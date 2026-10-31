# frozen_string_literal: true

require "pathname"
require "fileutils"
require "socket"
require "rbconfig"
require "etc"

require_relative "version"
require_relative "terminal"
require_relative "environment"
require_relative "templates"

module Railst
  class CLI
    def self.start(args = ARGV)
      new(args).run
    end

    def initialize(args)
      @args = args.dup
      @command = @args.shift || "help"
    end

    def run
      case @command
      when "s", "server", "run"
        run_server
      when "c", "console"
        run_console
      when "g", "generate"
        run_generate
      when "d", "destroy"
        run_destroy
      when "new"
        run_new
      when "t", "test"
        run_test
      when "test:rust", "t:rust"
        run_rust_test
      when "test:all", "t:all"
        run_all_tests
      when "r", "runner"
        run_runner
      when "routes"
        run_routes
      when "db"
        run_db
      when /\Adb:/
        run_db_task
      when "build", "rust:build"
        run_build
      when "clean", "rust:clean"
        run_clean
      when "doctor", "check"
        run_doctor
      when "bench", "benchmark"
        run_benchmark
      when "stats"
        run_stats
      when "ci"
        run_ci
      when "setup"
        run_setup
      when "install"
        run_install_cli
      when "version", "--version", "-v"
        show_version
      when "help", "--help", "-h"
        show_help
      else
        run_passthrough(@command)
      end
    end

    private

    def project_root
      @project_root ||= begin
        current = Pathname.pwd
        loop do
          return current if current.join("bin/rails").exist? && current.join("ext/rust_backend").exist?
          break if current.root?

          current = current.parent
        end
        nil
      end
    end

    def require_project_root!
      unless project_root
        puts ""
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} You must run this command inside a Rust on Rails project directory."
        puts ""
        exit 1
      end
    end

    def system_in_root(*cmd, exit_on_fail: true)
      require_project_root!
      success = false
      exit_code = 0

      Dir.chdir(project_root) do
        success = Kernel.system(Environment.toolchains_env, *cmd)
        exit_code = $?.exitstatus || (success ? 0 : 1)
      end

      exit(exit_code) if exit_on_fail && !success
      success
    end

    def exec_in_root(*cmd)
      require_project_root!
      Dir.chdir(project_root) do
        Kernel.exec(Environment.toolchains_env, *cmd)
      end
    end

    def rust_backend_stale?
      return false unless project_root

      so_path = project_root.join("lib/rust_backend/rust_backend.so")
      return true unless so_path.exist?

      so_mtime = so_path.mtime
      src_pattern = project_root.join("ext/rust_backend/**/*.{rs,toml,rb}").to_s
      Dir[src_pattern].any? do |f|
        next false if f.include?("/target/")

        File.mtime(f) > so_mtime
      end
    end

    def ensure_rust_built!
      require_project_root!
      return unless rust_backend_stale?

      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Rust extension is missing or modified. Recompiling..."
      puts ""

      success = system_in_root("bin/rake", "rust:build", exit_on_fail: false)
      unless success
        puts ""
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Rust compilation failed."
        puts ""
        exit 1
      end
    end

    # --- Server Command ---

    def parse_server_options(args)
      options = {
        host: "127.0.0.1",
        port: 3000,
        environment: ENV.fetch("RAILS_ENV", "development"),
        find_port: false,
        passthrough: []
      }

      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when "-p", "--port"
          i += 1
          options[:port] = args[i].to_i
        when /\A-p(\d+)\z/, /\A--port=(\d+)\z/
          options[:port] = $1.to_i
        when "-b", "-h", "--binding", "--host"
          i += 1
          options[:host] = args[i]
        when /\A-b(.+)\z/, /\A--binding=(.+)\z/, /\A--host=(.+)\z/
          options[:host] = $1
        when "-e", "--environment"
          i += 1
          options[:environment] = args[i]
        when /\A-e(.+)\z/, /\A--environment=(.+)\z/
          options[:environment] = $1
        when "-f", "--find-port"
          options[:find_port] = true
        else
          options[:passthrough] << arg
        end
        i += 1
      end

      options
    end

    def port_in_use?(host, port)
      check_hosts = [ host ]
      check_hosts << "127.0.0.1" if host == "0.0.0.0" || host == "localhost"
      check_hosts << "0.0.0.0" if host == "127.0.0.1"

      check_hosts.uniq.each do |h|
        server = TCPServer.new(h, port)
        server.close
      rescue Errno::EADDRINUSE, Errno::EACCES
        return true
      rescue StandardError
        # ignore other connection errors during check
      end
      false
    end

    def find_available_port(host, starting_port, max_tries = 20)
      candidate = starting_port
      max_tries.times do
        return candidate unless port_in_use?(host, candidate)

        candidate += 1
      end
      nil
    end

    def run_server
      require_project_root!
      ensure_rust_built!

      opts = parse_server_options(@args)
      host = opts[:host]
      port = opts[:port]
      env_name = opts[:environment]

      if port_in_use?(host, port)
        if opts[:find_port]
          next_port = find_available_port(host, port + 1)
          if next_port
            puts ""
            puts "   #{Terminal.badge("WARN", bg: :yellow, fg: :black)} Port #{port} is occupied. Using port #{next_port} instead."
            port = next_port
          else
            print_port_error(host, port)
            exit 1
          end
        else
          suggested_port = find_available_port(host, port + 1) || (port + 1)
          print_port_error(host, port, suggested_port)
          exit 1
        end
      end

      display_host = (host == "0.0.0.0") ? "127.0.0.1" : host
      puts ""
      puts "   #{Terminal.badge("INFO", bg: :green, fg: :black)} Server running on #{Terminal.bold_cyan("[http://#{display_host}:#{port}]")}."
      puts ""
      puts "  #{Terminal.dim("Press")} #{Terminal.bold("Ctrl+C")} #{Terminal.dim("to stop the server")}"
      puts ""
      puts "  #{Terminal.dim("Environment")} #{Terminal.dim(".........................................")} #{env_name}"
      puts "  #{Terminal.dim("Rust Backend")} #{Terminal.dim(".......................")} #{Terminal.green("Rayon + Magnus 0.9 (active)")}"
      puts ""

      exec_in_root("bin/rails", "server", "-b", host, "-p", port.to_s, "-e", env_name, *opts[:passthrough])
    end

    def print_port_error(host, port, suggested_port = nil)
      puts ""
      puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Failed to listen on #{host}:#{port} (Address already in use)."
      puts ""
      puts "  #{Terminal.dim("Port")} #{Terminal.bold(port)} #{Terminal.dim("is currently occupied by another process.")}"
      if suggested_port
        puts "  #{Terminal.dim("Try specifying a different port:")}"
        puts "    #{Terminal.bold_yellow("railst s -p #{suggested_port}")}"
        puts ""
        puts "  #{Terminal.dim("Or run with automatic port selection:")}"
        puts "    #{Terminal.bold_yellow("railst s --find-port")}"
      end
      puts ""
    end

    # --- Core Commands ---

    def run_console
      require_project_root!
      ensure_rust_built!
      exec_in_root("bin/rails", "console", *@args)
    end

    def run_generate
      require_project_root!
      ensure_rust_built!
      if @args.empty?
        exec_in_root("bin/rails", "generate", "--help")
      else
        system_in_root("bin/rails", "generate", *@args)
      end
    end

    def run_destroy
      require_project_root!
      system_in_root("bin/rails", "destroy", *@args)
    end

    def run_runner
      require_project_root!
      ensure_rust_built!
      exec_in_root("bin/rails", "runner", *@args)
    end

    def run_routes
      require_project_root!
      system_in_root("bin/rails", "routes", *@args)
    end

    def run_db
      require_project_root!
      sub = @args.shift || "migrate"
      system_in_root("bin/rails", "db:#{sub}", *@args)
    end

    def run_db_task
      require_project_root!
      system_in_root("bin/rails", @command, *@args)
    end

    def run_test
      require_project_root!
      if @args.empty?
        run_all_tests
      elsif @args.first == "rust"
        @args.shift
        run_rust_test
      elsif @args.first == "all"
        @args.shift
        run_all_tests
      else
        ensure_rust_built!
        system_in_root("bin/rails", "test", *@args)
      end
    end

    def run_rust_test
      require_project_root!
      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Running native Rust crate unit tests..."
      puts ""
      system_in_root("bin/rake", "rust:test")
    end

    def run_all_tests
      require_project_root!
      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Running native Rust tests..."
      puts ""
      rust_ok = system_in_root("bin/rake", "rust:test", exit_on_fail: false)

      puts ""
      puts "   #{Terminal.badge("INFO", bg: :green, fg: :black)} Running Rails test suite..."
      puts ""
      rails_ok = system_in_root("bin/rails", "test", exit_on_fail: false)

      exit((rust_ok && rails_ok) ? 0 : 1)
    end

    def run_build
      require_project_root!
      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Compiling Magnus Rust backend extension..."
      puts ""
      ok = system_in_root("bin/rake", "rust:build", exit_on_fail: false)
      if ok
        puts ""
        puts "   #{Terminal.badge("INFO", bg: :green, fg: :black)} Rust backend compiled successfully."
        puts ""
      else
        puts ""
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Rust compilation failed."
        puts ""
        exit 1
      end
    end

    def run_clean
      require_project_root!
      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Cleaning Rust build artifacts..."
      puts ""
      system_in_root("bin/rake", "rust:clean")
    end

    def run_setup
      require_project_root!
      system_in_root("bin/setup", *@args)
    end

    def run_ci
      require_project_root!
      system_in_root("bin/ci", *@args)
    end

    def run_passthrough(cmd)
      require_project_root!
      exec_in_root("bin/rails", cmd, *@args)
    end

    def run_new
      app_name = @args.shift
      if app_name.nil? || app_name.empty? || app_name.start_with?("-")
        puts ""
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Missing application name."
        puts ""
        puts "  Usage:"
        puts "    #{Terminal.bold_cyan("railst new <app_name> [rails_options]")}"
        puts ""
        puts "  Examples:"
        puts "    #{Terminal.bold_yellow("railst new my_app")}"
        puts "    #{Terminal.bold_yellow("railst new analytics_service -d postgresql")}"
        puts ""
        exit 1
      end

      target_dir = Pathname.pwd.join(app_name)
      if target_dir.exist?
        puts ""
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Destination directory '#{app_name}' already exists."
        puts ""
        exit 1
      end

      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Creating new Rails application: #{Terminal.bold(app_name)}..."
      puts ""

      rails_cmd = [ "rails", "new", app_name, *@args ]
      rails_success = Kernel.system(Environment.toolchains_env, *rails_cmd)
      unless rails_success
        puts ""
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Failed to create base Rails application."
        puts ""
        exit 1
      end

      puts ""
      puts "   #{Terminal.badge("INFO", bg: :cyan, fg: :black)} Injecting Rust on Rails architecture (Magnus 0.9 + Rayon + GVL)..."
      puts ""

      Templates.inject_into(target_dir, project_root)

      # Append rb_sys and railst into Gemfile if not present
      gemfile = target_dir.join("Gemfile")
      if gemfile.exist?
        gem_content = gemfile.read
        missing_gems = []
        missing_gems << '  gem "railst", "~> 0.2"' unless gem_content.include?("railst")
        missing_gems << '  gem "rb_sys", "~> 0.9"' unless gem_content.include?("rb_sys")

        unless missing_gems.empty?
          File.open(gemfile, "a") do |f|
            f.puts "\n# Rust on Rails development & build tooling\ngroup :development, :test do\n#{missing_gems.join("\n")}\nend\n"
          end
        end
      end

      # Copy railst CLI executable into bin/railst
      cli_source = File.expand_path($PROGRAM_NAME)
      dest_cli = target_dir.join("bin/railst")
      FileUtils.cp(cli_source, dest_cli)
      FileUtils.chmod(0755, dest_cli)

      puts ""
      puts "   #{Terminal.badge("INFO", bg: :green, fg: :black)} Compiling native Rust backend in #{app_name}..."
      puts ""

      Dir.chdir(target_dir) do
        Kernel.system(Environment.toolchains_env, "bundle", "install")
        success = Kernel.system(Environment.toolchains_env, "bin/rake", "rust:build")
        unless success
          puts ""
          puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Failed to compile native Rust backend."
          puts ""
          exit 1
        end
      end

      puts ""
      puts "   #{Terminal.badge("SUCCESS", bg: :green, fg: :black)} #{Terminal.bold("Rust on Rails application created successfully!")}"
      puts ""
      puts "  #{Terminal.dim("Get started:")}"
      puts "    #{Terminal.bold_yellow("cd #{app_name}")}"
      puts "    #{Terminal.bold_yellow("railst s")}"
      puts ""
    end

    def run_doctor
      puts ""
      puts "   #{Terminal.bold_cyan("=== Rust on Rails System Diagnostics ===")}"
      puts ""

      # 1. Ruby & C Headers
      ruby_ver = "#{RUBY_VERSION} (#{RUBY_PLATFORM})"
      hdr_dir = RbConfig::CONFIG["rubyhdrdir"]
      hdr_file = hdr_dir ? File.join(hdr_dir, "ruby.h") : nil
      hdr_ok = hdr_file && File.exist?(hdr_file)

      if hdr_ok
        puts "  #{Terminal.green("✓")} #{Terminal.bold("Ruby")}: #{ruby_ver}"
        puts "  #{Terminal.green("✓")} #{Terminal.bold("Ruby C-Headers")}: #{hdr_file}"
      else
        puts "  #{Terminal.yellow("!")} #{Terminal.bold("Ruby")}: #{ruby_ver}"
        puts "  #{Terminal.red("✗")} #{Terminal.bold("Ruby C-Headers")}: Not found in #{hdr_dir || 'unknown'}"
      end

      # 2. Rust & Cargo
      env = Environment.toolchains_env
      cargo_ver = `cargo --version 2>/dev/null`.strip
      rustc_ver = `rustc --version 2>/dev/null`.strip

      if !cargo_ver.empty? && !rustc_ver.empty?
        puts "  #{Terminal.green("✓")} #{Terminal.bold("Rust Toolchain")}: #{rustc_ver}, #{cargo_ver}"
      else
        puts "  #{Terminal.red("✗")} #{Terminal.bold("Rust Toolchain")}: cargo/rustc not found in PATH."
        puts "    #{Terminal.dim("Hint: Install Rust via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh")}"
      end

      # 3. LLVM / Clang
      libclang = env["LIBCLANG_PATH"]
      libclang_so = libclang ? Dir[File.join(libclang, "libclang.so*")].first : nil

      if libclang_so
        puts "  #{Terminal.green("✓")} #{Terminal.bold("LLVM / Clang")}: #{libclang_so}"
      else
        puts "  #{Terminal.yellow("!")} #{Terminal.bold("LLVM / Clang")}: libclang.so not detected in standard paths."
        puts "    #{Terminal.dim("Hint: Install libclang-dev (e.g. sudo apt install libclang-dev)")}"
      end

      # 4. Multi-Core Hardware Detection (Rayon)
      cores = Etc.nprocessors
      puts "  #{Terminal.green("✓")} #{Terminal.bold("Multi-Core Hardware")}: #{cores} physical/logical CPU cores (Rayon ready)"

      # 5. Project-Specific Status (if inside project)
      if project_root
        puts ""
        puts "  #{Terminal.bold_cyan("Project Status:")} #{project_root}"

        so_path = project_root.join("lib/rust_backend/rust_backend.so")
        if so_path.exist?
          stale = rust_backend_stale?
          size_kb = (so_path.size / 1024.0).round(1)
          if stale
            puts "  #{Terminal.yellow("!")} #{Terminal.bold("Rust Backend")}: Compiled (#{size_kb} KB) but #{Terminal.yellow("source files are newer")}."
            puts "    #{Terminal.dim("Hint: Run 'railst build' to recompile.")}"
          else
            puts "  #{Terminal.green("✓")} #{Terminal.bold("Rust Backend")}: Compiled and up-to-date (#{size_kb} KB)"
          end
        else
          puts "  #{Terminal.red("✗")} #{Terminal.bold("Rust Backend")}: Not yet compiled."
          puts "    #{Terminal.dim("Hint: Run 'railst build' to compile.")}"
        end

        schema_file = project_root.join("db/schema.rb")
        if schema_file.exist?
          puts "  #{Terminal.green("✓")} #{Terminal.bold("Database Schema")}: Present (#{schema_file})"
        end
      else
        puts ""
        puts "  #{Terminal.dim("(Run inside a Rust on Rails project directory for local extension diagnostics)")}"
      end

      puts ""
      puts "  #{Terminal.dim("System ready for high-performance Rust on Rails computing.")}"
      puts ""
    end

    def run_benchmark
      require_project_root!
      ensure_rust_built!

      count = (@args.first || 25_000).to_i.clamp(1_000, 200_000)

      puts ""
      puts "   #{Terminal.badge("BENCH", bg: :magenta, fg: :white)} #{Terminal.bold("Running Rust on Rails In-Process Performance Benchmark")}"
      puts "  Dataset: #{Terminal.bold(count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse)} in-memory record hashes"
      puts ""

      runner_code = <<~RUBY
        count = #{count}
        data = Array.new(count) { |i| { "id" => i, "value" => (i * 1.5).round(2) } }
        cfg = { "multiplier" => 1.25, "compute_field" => "value" }

        # 1. Pure Ruby Sequential Batch
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ruby_res = data.map do |d|
          d.merge("value_computed" => d["value"] * 1.25, "processed_by" => "ruby")
        end
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ruby_batch_ms = ((t1 - t0) * 1000.0).round(2)

        # 2. Rust Multi-Core Rayon Batch
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rust_res = RustBackend.process_batch(data, cfg)
        t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rust_batch_ms = ((t3 - t2) * 1000.0).round(2)

        # 3. Rust Parallel Reduction Metrics
        t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        metrics = RustBackend.aggregate_metrics(data, "value")
        t5 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rust_metric_ms = ((t5 - t4) * 1000.0).round(2)

        cores = Etc.nprocessors
        ruby_thru = (count / [ruby_batch_ms / 1000.0, 0.001].max).round
        rust_thru = (count / [rust_batch_ms / 1000.0, 0.001].max).round

        puts "RESULTS:"
        puts "\#{ruby_batch_ms}|\#{rust_batch_ms}|\#{rust_metric_ms}|\#{ruby_thru}|\#{rust_thru}|\#{cores}"
      RUBY

      out = nil
      Dir.chdir(project_root) do
        out = `bin/rails runner '#{runner_code}' 2>/dev/null`
      end

      if out && out.include?("RESULTS:")
        line = out.lines.find { |l| l.include?("|") }&.strip
        if line
          ruby_ms, rust_ms, metric_ms, ruby_thru, rust_thru, cores = line.split("|")

          puts "  +---------------------------+----------------+----------------+"
          puts "  | Operation                 | Pure Ruby      | Rust (Rayon)   |"
          puts "  +---------------------------+----------------+----------------+"
          puts "  | Batch Compute Latency     | #{ruby_ms.rjust(11)} ms | #{Terminal.bold_green(rust_ms.rjust(11) + ' ms')} |"
          puts "  | Parallel Metrics (5 ops)  |            N/A | #{Terminal.bold_cyan(metric_ms.rjust(11) + ' ms')} |"
          puts "  | Processing Throughput     | #{ruby_thru.rjust(9)} rec/s | #{Terminal.bold_green(rust_thru.rjust(9) + ' rec/s')} |"
          puts "  +---------------------------+----------------+----------------+"
          puts ""
          puts "  #{Terminal.dim("Hardware Acceleration:")} #{Terminal.bold(cores)} CPU cores #{Terminal.dim("(Rayon parallel pool, Ruby GVL released)")}"
          puts ""
        end
      else
        puts "   #{Terminal.badge("ERROR", bg: :red, fg: :white)} Failed to execute benchmark runner."
      end
    end

    def run_stats
      require_project_root!
      system_in_root("bin/rails", "stats")

      puts ""
      puts "  #{Terminal.bold_cyan("Rust Native Code Statistics:")}"
      crate_dir = project_root.join("ext/rust_backend")
      if crate_dir.exist?
        rs_files = Dir[crate_dir.join("src/**/*.rs")]
        total_lines = 0
        test_count = 0

        puts "  +-------------------------------+-------+-------+"
        puts "  | Rust Module                   | Lines | Tests |"
        puts "  +-------------------------------+-------+-------+"

        rs_files.sort.each do |f|
          name = Pathname.new(f).relative_path_from(crate_dir).to_s
          content = File.read(f)
          lines = content.lines.count
          tests = content.scan(/#\[test\]/).count
          total_lines += lines
          test_count += tests
          puts "  | #{name.ljust(29)} | #{lines.to_s.rjust(5)} | #{tests.to_s.rjust(5)} |"
        end

        puts "  +-------------------------------+-------+-------+"
        puts "  | #{Terminal.bold('Total Rust Backend')}           | #{Terminal.bold(total_lines.to_s.rjust(5))} | #{Terminal.bold(test_count.to_s.rjust(5))} |"
        puts "  +-------------------------------+-------+-------+"
        puts ""
      end
    end

    def run_install_cli
      user_gem_bin = `ruby -r rubygems -e "puts Gem.user_dir" 2>/dev/null`.strip
      dest_dirs = []
      dest_dirs << File.join(user_gem_bin, "bin") if !user_gem_bin.empty? && File.directory?(user_gem_bin)
      dest_dirs << File.expand_path("~/.local/bin")

      source_script = File.expand_path($PROGRAM_NAME)

      dest_dirs.uniq.each do |dest_dir|
        FileUtils.mkdir_p(dest_dir)
        dest_path = File.join(dest_dir, "railst")
        FileUtils.cp(source_script, dest_path)
        File.chmod(0755, dest_path)
        puts "   #{Terminal.badge("INFO", bg: :green, fg: :black)} Installed railst CLI to: #{dest_path}"
      end

      puts ""
      puts "  #{Terminal.dim("You can now run")} #{Terminal.bold_cyan("railst <command>")} #{Terminal.dim("from any directory!")}"
      puts ""
    end

    def show_version
      puts "Rust on Rails CLI v#{VERSION} (Rails 8 + Magnus 0.9 + Rayon)"
      if project_root
        rails_ver = `bin/rails --version 2>/dev/null`.strip
        rust_ver = `rustc --version 2>/dev/null`.strip
        puts "  Rails: #{rails_ver}" unless rails_ver.empty?
        puts "  Rust:  #{rust_ver}" unless rust_ver.empty?
      end
    end

    def show_help
      puts <<~HELP

        Usage: railst <command> [options]

        Core Rails Commands (with Rust Acceleration):
          railst s, server           Start the Rails server (auto-builds Rust backend)
          railst c, console          Start the interactive Rails console
          railst g, generate         Run Rails & Rust code generators
          railst d, destroy          Remove generated code
          railst t, test [path]      Run test suite (Rust crate tests + Rails tests)
          railst r, runner <code>    Run Ruby code in application context
          railst new <app_name>      Create a new Rust on Rails application

        Database Commands:
          railst db [action]         Run database task (migrate, rollback, prepare, seed, reset)
          railst db:migrate          Run database migrations (supports all db:* tasks)

        Rust on Rails Tooling:
          railst build               Compile the native Rust crate (cargo build --release)
          railst clean               Clean Rust build artifacts (cargo clean)
          railst doctor              Diagnose Ruby, Rust, LLVM/Clang, and Magnus environment
          railst bench [count]       Run CLI multi-core vs Ruby benchmark (default: 25,000)
          railst ci                  Run the full Continuous Integration verification suite
          railst routes              List all application routes
          railst stats               Report code statistics (Ruby + Rust lines of code)
          railst install             Install railst globally into user's PATH
          railst version, -v         Display framework version
          railst help, -h            Show this help message

        Options for 'railst server':
          -p, --port <port>          Specify server port (default: 3000)
          -b, --binding <host>       Specify IP binding (default: 127.0.0.1)
          -e, --environment <env>    Specify environment (default: development)
          -f, --find-port            Auto-select next available port if default is occupied

        Examples:
          railst s
          railst s -p 3001 --find-port
          railst g rust:resource Transaction amount:decimal status:string
          railst c
          railst t
          railst t:rust
          railst doctor
          railst bench 50000
          railst db:migrate

      HELP
    end
  end
end

# frozen_string_literal: true

module Railst
  module Environment
    def self.toolchains_env
      env = ENV.to_h

      # Dynamically detect gem user bin, cargo bin, and local bin
      gem_bin = begin
        user_dir = `ruby -r rubygems -e "puts Gem.user_dir" 2>/dev/null`.strip
        File.join(user_dir, "bin") unless user_dir.empty?
      rescue StandardError
        nil
      end

      cargo_bin = File.expand_path("~/.cargo/bin")
      local_bin = File.expand_path("~/.local/bin")

      current_paths = env.fetch("PATH", "").split(File::PATH_SEPARATOR)
      [ cargo_bin, local_bin, gem_bin ].compact.each do |p|
        current_paths.unshift(p) if File.directory?(p) && !current_paths.include?(p)
      end
      env["PATH"] = current_paths.join(File::PATH_SEPARATOR)

      # Automatic LLVM / Clang detection for bindgen & rb-sys
      unless env["LIBCLANG_PATH"]
        candidate_lib_paths = [
          File.expand_path("~/.local/lib"),
          "/usr/lib/llvm-23/lib",
          "/usr/lib/llvm-22/lib",
          "/usr/lib/llvm-21/lib",
          "/usr/lib/llvm-20/lib",
          "/usr/lib/llvm-19/lib",
          "/usr/lib/llvm-18/lib",
          "/usr/lib",
          "/usr/local/lib"
        ]
        found_lib = candidate_lib_paths.find do |dir|
          File.directory?(dir) && !Dir[File.join(dir, "libclang.so*")].empty?
        end
        env["LIBCLANG_PATH"] = found_lib if found_lib
      end

      unless env["BINDGEN_EXTRA_CLANG_ARGS"]
        candidate_include_paths = [
          File.expand_path("~/.local/lib/clang/23/include"),
          "/usr/lib/clang/23/include",
          "/usr/lib/clang/22/include",
          "/usr/lib/clang/21/include",
          "/usr/lib/clang/20/include",
          "/usr/lib/clang/19/include",
          "/usr/lib/clang/18/include"
        ]
        found_inc = candidate_include_paths.find { |dir| File.directory?(dir) }
        env["BINDGEN_EXTRA_CLANG_ARGS"] = "-I#{found_inc}" if found_inc
      end

      # Quiet down noisy glib / libvips system module warnings
      env["VIPS_WARNING"] = "0"
      env["G_MESSAGES_DEBUG"] = "none"

      env
    end
  end
end

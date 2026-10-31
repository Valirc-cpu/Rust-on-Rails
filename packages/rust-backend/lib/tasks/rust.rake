# frozen_string_literal: true

def rust_build_env
  cargo_path = File.expand_path("~/.cargo/bin")
  env = {
    "LIBCLANG_PATH" => ENV["LIBCLANG_PATH"] || File.expand_path("~/.local/lib"),
    "BINDGEN_EXTRA_CLANG_ARGS" => ENV["BINDGEN_EXTRA_CLANG_ARGS"] || "-I#{File.expand_path('~/.local/lib/clang/23/include')}"
  }
  env["PATH"] = "#{cargo_path}:#{ENV['PATH']}" unless ENV["PATH"].include?(cargo_path)
  env
end

namespace :rust do
  desc "Build the Magnus Rust backend extension"
  task :build do
    puts "[RustBackend] Compiling Rust crate..."
    crate_dir = Rails.root.join("ext/rust_backend")
    target_dir = Rails.root.join("lib/rust_backend")
    FileUtils.mkdir_p(target_dir)

    system(rust_build_env, "cargo build --release", chdir: crate_dir.to_s, exception: true)

    source_so = crate_dir.join("target/release/librust_backend.so")
    dest_so = target_dir.join("rust_backend.so")

    FileUtils.cp(source_so, dest_so)
    puts "[RustBackend] Built and copied extension to #{dest_so}"
  end

  desc "Run native Rust tests in ext/rust_backend"
  task :test do
    crate_dir = Rails.root.join("ext/rust_backend")
    system(rust_build_env, "cargo test", chdir: crate_dir.to_s, exception: true)
  end

  desc "Clean compiled Rust artifacts"
  task :clean do
    crate_dir = Rails.root.join("ext/rust_backend")
    system(rust_build_env, "cargo clean", chdir: crate_dir.to_s)
    FileUtils.rm_f(Rails.root.join("lib/rust_backend/rust_backend.so"))
    puts "[RustBackend] Cleaned Rust build artifacts."
  end
end

# Automatically build Rust extension before tests if not already present
task test: "rust:build"

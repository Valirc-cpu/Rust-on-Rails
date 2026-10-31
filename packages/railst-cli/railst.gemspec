# frozen_string_literal: true

require_relative "lib/railst/version"

Gem::Specification.new do |spec|
  spec.name          = "railst"
  spec.version       = Railst::VERSION
  spec.authors       = [ "Valirc-cpu" ]
  spec.email         = [ "taltagemilang@gmail.com" ]
  spec.summary       = "CLI and Installer for the Rust on Rails High-Performance Framework"
  spec.description   = "Standalone developer interface and scaffolding tool for combining Rails 8 and pure Rust"
  spec.homepage      = "https://github.com/Valirc-cpu/Rust-on-Rails"
  spec.license       = "MIT"

  spec.metadata["source_code_uri"] = "https://github.com/Valirc-cpu/Rust-on-Rails"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Valirc-cpu/Rust-on-Rails/issues"
  spec.metadata["changelog_uri"]   = "https://github.com/Valirc-cpu/Rust-on-Rails/blob/main/README.md"

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "exe/*", "README.md"]
  end
  spec.bindir        = "exe"
  spec.executables   = [ "railst" ]
  spec.require_paths = [ "lib" ]

  spec.required_ruby_version = ">= 3.2.0"
end

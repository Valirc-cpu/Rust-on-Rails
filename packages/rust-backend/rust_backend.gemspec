# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "rust_backend"
  spec.version       = "0.2.1"
  spec.authors       = [ "Valirc-cpu" ]
  spec.email         = [ "taltagemilang@gmail.com" ]
  spec.summary       = "Native in-process Rust data processing extension for Rails 8 with Magnus and Rayon"
  spec.description   = "Multi-core parallel data transformations, reductions, and GVL release for Ruby on Rails"
  spec.homepage      = "https://github.com/Valirc-cpu/Rust-on-Rails"
  spec.license       = "MIT"

  spec.metadata["source_code_uri"] = "https://github.com/Valirc-cpu/Rust-on-Rails"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Valirc-cpu/Rust-on-Rails/issues"

  spec.files         = Dir["lib/**/*", "ext/**/*.{rs,toml,rb}", "README.md"]
  spec.require_paths = [ "lib" ]
  spec.extensions    = [ "ext/rust_backend/extconf.rb" ]

  spec.add_dependency "rb_sys", "~> 0.9"

  spec.required_ruby_version = ">= 3.2.0"
end

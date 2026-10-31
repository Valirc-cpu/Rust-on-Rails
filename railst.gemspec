# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "railst"
  spec.version       = "0.1.0"
  spec.authors       = ["HarmlessValve"]
  spec.email         = ["Altagemilang@protonmail.com"]
  spec.summary       = "High-Performance Data Processing Framework combining Rails 8 and pure Rust"
  spec.description   = "In-process Rust backend extension for Rails 8 with Magnus and Rayon"
  spec.homepage      = "https://github.com/HarmlessValve/Rust-on-Ruby"
  spec.license       = "MIT"

  spec.files         = Dir["{app,bin,config,db,exe,ext,lib,public}/**/*", "Gemfile", "Rakefile", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = ["railst"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.4.0"
end

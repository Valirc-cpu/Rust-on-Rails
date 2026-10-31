# frozen_string_literal: true

module RustBackend
  # Load the Magnus-compiled native extension
  begin
    require_relative "rust_backend/rust_backend"
  rescue LoadError
    require_relative "../ext/rust_backend/rust_backend"
  end
end

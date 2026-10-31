# frozen_string_literal: true

require "rails/generators"

module Rust
  module Generators
    class ServiceGenerator < Rails::Generators::NamedBase
      desc "Generates a Ruby service backed by the Magnus Rust extension"

      source_root File.expand_path("templates", __dir__)

      def create_service_file
        create_file "app/services/rust/#{file_name}_service.rb", <<-RUBY
# frozen_string_literal: true

module Rust
  class #{class_name}Service
    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end

    def initialize(*args, **kwargs)
      @args = args
      @kwargs = kwargs
    end

    def call
      # Delegating business logic to Magnus Rust backend
      # Example: RustBackend.calculate(...) or custom Rust module
      RustBackend.hello("#{class_name}")
    end
  end
end
RUBY
      end

      def create_test_file
        create_file "test/services/rust/#{file_name}_service_test.rb", <<-RUBY
# frozen_string_literal: true

require "test_helper"

class Rust::#{class_name}ServiceTest < ActiveSupport::TestCase
  test "executes rust-backed service" do
    result = Rust::#{class_name}Service.call
    assert_includes result, "Hello #{class_name} from Rust"
  end
end
RUBY
      end
    end
  end
end

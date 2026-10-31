# frozen_string_literal: true

require "test_helper"

class RustBackendTest < ActiveSupport::TestCase
  test "rust hello returns greeting" do
    assert_equal "Hello World from Rust (Magnus)!", RustBackend.hello("World")
  end

  test "rust calculate performs arithmetic correctly" do
    assert_equal 42.0, RustBackend.calculate(40.0, 2.0, "add")
    assert_equal 25.0, RustBackend.calculate(100.0, 4.0, "div")
  end

  test "rust calculate raises zero division error on divide by zero" do
    assert_raises(ZeroDivisionError) do
      RustBackend.calculate(10.0, 0.0, "div")
    end
  end

  test "rust process_record enriches ruby hash" do
    input = { "name" => "Item A", "price" => 100 }
    result = RustBackend.process_record(input)
    assert_equal true, result["rust_processed"]
    assert_equal "magnus-0.9", result["rust_engine"]
    assert_equal 100, result["price"]
  end
end

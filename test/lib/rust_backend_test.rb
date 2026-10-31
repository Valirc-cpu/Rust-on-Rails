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

  test "rust process_batch transforms dynamic hashes in parallel with rayon" do
    input = [
      { "id" => 1, "value" => 10.0 },
      { "id" => 2, "value" => 20.0 }
    ]
    result = RustBackend.process_batch(input, { "multiplier" => 2.5, "compute_field" => "value" })
    assert_equal 2, result.size
    assert_equal 25.0, result.first["value_computed"]
    assert_equal true, result.first["gvl_released"]
  end

  test "rust aggregate_metrics computes parallel statistical reductions" do
    input = [
      { "score" => 10.0 },
      { "score" => 30.0 }
    ]
    summary = RustBackend.aggregate_metrics(input, "score")
    assert_equal 2, summary["count"]
    assert_equal 40.0, summary["sum"]
    assert_equal 20.0, summary["avg"]
    assert_equal 10.0, summary["min"]
    assert_equal 30.0, summary["max"]
    assert_equal "rayon", summary["parallel_engine"]
  end
end

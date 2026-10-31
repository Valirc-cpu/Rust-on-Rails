# frozen_string_literal: true

require "test_helper"

class DataPointsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get data_points_url, as: :json
    assert_response :success
  end

  test "should process batch in parallel via Rust" do
    post process_batch_data_points_url, params: { records: [{ value: 10.0 }], config: { multiplier: 2.0 } }, as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response["count"]
    assert_equal true, json_response["data"].first["gvl_released"]
  end

  test "should compute parallel metrics via Rust" do
    get metrics_data_points_url, params: { field: "device_id" }, as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "rayon", json_response["parallel_engine"]
  end
end

# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get root landing page" do
    get root_url
    assert_response :success
    assert_select "h1.hero-headline", /The Velocity of Rails/
    assert_select "span.brand-name", "Railst"
  end

  test "should execute in-process benchmark endpoint" do
    post benchmark_url, params: { count: 1000 }, as: :json
    assert_response :success

    json = response.parsed_body
    assert_equal "ok", json["status"]
    assert_equal 1000, json["records"]
    assert json["duration_ms"].is_a?(Numeric)
    assert_equal "rayon", json["metrics"]["parallel_engine"]
    assert_equal true, json["gvl_released"]
  end
end

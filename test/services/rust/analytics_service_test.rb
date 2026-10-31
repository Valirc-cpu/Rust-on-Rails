# frozen_string_literal: true

require "test_helper"

class Rust::AnalyticsServiceTest < ActiveSupport::TestCase
  test "executes rust-backed service" do
    result = Rust::AnalyticsService.call
    assert_includes result, "Hello Analytics from Rust"
  end
end

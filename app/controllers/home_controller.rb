# frozen_string_literal: true

require "etc"

class HomeController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :benchmark ]

  def index
    @ruby_version = RUBY_DESCRIPTION
    @rails_version = Rails.version
    @environment = Rails.env
    @rust_loaded = defined?(RustBackend) && RustBackend.respond_to?(:aggregate_metrics)
    @cpu_cores = Etc.nprocessors
    @db_adapter = ActiveRecord::Base.connection.adapter_name
  end

  def benchmark
    count = (params[:count] || 10_000).to_i.clamp(1_000, 100_000)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    data = Array.new(count) { |i| { "id" => i, "val" => (i * 1.5).round(2) } }
    metrics = RustBackend.aggregate_metrics(data, "val")

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0).round(2)

    render json: {
      status: "ok",
      records: count,
      duration_ms: duration_ms,
      metrics: metrics,
      engine: "Magnus 0.9 + Rayon Multi-Core",
      gvl_released: true,
      timestamp: Time.current.iso8601
    }
  rescue StandardError => e
    render json: { status: "error", error: e.message }, status: :internal_server_error
  end
end

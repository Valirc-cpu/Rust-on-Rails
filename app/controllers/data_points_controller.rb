# frozen_string_literal: true

class DataPointsController < ApplicationController
  before_action :set_data_point, only: %i[show update destroy]

  # GET /data_points
  def index
    @data_points = DataPoint.all
    render json: @data_points
  end

  # GET /data_points/1
  def show
    render json: @data_point.process_with_rust
  end

  # POST /data_points
  def create
    @data_point = DataPoint.new(data_point_params)

    if @data_point.save
      render json: @data_point.process_with_rust, status: :created
    else
      render json: @data_point.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /data_points/1
  def update
    if @data_point.update(data_point_params)
      render json: @data_point.process_with_rust
    else
      render json: @data_point.errors, status: :unprocessable_entity
    end
  end

  # DELETE /data_points/1
  def destroy
    @data_point.destroy!
  end

  # POST /data_points/process_batch
  # High-performance parallel dynamic hash processing in Rust (Rayon, GVL released)
  def process_batch
    raw = params[:records]
    records = if raw.present?
      raw.map { |r| r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r }
    else
      DataPoint.limit(10_000).as_json
    end
    cfg = params[:config]
    config = if cfg.present?
      cfg.respond_to?(:to_unsafe_h) ? cfg.to_unsafe_h : cfg
    else
      { "multiplier" => 1.0, "compute_field" => "value" }
    end

    processed = DataPoint.rust_batch_process(records, config)
    render json: { count: processed.size, data: processed }
  end

  # GET /data_points/metrics?field=...
  # High-performance parallel aggregation in Rust (Rayon, GVL released)
  def metrics
    field = params[:field] || "device_id"
    summary = DataPoint.rust_aggregate(DataPoint.all, field)
    render json: summary
  end

  private

  def set_data_point
    @data_point = DataPoint.find(params[:id])
  end

  def data_point_params
    params.require(:data_point).permit(:device_id, :value, :status)
  end
end

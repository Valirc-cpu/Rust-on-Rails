# frozen_string_literal: true

require "rails/generators"
require "rails/generators/resource_helpers"

module Rust
  module Generators
    class ResourceGenerator < Rails::Generators::NamedBase
      include Rails::Generators::ResourceHelpers

      desc "Generates a complete Rust-backed resource (Migration, Model with RustBacked, Controller with batch/metrics endpoints, and Routes)"

      argument :attributes, type: :array, default: [], banner: "field[:type] field[:type]"

      def create_model_and_migration
        generate "model", "#{name} #{attributes.map { |a| "#{a.name}:#{a.type}" }.join(' ')}"
      end

      def inject_rust_backed_into_model
        model_path = "app/models/#{file_name}.rb"
        inject_into_class model_path, class_name do
          "  include RustBacked\n"
        end
      end

      def create_controller_file
        attrs_permitted = attributes.map { |a| ":#{a.name}" }.join(", ")
        metric_default = attributes.first&.name || "id"

        template_content = <<~RUBY
          # frozen_string_literal: true

          class #{controller_class_name}Controller < ApplicationController
            before_action :set_#{singular_name}, only: %i[show update destroy]

            # GET /#{plural_name}
            def index
              @#{plural_name} = #{class_name}.all
              render json: @#{plural_name}
            end

            # GET /#{plural_name}/1
            def show
              render json: @#{singular_name}.process_with_rust
            end

            # POST /#{plural_name}
            def create
              @#{singular_name} = #{class_name}.new(#{singular_name}_params)

              if @#{singular_name}.save
                render json: @#{singular_name}.process_with_rust, status: :created
              else
                render json: @#{singular_name}.errors, status: :unprocessable_entity
              end
            end

            # PATCH/PUT /#{plural_name}/1
            def update
              if @#{singular_name}.update(#{singular_name}_params)
                render json: @#{singular_name}.process_with_rust
              else
                render json: @#{singular_name}.errors, status: :unprocessable_entity
              end
            end

            # DELETE /#{plural_name}/1
            def destroy
              @#{singular_name}.destroy!
            end

            # POST /#{plural_name}/process_batch
            # High-performance parallel dynamic hash processing in Rust (Rayon, GVL released)
            def process_batch
              raw = params[:records]
              records = if raw.present?
                raw.map { |r| r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r }
              else
                #{class_name}.limit(10_000).as_json
              end
              cfg = params[:config]
              config = if cfg.present?
                cfg.respond_to?(:to_unsafe_h) ? cfg.to_unsafe_h : cfg
              else
                { "multiplier" => 1.0, "compute_field" => "value" }
              end

              processed = #{class_name}.rust_batch_process(records, config)
              render json: { count: processed.size, data: processed }
            end

            # GET /#{plural_name}/metrics?field=...
            # High-performance parallel aggregation in Rust (Rayon, GVL released)
            def metrics
              field = params[:field] || "#{metric_default}"
              summary = #{class_name}.rust_aggregate(#{class_name}.all, field)
              render json: summary
            end

            private

            def set_#{singular_name}
              @#{singular_name} = #{class_name}.find(params[:id])
            end

            def #{singular_name}_params
              params.require(:#{singular_name}).permit(#{attrs_permitted})
            end
          end
        RUBY

        create_file "app/controllers/#{controller_file_name}_controller.rb", template_content
      end

      def add_resource_routes
        route_definition = <<~RUBY
          resources :#{plural_name} do
            collection do
              post :process_batch
              get :metrics
            end
          end
        RUBY
        route route_definition
      end

      def create_controller_test
        metric_default = attributes.first&.name || "id"

        test_content = <<~RUBY
          # frozen_string_literal: true

          require "test_helper"

          class #{controller_class_name}ControllerTest < ActionDispatch::IntegrationTest
            test "should get index" do
              get #{plural_name}_url, as: :json
              assert_response :success
            end

            test "should process batch in parallel via Rust" do
              post process_batch_#{plural_name}_url, params: { records: [{ value: 10.0 }], config: { multiplier: 2.0 } }, as: :json
              assert_response :success
              json_response = JSON.parse(response.body)
              assert_equal 1, json_response["count"]
              assert_equal true, json_response["data"].first["gvl_released"]
            end

            test "should compute parallel metrics via Rust" do
              get metrics_#{plural_name}_url, params: { field: "#{metric_default}" }, as: :json
              assert_response :success
              json_response = JSON.parse(response.body)
              assert_equal "rayon", json_response["parallel_engine"]
            end
          end
        RUBY

        create_file "test/controllers/#{controller_file_name}_controller_test.rb", test_content
      end
    end
  end
end

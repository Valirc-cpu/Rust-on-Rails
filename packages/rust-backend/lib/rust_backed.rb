# frozen_string_literal: true

module RustBacked
  extend ActiveSupport::Concern

  included do
    # ActiveSupport concern for models integrating with Magnus Rust extension
  end

  def process_with_rust
    RustBackend.process_record(attributes)
  end

  class_methods do
    # Perform arithmetic/primitive computation in native Rust
    def rust_compute(op, a, b)
      RustBackend.calculate(a.to_f, b.to_f, op.to_s)
    end

    # Batch process dynamic records across CPU cores with Rayon and GVL released
    def rust_batch_process(scope_or_hashes, config = {})
      raw = if scope_or_hashes.respond_to?(:map)
        scope_or_hashes.map { |r| r.respond_to?(:attributes) ? r.attributes : r }
      else
        scope_or_hashes
      end
      RustBackend.process_batch(raw, config.stringify_keys)
    end

    # High speed parallel statistical aggregation across CPU cores (GVL released)
    def rust_aggregate(scope_or_hashes, field)
      raw = if scope_or_hashes.respond_to?(:map)
        scope_or_hashes.map { |r| r.respond_to?(:attributes) ? r.attributes : r }
      else
        scope_or_hashes
      end
      RustBackend.aggregate_metrics(raw, field.to_s)
    end
  end
end

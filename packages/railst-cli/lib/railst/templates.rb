# frozen_string_literal: true

require "pathname"
require "fileutils"

module Railst
  module Templates
    def self.inject_into(target_dir, source_project_root = nil)
      target_path = Pathname.new(target_dir)

      # 1. Check for template in monorepo packages/template or source root
      monorepo_template = nil
      if source_project_root
        candidates = [
          source_project_root.join("packages/template"),
          source_project_root
        ]
        monorepo_template = candidates.find { |c| c.join("ext/rust_backend").exist? }
      end

      if monorepo_template
        # Copy backend & support files from existing monorepo template
        copy_tree(monorepo_template.join("ext/rust_backend"), target_path.join("ext/rust_backend"))
        copy_file_safe(monorepo_template.join("app/models/concerns/rust_backed.rb"), target_path.join("app/models/concerns/rust_backed.rb"))
        copy_file_safe(monorepo_template.join("config/initializers/rust_backend.rb"), target_path.join("config/initializers/rust_backend.rb"))
        copy_file_safe(monorepo_template.join("lib/rust_backend.rb"), target_path.join("lib/rust_backend.rb"))
        copy_file_safe(monorepo_template.join("lib/tasks/rust.rake"), target_path.join("lib/tasks/rust.rake"))
        copy_tree(monorepo_template.join("lib/generators/rust"), target_path.join("lib/generators/rust"))
      else
        # Self-contained embedded template generation
        write_embedded_templates(target_path)
      end

      # Update config/application.rb for autoloading
      app_rb = target_path.join("config/application.rb")
      if app_rb.exist?
        code = app_rb.read
        autoload_line = "config.autoload_lib(ignore: %w[assets tasks generators rust_backend])"
        unless code.include?(autoload_line)
          code.sub!(/class Application < Rails::Application\n/) do |m|
            "#{m}    #{autoload_line}\n"
          end
          app_rb.write(code)
        end
      end
    end

    def self.copy_tree(src, dst)
      return unless src.exist?

      FileUtils.mkdir_p(dst)
      FileUtils.cp_r(File.join(src, "."), dst)
      FileUtils.rm_rf(File.join(dst, "target"))
    end

    def self.copy_file_safe(src, dst)
      return unless src.exist?

      FileUtils.mkdir_p(dst.parent)
      FileUtils.cp(src, dst)
    end

    def self.write_embedded_templates(target_path)
      files = {
        "ext/rust_backend/Cargo.toml" => cargo_toml_content,
        "ext/rust_backend/extconf.rb" => extconf_rb_content,
        "ext/rust_backend/src/lib.rs" => lib_rs_content,
        "ext/rust_backend/src/gvl.rs" => gvl_rs_content,
        "ext/rust_backend/src/dynamic_hash.rs" => dynamic_hash_rs_content,
        "ext/rust_backend/src/data_processor.rs" => data_processor_rs_content,
        "app/models/concerns/rust_backed.rb" => rust_backed_rb_content,
        "config/initializers/rust_backend.rb" => initializer_content,
        "lib/rust_backend.rb" => loader_content,
        "lib/tasks/rust.rake" => rake_task_content
      }

      files.each do |rel_path, content|
        full_path = target_path.join(rel_path)
        FileUtils.mkdir_p(full_path.parent)
        full_path.write(content)
      end
    end

    def self.cargo_toml_content
      <<~TOML
        [package]
        name = "rust_backend"
        version = "0.1.0"
        edition = "2021"

        [lib]
        crate-type = ["cdylib"]

        [dependencies]
        magnus = { version = "0.9", features = ["rb-sys"] }
        rb-sys = "0.9"
        rayon = "1.10"
        serde = { version = "1.0", features = ["derive"] }
        serde_json = "1.0"
      TOML
    end

    def self.extconf_rb_content
      <<~RUBY
        # frozen_string_literal: true

        require "mkmf"
        require "rb_sys/mkmf"

        create_rust_makefile("rust_backend/rust_backend")
      RUBY
    end

    def self.lib_rs_content
      <<~RUST
        pub mod data_processor;
        pub mod dynamic_hash;
        pub mod gvl;

        use magnus::{function, prelude::*, Error, RHash, Ruby};

        fn hello(name: String) -> String {
            format!("Hello {} from Rust (Magnus)!", name)
        }

        fn calculate(ruby: &Ruby, a: f64, b: f64, op: String) -> Result<f64, Error> {
            match op.as_str() {
                "add" | "+" => Ok(a + b),
                "sub" | "-" => Ok(a - b),
                "mul" | "*" => Ok(a * b),
                "div" | "/" => {
                    if b == 0.0 {
                        Err(Error::new(ruby.exception_zero_div_error(), "division by zero in Rust backend"))
                    } else {
                        Ok(a / b)
                    }
                }
                _ => Err(Error::new(ruby.exception_arg_error(), format!("unknown operator: {}", op))),
            }
        }

        fn process_record(ruby: &Ruby, attributes: RHash) -> Result<RHash, Error> {
            let result = ruby.hash_new();
            attributes.foreach(|k: magnus::Value, v: magnus::Value| {
                result.aset(k, v)?;
                Ok(magnus::r_hash::ForEach::Continue)
            })?;
            result.aset("rust_processed", true)?;
            result.aset("rust_engine", "magnus-0.9")?;
            Ok(result)
        }

        #[magnus::init]
        fn init(ruby: &Ruby) -> Result<(), Error> {
            let module = ruby.define_module("RustBackend")?;
            module.define_singleton_method("hello", function!(hello, 1))?;
            module.define_singleton_method("calculate", function!(calculate, 3))?;
            module.define_singleton_method("process_record", function!(process_record, 1))?;

            // High performance data processing with dynamic Hashes & Rayon (GVL released)
            module.define_singleton_method("process_batch", function!(data_processor::process_batch, 2))?;
            module.define_singleton_method("aggregate_metrics", function!(data_processor::aggregate_metrics, 2))?;

            Ok(())
        }
      RUST
    end

    def self.gvl_rs_content
      <<~RUST
        use std::ffi::c_void;

        pub fn call_without_gvl<F, R>(f: F) -> R
        where
            F: FnOnce() -> R + Send,
            R: Send,
        {
            struct State<F, R> {
                f: Option<F>,
                result: Option<R>,
            }

            unsafe extern "C" fn runner<F, R>(data: *mut c_void) -> *mut c_void
            where
                F: FnOnce() -> R + Send,
                R: Send,
            {
                let state = &mut *(data as *mut State<F, R>);
                if let Some(f) = state.f.take() {
                    state.result = Some(f());
                }
                std::ptr::null_mut()
            }

            let mut state = State {
                f: Some(f),
                result: None,
            };

            unsafe {
                rb_sys::rb_thread_call_without_gvl(
                    Some(runner::<F, R>),
                    &mut state as *mut _ as *mut c_void,
                    None,
                    std::ptr::null_mut(),
                );
            }

            state.result.expect("GVL callback finished")
        }
      RUST
    end

    def self.dynamic_hash_rs_content
      <<~RUST
        use magnus::{
            prelude::*, rb_sys::AsRawValue, Error, Float, Integer, RArray, RHash, RString, Ruby, Symbol, Value,
        };
        use serde_json::{Map, Number, Value as JsonValue};

        pub fn rval_to_json(val: Value) -> JsonValue {
            let raw = val.as_raw();
            // CRuby special constants: Qnil = 8, Qtrue = 20, Qfalse = 0
            if raw == 8 || val.is_nil() {
                JsonValue::Null
            } else if raw == 20 {
                JsonValue::Bool(true)
            } else if raw == 0 {
                JsonValue::Bool(false)
            } else if let Some(i) = Integer::from_value(val) {
                if let Ok(num) = i.to_i64() {
                    JsonValue::Number(num.into())
                } else {
                    JsonValue::Number(i.to_u64().unwrap_or(0).into())
                }
            } else if let Some(f) = Float::from_value(val) {
                Number::from_f64(f.to_f64())
                    .map(JsonValue::Number)
                    .unwrap_or(JsonValue::Null)
            } else if let Some(s) = RString::from_value(val) {
                JsonValue::String(s.to_string().unwrap_or_default())
            } else if let Some(sym) = Symbol::from_value(val) {
                JsonValue::String(sym.name().unwrap_or_default().to_string())
            } else if let Some(h) = RHash::from_value(val) {
                let mut map = Map::new();
                let _ = h.foreach(|k: Value, v: Value| {
                    let key = if let Some(s) = RString::from_value(k) {
                        s.to_string().unwrap_or_default()
                    } else if let Some(sym) = Symbol::from_value(k) {
                        sym.name().unwrap_or_default().to_string()
                    } else {
                        k.to_string()
                    };
                    map.insert(key, rval_to_json(v));
                    Ok(magnus::r_hash::ForEach::Continue)
                });
                JsonValue::Object(map)
            } else if let Some(arr) = RArray::from_value(val) {
                let vec: Vec<JsonValue> = arr.into_iter().map(rval_to_json).collect();
                JsonValue::Array(vec)
            } else {
                JsonValue::String(val.to_string())
            }
        }

        pub fn json_to_rval(ruby: &Ruby, val: &JsonValue) -> Result<Value, Error> {
            match val {
                JsonValue::Null => Ok(ruby.qnil().as_value()),
                JsonValue::Bool(b) => Ok(ruby.into_value(*b).as_value()),
                JsonValue::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        Ok(ruby.into_value(i).as_value())
                    } else if let Some(f) = n.as_f64() {
                        Ok(ruby.into_value(f).as_value())
                    } else {
                        Ok(ruby.qnil().as_value())
                    }
                }
                JsonValue::String(s) => Ok(ruby.str_new(s).as_value()),
                JsonValue::Array(arr) => {
                    let r_arr = ruby.ary_new_capa(arr.len());
                    for item in arr {
                        r_arr.push(json_to_rval(ruby, item)?)?;
                    }
                    Ok(r_arr.as_value())
                }
                JsonValue::Object(map) => {
                    let r_hash = ruby.hash_new();
                    for (k, v) in map {
                        let rk = ruby.str_new(k);
                        let rv = json_to_rval(ruby, v)?;
                        r_hash.aset(rk, rv)?;
                    }
                    Ok(r_hash.as_value())
                }
            }
        }
      RUST
    end

    def self.data_processor_rs_content
      <<~RUST
        use crate::dynamic_hash::{json_to_rval, rval_to_json};
        use crate::gvl::call_without_gvl;
        use magnus::{value::ReprValue, Error, RArray, RHash, Ruby, Value};
        use rayon::prelude::*;
        use serde_json::{json, Value as JsonValue};

        pub fn process_batch(ruby: &Ruby, records: RArray, config: RHash) -> Result<Value, Error> {
            // 1. Convert dynamic Ruby objects to Rust JsonValues while holding GVL
            let raw_records: Vec<JsonValue> = records.into_iter().map(rval_to_json).collect();
            let raw_config = rval_to_json(config.as_value());

            let compute_field = raw_config
                .get("compute_field")
                .and_then(|v| v.as_str())
                .unwrap_or("value")
                .to_string();

            let multiplier = raw_config
                .get("multiplier")
                .and_then(|v| v.as_f64())
                .unwrap_or(1.0);

            let offset = raw_config
                .get("offset")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);

            // 2. Release GVL and process in parallel across all CPU cores with Rayon
            let processed_records = call_without_gvl(move || {
                raw_records
                    .into_par_iter()
                    .map(|mut rec| {
                        if let JsonValue::Object(ref mut map) = rec {
                            let current_val = map
                                .get(&compute_field)
                                .and_then(|v| {
                                    v.as_f64().or_else(|| {
                                        v.as_str().and_then(|s| s.parse::<f64>().ok())
                                    })
                                })
                                .unwrap_or(0.0);

                            let computed = (current_val * multiplier) + offset;
                            map.insert(format!("{}_computed", compute_field), json!(computed));
                            map.insert("processed_by".to_string(), json!("rust_rayon_parallel"));
                            map.insert("gvl_released".to_string(), json!(true));
                        }
                        rec
                    })
                    .collect::<Vec<JsonValue>>()
            });

            // 3. Serialize back into native Ruby Hash / Array
            let result_json = JsonValue::Array(processed_records);
            json_to_rval(ruby, &result_json)
        }

        pub fn aggregate_metrics(ruby: &Ruby, records: RArray, metric_field: String) -> Result<Value, Error> {
            let raw_records: Vec<JsonValue> = records.into_iter().map(rval_to_json).collect();
            let target_field = metric_field.clone();

            // Release GVL for parallel reduction across all cores
            let (count, sum, min, max) = call_without_gvl(move || {
                let values: Vec<f64> = raw_records
                    .into_par_iter()
                    .filter_map(|rec| {
                        if let JsonValue::Object(map) = rec {
                            map.get(&target_field).and_then(|v| {
                                v.as_f64().or_else(|| v.as_str().and_then(|s| s.parse::<f64>().ok()))
                            })
                        } else {
                            None
                        }
                    })
                    .collect();

                if values.is_empty() {
                    (0, 0.0, 0.0, 0.0)
                } else {
                    let count = values.len();
                    let sum: f64 = values.par_iter().sum();
                    let min = values.par_iter().copied().reduce(|| f64::INFINITY, f64::min);
                    let max = values.par_iter().copied().reduce(|| f64::NEG_INFINITY, f64::max);
                    (count, sum, min, max)
                }
            });

            let avg = if count > 0 { sum / count as f64 } else { 0.0 };

            let summary = json!({
                "field": metric_field,
                "count": count,
                "sum": sum,
                "avg": avg,
                "min": min,
                "max": max,
                "parallel_engine": "rayon"
            });

            json_to_rval(ruby, &summary)
        }

        #[cfg(test)]
        mod tests {
            use super::*;

            #[test]
            fn test_parallel_reduction_metrics() {
                let records = vec![
                    json!({ "reading": 10.0 }),
                    json!({ "reading": 20.0 }),
                    json!({ "reading": 30.0 }),
                ];

                let target_field = "reading".to_string();
                let values: Vec<f64> = records
                    .into_par_iter()
                    .filter_map(|rec| {
                        if let JsonValue::Object(map) = rec {
                            map.get(&target_field).and_then(|v| v.as_f64())
                        } else {
                            None
                        }
                    })
                    .collect();

                assert_eq!(values.len(), 3);
                let sum: f64 = values.par_iter().sum();
                assert_eq!(sum, 60.0);
                let count = values.len();
                let avg = sum / count as f64;
                assert_eq!(avg, 20.0);
            }
        }
      RUST
    end

    def self.rust_backed_rb_content
      <<~RUBY
        # frozen_string_literal: true

        module RustBacked
          extend ActiveSupport::Concern

          included do
            # ActiveSupport concern for models integrating with Magnus Rust extension
          end

          def process_with_rust
            RustBackend.transform_record(attributes, { "multiplier" => 1.0 })
          end

          class_methods do
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
      RUBY
    end

    def self.initializer_content
      <<~RUBY
        # frozen_string_literal: true

        require "rust_backend"

        Rails.logger.info "[RustBackend] Magnus native Rust backend loaded successfully."
      RUBY
    end

    def self.loader_content
      <<~RUBY
        # frozen_string_literal: true

        module RustBackend
          begin
            require_relative "rust_backend/rust_backend"
          rescue LoadError
            require_relative "../ext/rust_backend/rust_backend"
          end
        end
      RUBY
    end

    def self.rake_task_content
      <<~RUBY
        # frozen_string_literal: true

        def rust_build_env
          cargo_path = File.expand_path("~/.cargo/bin")
          env = {
            "LIBCLANG_PATH" => ENV["LIBCLANG_PATH"] || File.expand_path("~/.local/lib"),
            "BINDGEN_EXTRA_CLANG_ARGS" => ENV["BINDGEN_EXTRA_CLANG_ARGS"] || "-I\#{File.expand_path('~/.local/lib/clang/23/include')}"
          }
          env["PATH"] = "\#{cargo_path}:\#{ENV['PATH']}" unless ENV["PATH"].include?(cargo_path)
          env
        end

        namespace :rust do
          desc "Build the Magnus Rust backend extension"
          task :build do
            puts "[RustBackend] Compiling Rust crate..."
            crate_dir = Rails.root.join("ext/rust_backend")
            target_dir = Rails.root.join("lib/rust_backend")
            FileUtils.mkdir_p(target_dir)

            system(rust_build_env, "cargo build --release", chdir: crate_dir.to_s, exception: true)

            source_so = crate_dir.join("target/release/librust_backend.so")
            dest_so = target_dir.join("rust_backend.so")

            FileUtils.cp(source_so, dest_so)
            puts "[RustBackend] Built and copied extension to \#{dest_so}"
          end

          desc "Run native Rust tests in ext/rust_backend"
          task :test do
            crate_dir = Rails.root.join("ext/rust_backend")
            system(rust_build_env, "cargo test", chdir: crate_dir.to_s, exception: true)
          end

          desc "Clean compiled Rust artifacts"
          task :clean do
            crate_dir = Rails.root.join("ext/rust_backend")
            system(rust_build_env, "cargo clean", chdir: crate_dir.to_s)
            FileUtils.rm_f(Rails.root.join("lib/rust_backend/rust_backend.so"))
            puts "[RustBackend] Cleaned Rust build artifacts."
          end
        end

        task test: "rust:build"
      RUBY
    end
  end
end

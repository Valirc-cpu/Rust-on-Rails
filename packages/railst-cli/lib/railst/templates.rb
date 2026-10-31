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
        magnus = "0.9"
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
        use magnus::{Error, Ruby};

        pub mod dynamic_hash;
        pub mod data_processor;
        pub mod gvl;

        #[magnus::init]
        fn init(ruby: &Ruby) -> Result<(), Error> {
            let module = ruby.define_module("RustBackend")?;

            module.define_singleton_method(
                "process_batch",
                magnus::function!(data_processor::process_batch, 2),
            )?;

            module.define_singleton_method(
                "aggregate_metrics",
                magnus::function!(data_processor::aggregate_metrics, 2),
            )?;

            module.define_singleton_method(
                "transform_record",
                magnus::function!(data_processor::transform_record, 2),
            )?;

            Ok(())
        }
      RUST
    end

    def self.gvl_rs_content
      <<~RUST
        use magnus::rb_sys::rb_thread_call_without_gvl;
        use std::os::raw::c_void;

        extern "C" fn nogvl_trampoline<F, R>(ptr: *mut c_void) -> *mut c_void
        where
            F: FnOnce() -> R,
        {
            let f = unsafe { Box::from_raw(ptr as *mut F) };
            let result = f();
            Box::into_raw(Box::new(result)) as *mut c_void
        }

        pub fn call_without_gvl<F, R>(f: F) -> R
        where
            F: FnOnce() -> R + Send,
            R: Send,
        {
            let boxed_f = Box::new(f);
            let ptr = Box::into_raw(boxed_f) as *mut c_void;

            let res_ptr = unsafe {
                rb_thread_call_without_gvl(
                    Some(nogvl_trampoline::<F, R>),
                    ptr,
                    None,
                    std::ptr::null_mut(),
                )
            };

            let boxed_res = unsafe { Box::from_raw(res_ptr as *mut R) };
            *boxed_res
        }
      RUST
    end

    def self.dynamic_hash_rs_content
      <<~RUST
        use magnus::{value::ReprValue, Error, RArray, RHash, Ruby, Symbol, Value};
        use serde_json::{Map, Number, Value as JsonValue};

        pub fn rval_to_json(val: Value) -> JsonValue {
            if val.is_nil() {
                return JsonValue::Null;
            }
            if let Ok(b) = bool::try_convert(val) {
                return JsonValue::Bool(b);
            }
            if let Ok(i) = i64::try_convert(val) {
                return JsonValue::Number(Number::from(i));
            }
            if let Ok(f) = f64::try_convert(val) {
                if let Some(n) = Number::from_f64(f) {
                    return JsonValue::Number(n);
                }
            }
            if let Ok(s) = String::try_convert(val) {
                return JsonValue::String(s);
            }
            if let Ok(sym) = Symbol::try_convert(val) {
                if let Ok(s) = sym.name() {
                    return JsonValue::String(s.to_string());
                }
            }
            if let Ok(hash) = RHash::try_convert(val) {
                let mut map = Map::new();
                let _ = hash.each(|k: Value, v: Value| {
                    let key_str = if let Ok(s) = String::try_convert(k) {
                        s
                    } else if let Ok(sym) = Symbol::try_convert(k) {
                        sym.name().map(|n| n.to_string()).unwrap_or_else(|_| k.to_string())
                    } else {
                        k.to_string()
                    };
                    map.insert(key_str, rval_to_json(v));
                    Ok(())
                });
                return JsonValue::Object(map);
            }
            if let Ok(arr) = RArray::try_convert(val) {
                let mut vec = Vec::with_capacity(arr.len());
                for item in arr.into_iter() {
                    vec.push(rval_to_json(item));
                }
                return JsonValue::Array(vec);
            }
            JsonValue::String(val.to_string())
        }

        pub fn json_to_rval(ruby: &Ruby, val: &JsonValue) -> Result<Value, Error> {
            match val {
                JsonValue::Null => Ok(ruby.qnil().as_value()),
                JsonValue::Bool(b) => Ok(ruby.into_value(*b)),
                JsonValue::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        Ok(ruby.into_value(i))
                    } else if let Some(f) = n.as_f64() {
                        Ok(ruby.into_value(f))
                    } else {
                        Ok(ruby.into_value(n.to_string()))
                    }
                }
                JsonValue::String(s) => Ok(ruby.into_value(s.as_str())),
                JsonValue::Array(arr) => {
                    let rarr = ruby.ary_new_capa(arr.len());
                    for item in arr {
                        rarr.push(json_to_rval(ruby, item)?)?;
                    }
                    Ok(rarr.as_value())
                }
                JsonValue::Object(map) => {
                    let rhash = ruby.hash_new();
                    for (k, v) in map {
                        let rkey = ruby.into_value(k.as_str());
                        let rval = json_to_rval(ruby, v)?;
                        rhash.aset(rkey, rval)?;
                    }
                    Ok(rhash.as_value())
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

        pub fn transform_record(ruby: &Ruby, record: RHash, config: RHash) -> Result<Value, Error> {
            let mut raw_record = rval_to_json(record.as_value());
            let raw_config = rval_to_json(config.as_value());

            let field = raw_config.get("compute_field").and_then(|v| v.as_str()).unwrap_or("value").to_string();
            let mult = raw_config.get("multiplier").and_then(|v| v.as_f64()).unwrap_or(1.0);

            if let JsonValue::Object(ref mut map) = raw_record {
                let current_val = map.get(&field).and_then(|v| v.as_f64()).unwrap_or(0.0);
                map.insert(format!("{}_computed", field), json!(current_val * mult));
                map.insert("processed_by".to_string(), json!("rust_magnus"));
            }

            json_to_rval(ruby, &raw_record)
        }

        pub fn process_batch(ruby: &Ruby, records: RArray, config: RHash) -> Result<Value, Error> {
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

            let result_json = JsonValue::Array(processed_records);
            json_to_rval(ruby, &result_json)
        }

        pub fn aggregate_metrics(ruby: &Ruby, records: RArray, metric_field: String) -> Result<Value, Error> {
            let raw_records: Vec<JsonValue> = records.into_iter().map(rval_to_json).collect();
            let target_field = metric_field.clone();

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

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

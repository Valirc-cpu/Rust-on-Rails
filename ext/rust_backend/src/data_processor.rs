use crate::dynamic_hash::{json_to_rval, rval_to_json};
use crate::gvl::call_without_gvl;
use magnus::{value::ReprValue, Error, RArray, RHash, Ruby, Value};
use rayon::prelude::*;
use serde_json::{json, Value as JsonValue};

pub fn process_batch(ruby: &Ruby, records: RArray, config: RHash) -> Result<Value, Error> {
    // 1. Convert dynamic Ruby objects to Rust JsonValues while holding GVL
    let raw_records: Vec<JsonValue> = records.into_iter().map(rval_to_json).collect();

    let raw_config = rval_to_json(config.as_value());

    let multiplier = raw_config
        .get("multiplier")
        .and_then(|v| v.as_f64())
        .unwrap_or(1.0);
    let compute_field = raw_config
        .get("compute_field")
        .and_then(|v| v.as_str())
        .unwrap_or("value")
        .to_string();

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

                    let computed = current_val * multiplier;
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
    // Release GVL for parallel reduction
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

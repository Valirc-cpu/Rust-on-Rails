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

# `rust_backend` Core Engine

The pure Rust Magnus 0.9 + Rayon backend engine for **Rust on Rails**.

## Architecture
- **Magnus 0.9**: Safe, direct C-ABI in-process Ruby-Rust interop.
- **Rayon**: Work-stealing parallel multi-core iterator crunches data across all CPU threads.
- **Ruby GVL Release**: Safe `rb_thread_call_without_gvl` releasing the Ruby VM lock so Puma/Ruby threads aren't blocked.
- **Dynamic Hash Converter**: Bidirectional zero-friction type serialization between Ruby dynamic types and `serde_json::Value`.

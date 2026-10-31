# Rust-on-Ruby (Rails 8 + Magnus Native Rust Backend)

Arsitektur hybrid berkecepatan tinggi yang memadukan **produktivitas Ruby on Rails** (Routing, ActiveRecord ORM, Scaffolding, Migrations) dengan **kinerja native Rust murni** (Magnus 0.9 + Rayon CPU parallelism + GVL release).

---

##  Arsitektur Sistem

```
+--------------------------------------------------------------+
|                    Rails 8 Web Layer                         |
|  - Routing (config/routes.rb)                                |
|  - Controllers & REST APIs                                   |
|  - ActiveRecord Models (app/models/concerns/rust_backed.rb)   |
+------------------------------+-------------------------------+
                               |
               In-Process FFI  | (Magnus 0.9 C-ABI)
                               v
+--------------------------------------------------------------+
|                 Rust Backend (ext/rust_backend)              |
|  - Dynamic Hash/JSON serialization (src/dynamic_hash.rs)     |
|  - GVL Released Thread Execution (src/gvl.rs)                |
|  - Multi-Core Data Crunching with Rayon (src/data_processor) |
+--------------------------------------------------------------+
```

### Keunggulan Utama
1. **Dynamic Hash Interoperability**: Menerima data hash dinamis atau array dari ActiveRecord tanpa perlu mendefinisikan skema struct yang kaku di awal.
2. **True CPU Parallelism (GVL Release)**: Ruby Global VM Lock dilepaskan saat komputasi berat, memungkinkan Rayon menggunakan semua core CPU server tanpa memblokir thread HTTP / Puma lainnya.
3. **Scaffolding Terintegrasi**: Generator terpadu untuk model, migrasi, routes, controller, dan pengujian.

---

## 🛠 Command & Workflow

### 1. Build & Test Rust Extension
```bash
# Mengompilasi Rust crate dan memperbarui lib/rust_backend/rust_backend.so
bin/rake rust:build

# Menjalankan seluruh test suite (Ruby & Rust)
bin/rails test
```

### 2. Scaffold Resource Berbasis Rust Murni
Buat migrasi database, model ActiveRecord dengan `RustBacked`, routes, dan controller dengan endpoint batch processing & metrics secara otomatis:

```bash
bin/rails generate rust:resource SensorData device_id:string reading:float status:string
bin/rails db:migrate
```

Endpoint yang otomatis tersedia:
- `GET /sensor_data` - REST index
- `GET /sensor_data/:id` - Data yang diproses native oleh Rust
- `POST /sensor_data/process_batch` - Batch data processor paralel (Rayon, GVL dilepas)
- `GET /sensor_data/metrics?field=reading` - Agregasi statistik paralel (sum, avg, min, max, count)

### 3. Buat Service Baru Berbasis Rust
Untuk business logic spesifik / micro-computations:
```bash
bin/rails generate rust:service HighFrequencyAnalytics
```

---

## 📊 Benchmark
Pemrosesan batch 50.000 record dinamis (transformasi & agregasi multi-core):
* **Waktu eksekusi**: ~238 ms untuk 50.000 dynamic hash records.
* **GVL status**: Released (`gvl_released: true`).

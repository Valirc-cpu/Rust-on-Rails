# Rust-on-Ruby Framework

> **High-Performance Data Processing Framework**  
> Menggabungkan produktivitas pengembangan **Ruby on Rails 8** dengan kecepatan komputasi multi-core **Rust murni** melalui **Magnus 0.9**, **Rayon**, dan **Pelepasan Ruby GVL**.

---

## 🏛 Arsitektur Sistem

Framework ini menggunakan integrasi *in-process native C-ABI* (tanpa overhead jaringan, soket, atau IPC):

```
┌─────────────────────────────────────────────────────────────┐
│                     Rails 8 Application                     │
│  - REST Controllers & Dynamic Routing (config/routes.rb)   │
│  - ActiveRecord ORM & Migrations (app/models/)              │
│  - RustBacked Concern (app/models/concerns/rust_backed.rb)  │
└──────────────────────────────┬──────────────────────────────┘
                               │ In-Process FFI (Magnus 0.9)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 Rust Engine (ext/rust_backend)              │
│  - Dynamic Hash Converter (src/dynamic_hash.rs)             │
│  - No-GVL Parallel Threading (src/gvl.rs)                   │
│  - Multi-Core Rayon Cruncher (src/data_processor.rs)        │
└─────────────────────────────────────────────────────────────┘
```

### Keunggulan Utama
* **Interoperabilitas Dynamic Hash**: Menerima data hash dinamis atau relasi ActiveRecord langsung tanpa perlu mendefinisikan skema struct yang kaku di sisi Rust.
* **True Multi-Core Parallelism (GVL Release)**: Ruby Global VM Lock (GVL) dilepaskan sebelum komputasi berat dimulai, sehingga **Rayon** bebas memanfaatkan seluruh thread CPU tanpa memblokir thread HTTP Puma lainnya.
* **Produktivitas RoR 100% Utuh**: Routing, scaffolding, ActiveRecord ORM, validations, dan console (`rails c`) tetap berfungsi normal.

---

## ⚡ Cara Aktivasi & Menjalankan Project

### 1. Prasyarat Lingkungan
Pastikan environment shell Anda (`~/.bashrc` atau `~/.zshrc`) telah memuat path berikut:

```bash
# Ruby Gem binaries & Cargo
export PATH="$HOME/.cargo/bin:$(ruby -r rubygems -e 'puts Gem.user_dir')/bin:$PATH"

# Clang / Bindgen headers (untuk kompilasi extension rb-sys)
export LIBCLANG_PATH="$HOME/.local/lib"
export BINDGEN_EXTRA_CLANG_ARGS="-I$HOME/.local/lib/clang/23/include"
```

### 2. Instalasi Dependensi & Build Extension
Jalankan perintah berikut di direktori root project:

```bash
# 1. Install gem Rails & rb_sys
bundle install

# 2. Kompilasi modul Rust murni menjadi pustaka bersama (.so)
bin/rake rust:build

# 3. Siapkan database
bin/rails db:prepare

# 4. Jalankan verifikasi test suite
bin/rails test
```

### 3. Menjalankan Server Development
```bash
bin/rails server
```
Server Rails akan otomatis memuat modul `RustBackend` saat booting.

---

## 🛠 Panduan Developer & Workflow Scaffolding

### 1. Scaffold Resource Berbasis Rust (`rust:resource`)
Gunakan generator bawaan untuk membuat resource lengkap (Migrasi DB + Model dengan `RustBacked` + Controller REST & Batch + Routes + Integration Tests):

```bash
bin/rails generate rust:resource Transaction amount:decimal status:string category:string
bin/rails db:migrate
```

Endpoint yang langsung tersedia:
* `GET    /transactions` - REST index
* `GET    /transactions/:id` - REST show dengan pemrosesan Rust
* `POST   /transactions` - REST create
* `PATCH  /transactions/:id` - REST update
* `DELETE /transactions/:id` - REST destroy
* `POST   /transactions/process_batch` - Pemrosesan paralel multi-core data hash (Rayon + GVL released)
* `GET    /transactions/metrics?field=amount` - Reduksi statistik multi-core (count, sum, avg, min, max)

### 2. Scaffold Service Rust (`rust:service`)
Untuk komputasi spesifik atau algoritma custom:
```bash
bin/rails generate rust:service AnomalyDetector
```
Akan membuat service di `app/services/rust/anomaly_detector_service.rb` dan file unit test-nya.

### 3. Manajemen Build Rust
```bash
# Rebuild extension Rust ke lib/rust_backend/rust_backend.so
bin/rake rust:build

# Jalankan pengujian unit di sisi crate Rust
bin/rake rust:test

# Bersihkan build artifacts Rust
bin/rake rust:clean
```

---

## 💻 Contoh Penggunaan Kode

### A. Menggunakan Model ActiveRecord
```ruby
class Transaction < ApplicationRecord
  include RustBacked
end

# 1. Komputasi per-record
tx = Transaction.first
result = tx.process_with_rust

# 2. Batch Processing Paralel (Pelepasan GVL + Rayon)
records = Transaction.limit(50_000).as_json
processed = Transaction.rust_batch_process(records, {
  "multiplier" => 1.15,
  "compute_field" => "amount"
})

# 3. Reduksi Statistik Paralel
stats = Transaction.rust_aggregate(Transaction.all, "amount")
# => { "field" => "amount", "count" => 50000, "sum" => 5750000.0, "avg" => 115.0, "min" => 10.0, "max" => 500.0, "parallel_engine" => "rayon" }
```

### B. Menggunakan Modul RustBackend Langsung
```ruby
# Panggilan kalkulasi primitif berkecepatan native
RustBackend.calculate(150.0, 3.0, "div") # => 50.0

# Dynamic Hash enrichment
RustBackend.process_record({ "user_id" => 42, "balance" => 1000.0 })
```

---

## 📂 Struktur Direktori

```
Rust-on-Ruby/
├── app/
│   ├── controllers/            # Controller Rails (termasuk batch endpoints)
│   ├── models/
│   │   └── concerns/
│   │       └── rust_backed.rb  # Concern penghubung ActiveRecord ke Rust
│   └── services/rust/          # Service layer berbasis Rust
├── config/
│   └── initializers/
│       └── rust_backend.rb     # Auto-loader extension saat Rails boot
├── ext/
│   └── rust_backend/           # Kode sumber Rust murni
│       ├── Cargo.toml          # Konfigurasi dependensi Rust (Magnus, Rayon, Serde)
│       ├── extconf.rb          # Script konfigurasi build rb-sys
│       └── src/
│           ├── lib.rs          # Magnus entrypoint & modul init
│           ├── gvl.rs          # Safe wrapper pelepasan Ruby GVL
│           ├── dynamic_hash.rs # Parser dua arah Ruby RHash <-> Serde JsonValue
│           └── data_processor.rs # Komputasi batch paralel & agregasi Rayon
├── lib/
│   ├── generators/rust/        # Custom Rails generators (resource & service)
│   ├── tasks/rust.rake         # Rake tasks untuk kompilasi Rust
│   └── rust_backend.rb         # Ruby module interface
└── test/
    └── lib/rust_backend_test.rb # Test suite untuk FFI Rust
```

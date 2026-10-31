# Rust-on-Ruby Framework

Framework pemrosesan data berkinerja tinggi yang menggabungkan produktivitas pengembangan **Ruby on Rails 8** dengan kecepatan komputasi multi-core **Rust murni** melalui **Magnus 0.9**, **Rayon**, dan **Pelepasan Ruby GVL (Global VM Lock)**.

---

## 1. Penjelasan Codebase

Arsitektur aplikasi terbagi menjadi dua lapisan utama yang berkomunikasi langsung di dalam memori (in-process) melalui C-ABI tanpa overhead jaringan atau soket:

```
+-------------------------------------------------------------+
|                     Rails 8 Application                     |
|  - Routing & REST Controllers (app/controllers/)            |
|  - ActiveRecord Models & Concerns (app/models/)             |
|  - Service Layer (app/services/rust/)                       |
+------------------------------+------------------------------+
                               | In-Process FFI (Magnus 0.9)
                               v
+-------------------------------------------------------------+
|                 Rust Engine (ext/rust_backend)              |
|  - Dynamic Hash Converter (src/dynamic_hash.rs)             |
|  - GVL Release Wrapper (src/gvl.rs)                         |
|  - Parallel Data Processor (src/data_processor.rs)          |
+-------------------------------------------------------------+
```

### Struktur Folder dan Peran Masing-Masing

* **`app/models/concerns/rust_backed.rb`**:
  Concern ActiveSupport yang disematkan pada model ActiveRecord. Menyediakan method `process_with_rust`, `rust_batch_process`, dan `rust_aggregate` agar model dapat langsung memanggil fungsi Rust.
* **`app/controllers/`**:
  Controller Rails standar untuk menangani request HTTP. Controller yang dibuat via generator framework otomatis memiliki endpoint REST standar serta endpoint pemrosesan batch paralel (`/process_batch`) dan metrik statistik (`/metrics`).
* **`app/services/rust/`**:
  Service layer untuk mengisolasi logika bisnis khusus yang memanggil modul Rust tanpa mengotori controller.
* **`config/initializers/rust_backend.rb`**:
  Initializer yang otomatis memuat pustaka bersama Rust (`rust_backend.so`) saat aplikasi Rails melakukan booting.
* **`ext/rust_backend/`**:
  Crate Rust murni tempat seluruh kode native berada:
  * `Cargo.toml`: Konfigurasi dependensi Rust (`magnus`, `rb-sys`, `rayon`, `serde`, `serde_json`).
  * `extconf.rb`: Script pembuat Makefile berbasis `rb-sys`.
  * `src/lib.rs`: Entry point Magnus yang mengekspor fungsi Rust ke namespace Ruby `RustBackend`.
  * `src/gvl.rs`: Wrapper aman untuk `rb_thread_call_without_gvl`, melepaskan GVL Ruby agar thread CPU murni dapat berjalan paralel.
  * `src/dynamic_hash.rs`: Konverter dua arah antara tipe data dinamis Ruby (`RHash`, `RArray`, `Symbol`, angka, string, boolean) dengan `serde_json::Value` di Rust.
  * `src/data_processor.rs`: Implementasi komputasi batch paralel dan reduksi statistik multi-core menggunakan parallel iterator milik Rayon.
* **`lib/generators/rust/`**:
  Kumpulan generator kustom Rails untuk scaffolding:
  * `resource`: Generator terpadu untuk membuat migrasi, model dengan `RustBacked`, controller batch/metrics, dan routing.
  * `service`: Generator untuk membuat service Ruby berbasis Rust.
* **`lib/tasks/rust.rake`**:
  Rake tasks otomatis untuk lifecycle Rust: `rust:build`, `rust:test`, dan `rust:clean`. Task `test` di Rails otomatis memanggil `rust:build`.
* **`lib/rust_backend.rb`**:
  Loader Ruby yang bertugas memuat biner `rust_backend.so`.
* **`bin/ci`**:
  Runner Continuous Integration lengkap yang menjalankan setup, linter RuboCop, audit keamanan, unit test Rust, dan test suite Rails.
* **`bin/railst` & `exe/railst`**:
  Executable CLI mandiri framework `railst` untuk menjalankan semua perintah tanpa mengetik awalan `bin/`.

---

## 2. Command CLI `railst` (Developer Interface Tanpa Awalan `bin/`)

Framework ini menyediakan command line interface bawaan bernama **`railst`** sehingga developer tidak perlu mengetik awalan `bin/` atau `bundle exec`. Output CLI didesain dengan format bersih, elegan, dan informatif layaknya Laravel (`php artisan serve`), dilengkapi pendeteksi tabrakan port otomatis dan penekanan pesan warning verbose sistem.

### Cara Mengaktifkan Command `railst`
Di komputer mana pun framework ini di-clone, jalankan perintah setup sekali:

```bash
bin/setup --skip-server
# atau jika hanya ingin mengaktifkan CLI ke direktori PATH sistem:
bin/railst install
```

Perintah di atas akan menyalin biner `railst` ke direktori path user (`$(ruby -e 'puts Gem.user_dir')/bin` dan `~/.local/bin`) yang sudah terdaftar di `$PATH`.

### Menjalankan Server (`railst run`)

Perintah `railst run` otomatis mengecek dan mengompilasi ekstensi Rust jika belum dibangun, menyaring log internal Puma yang bising, dan menyajikan antarmuka visual server yang bersih:

```bash
railst run                       # Menjalankan server pada port default 3000
railst run -p 3001               # Menjalankan server pada port spesifik (misal: 3001)
railst run --find-port           # Otomatis memilih port berikutnya jika default terpakai
railst run -b 0.0.0.0            # Mengikat server ke seluruh antarmuka jaringan (IP 0.0.0.0)
railst run -e production         # Menjalankan dalam environment spesifik
railst run --verbose             # Menampilkan log raw lengkap Rails, SQL query, & Puma
```

#### Tampilan Server Saat Berjalan Normal (Laravel-Style)
```text
   INFO  Server running on [http://127.0.0.1:3001].

  Press Ctrl+C to stop the server

  Environment ......................................... development
  Rust Backend ....................... Rayon + Magnus 0.9 (active)

  2026-10-31 16:10:00  GET    / ............................................. 200 OK ~ 4ms
  2026-10-31 16:10:05  POST   /benchmark .................................... 200 OK ~ 11ms

   INFO  Server stopped.
```

#### Tampilan Saat Terjadi Tabrakan Port (Clean Error Reporting)
Jika port 3000 sedang ditempati oleh proses lain (seperti Docker proxy):
```text
   ERROR  Failed to listen on 127.0.0.1:3000 (reason: Address already in use).

  Port 3000 is currently occupied by another process.
  Try specifying a different port:
    railst run -p 3001

  Or run with automatic port selection:
    railst run --find-port
```

---

### Daftar Perintah `railst` Lengkap

| Perintah | Deskripsi |
| :--- | :--- |
| `railst run [options]` | Menjalankan server development dengan auto-build Rust dan tampilan bersih |
| `railst build` | Mengompilasi crate `ext/rust_backend` via Cargo ke `lib/rust_backend/` |
| `railst test [path]` | Menjalankan unit test native Rust (`cargo test`) dan Minitest Rails |
| `railst ci` | Menjalankan 7 tahapan verifikasi Continuous Integration menyeluruh |
| `railst g rust:resource <Name> [field:type]` | Scaffolding terpadu: migrasi, model `RustBacked`, controller, dan routing |
| `railst g rust:service <Name>` | Membuat service Ruby khusus yang terintegrasi langsung dengan Rust |
| `railst c` | Membuka konsol interaktif Rails dengan namespace `RustBackend` siap pakai |
| `railst db [action]` | Menjalankan operasi database (`migrate`, `rollback`, `prepare`, `seed`) |
| `railst setup` | Instalasi dependensi gem, migrasi DB, dan kompilasi Rust extension |
| `railst clean` | Membersihkan artefak build target Cargo pada crate Rust |
| `railst install` | Menginstal biner `railst` secara global ke direktori bin user |
| `railst help` | Menampilkan bantuan penggunaan dan opsi argumen |

---

## 3. Tampilan Frontend Baru (Rust + Ruby Fusion Palette)

Landing page bawaan ("Yay! You're on Rails!") telah digantikan dengan antarmuka front-end modern yang didesain secara elegan, ringkas, dan bebas emoji.

### Karakteristik Desain:
* **Palet Warna Rust & Ruby**: Mengombinasikan warna khas tembaga/perunggu Rust (`#CE412B`, `#E57353`) dengan crimson dan garnet mewah khas Ruby (`#CC342D`, `#700010`).
* **Dark Glassmorphic Surface**: Berlatarbelakang obsidian gelap (`#0A0A0D`) dengan aksen ambient radial glow dan kartu kontainer transparan ber-filter *blur*.
* **Live In-Browser Benchmark Widget**: Fitur interaktif di halaman utama untuk menguji latensi pemrosesan data in-process Rust FFI secara langsung. Developer dapat memilih 10.000 hingga 100.000 data point dan mengevaluasi throughput per detik secara *real-time*.
* **Status Arsitektur Terintegrasi**: Menampilkan status aktif FFI Magnus 0.9, pelepasan GVL, jumlah CPU core yang terdeteksi oleh Rayon, serta status adapter database.

---

## 4. Prasyarat dan Cara Instalasi

### Prasyarat Sistem
* **Ruby**: Versi 3.4.x atau lebih baru beserta header development (`ruby.h`).
* **Rust & Cargo**: Terpasang via `rustup` (rekomendasi) atau package manager.
* **Clang / LLVM Libraries**: Diperlukan oleh `bindgen` saat kompilasi `rb-sys`.

### Langkah 1: Konfigurasi Environment Shell
Tambahkan baris berikut ke file konfigurasi shell Anda (`~/.bashrc` atau `~/.zshrc`):

```bash
# Path binary gem user dan Cargo
export PATH="$HOME/.cargo/bin:$(ruby -r rubygems -e 'puts Gem.user_dir')/bin:$PATH"

# Path library Clang dan header bindgen
export LIBCLANG_PATH="$HOME/.local/lib"
export BINDGEN_EXTRA_CLANG_ARGS="-I$HOME/.local/lib/clang/23/include"
```

Setelah ditambahkan, muat ulang shell:
```bash
source ~/.bashrc  # atau source ~/.zshrc
```

### Langkah 2: Setup Otomatis Proyek
Di direktori root proyek, jalankan:

```bash
bin/setup --skip-server
```

Script ini otomatis melakukan:
1. Verifikasi dan instalasi gem dependensi (`bundle install`).
2. Kompilasi modul Rust menjadi pustaka biner `lib/rust_backend/rust_backend.so`.
3. Persiapan database SQLite (`bin/rails db:prepare`).
4. Pembersihan log dan berkas sementara.

### Langkah 3: Menjalankan Server
```bash
bin/rails server
```
Server Rails akan aktif di `http://localhost:3000`.

---

## 5. Panduan Pembuatan Komponen Aplikasi

Framework ini mempertahankan 100% alur kerja Rails sambil menyediakan akselerasi Rust.

### Metode A: Scaffold Resource Rust Terpadu (Direkomendasikan)
Untuk membuat resource baru yang otomatis siap memproses data dalam jumlah besar dengan Rust:

```bash
railst g rust:resource Invoice customer:string amount:decimal status:string
```

Perintah di atas secara otomatis menghasilkan:
1. **Migration DB**: Berkas migrasi di `db/migrate/..._create_invoices.rb`.
2. **Model ActiveRecord**: Berkas `app/models/invoice.rb` yang sudah menyertakan `include RustBacked`.
3. **Controller Lengkap**: Berkas `app/controllers/invoices_controller.rb` dengan aksi CRUD serta endpoint paralel:
   * `POST /invoices/process_batch` (Pemrosesan batch multi-core via Rayon).
   * `GET /invoices/metrics?field=amount` (Reduksi statistik agregat via Rayon).
4. **Routing**: Mendaftarkan `resources :invoices` beserta endpoint koleksi `process_batch` dan `metrics` di `config/routes.rb`.
5. **Integration Test**: Berkas pengujian controller di `test/controllers/invoices_controller_test.rb`.

Jalankan migrasi database setelah scaffolding:
```bash
bin/rails db:migrate
```

---

### Metode B: Menghubungkan Model dan Migration Standar Secara Manual
Jika Anda sudah memiliki model Rails biasa atau ingin membuat migrasi secara manual:

#### 1. Membuat Migrasi Database
```bash
bin/rails generate migration CreateProducts name:string price:decimal quantity:integer
bin/rails db:migrate
```

#### 2. Menghubungkan Model ke Rust
Cukup tambahkan `include RustBacked` pada model Anda:

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  include RustBacked

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
```

Setelah concern disertakan, model otomatis memiliki fungsi akselerasi:
```ruby
# Proses per-record
product = Product.first
product.process_with_rust

# Batch processing ribuan record sekaligus tanpa memblokir thread HTTP
records = Product.all.as_json
Product.rust_batch_process(records, { "multiplier" => 1.1, "compute_field" => "price" })

# Agregasi metrik paralel (count, sum, avg, min, max)
Product.rust_aggregate(Product.all, "price")
```

#### 3. Membuat Controller Manual
Buat controller Rails standar:
```bash
bin/rails generate controller Products
```

Implementasikan pemanggilan batch Rust di controller:
```ruby
# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  def index
    render json: Product.all
  end

  def process_batch
    raw = params[:records]
    records = raw.present? ? raw.map { |r| r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r } : Product.all.as_json
    config = params[:config].present? ? (params[:config].respond_to?(:to_unsafe_h) ? params[:config].to_unsafe_h : params[:config]) : {}

    result = Product.rust_batch_process(records, config)
    render json: { count: result.size, data: result }
  end
end
```

---

### Metode C: Membuat Service Layer Rust Kustom
Jika Anda memiliki algoritma atau business logic mandiri di luar operasi CRUD:

```bash
bin/rails generate rust:service AnomalyDetector
```

Akan menghasilkan berkas service di `app/services/rust/anomaly_detector_service.rb`:
```ruby
module Rust
  class AnomalyDetectorService
    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end

    def call
      # Panggil fungsi native di RustBackend
      RustBackend.process_batch(@records, @config)
    end
  end
end
```

---

### Metode D: Menambahkan Fungsi Baru di Rust Crate
Jika Anda ingin menambahkan fungsi native baru di sisi Rust:

1. Buat atau buka berkas modul di `ext/rust_backend/src/`.
2. Tulis fungsi Rust:
   ```rust
   // ext/rust_backend/src/custom_calc.rs
   use magnus::{Error, Ruby, Value};

   pub fn complex_hash_operation(ruby: &Ruby, input: String) -> Result<String, Error> {
       // Logika CPU-intensive murni
       Ok(format!("processed: {}", input))
   }
   ```
3. Daftarkan fungsi di `ext/rust_backend/src/lib.rs`:
   ```rust
   pub mod custom_calc;

   #[magnus::init]
   fn init(ruby: &Ruby) -> Result<(), Error> {
       let module = ruby.define_module("RustBackend")?;
       module.define_singleton_method("complex_hash_operation", magnus::function!(custom_calc::complex_hash_operation, 1))?;
       Ok(())
   }
   ```
4. Kompilasi ulang:
   ```bash
   bin/rake rust:build
   ```

---

## 6. Panduan Pengujian (Testing)

Framework ini menyediakan tiga tingkatan pengujian untuk memastikan stabilitas:

### 1. Pengujian CI Menyeluruh (All-in-One Pipeline)
```bash
railst ci
```
Menjalankan audit linter, scanner kerentanan gem dan importmap, analisis keamanan Brakeman, unit test native Rust, serta integrasi test Rails secara otomatis.

### 2. Pengujian Test Suite Rails & FFI
```bash
railst test
```
Menjalankan pengujian Minitest pada model, controller, dan FFI integration (`test/lib/rust_backend_test.rb`). Hook otomatis akan mengompilasi Rust jika berkas kode native berubah.

### 3. Pengujian Unit Native Rust Murni
```bash
bin/rake rust:test
```
Menjalankan pengujian `cargo test` langsung di dalam crate `ext/rust_backend`.

---

## 7. Prinsip Arsitektur Anti-Spaghetti Code

Untuk menjaga performa dan keterbacaan kode seiring pertumbuhan proyek:

1. **Pemisahan Tanggung Jawab yang Jelas**:
   * **Rails (Ruby)**: Menangani validasi HTTP, parsing parameter, relasi database, dan migrasi skema.
   * **Rust**: Menangani komputasi berat, transformasi data berukuran besar, hashing, dan kalkulasi paralel.
2. **Tidak Ada SQL di Dalam Rust**:
   Biarkan ActiveRecord mengelola query dan koneksi database. Rust hanya menerima data yang sudah berupa hash/array atau json dan mengembalikan hasil olahan.
3. **Modularitas Crate**:
   Hindari menumpuk semua logika pada `ext/rust_backend/src/lib.rs`. Pisahkan domain ke dalam modul terpisah (misalnya `data_processor.rs`, `dynamic_hash.rs`, `gvl.rs`) dan gunakan unit test `#[test]` di setiap modul Rust.

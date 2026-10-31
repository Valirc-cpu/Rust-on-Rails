# Rust-on-Ruby Framework

A high-performance data processing framework combining the rapid development productivity of **Ruby on Rails 8** with the raw multi-core computing power of **pure Rust** via **Magnus 0.9**, **Rayon**, and **Ruby GVL (Global VM Lock) Release**.

---

## 1. Codebase Architecture

The application architecture is divided into two primary layers communicating directly in-process via C-ABI without network overhead, sockets, or IPC serialization penalties:

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

### Directory Structure and Component Roles

* **`app/models/concerns/rust_backed.rb`**:
  ActiveSupport concern attached to ActiveRecord models. Provides `process_with_rust`, `rust_batch_process`, and `rust_aggregate` methods to allow models to invoke native Rust acceleration directly.
* **`app/controllers/`**:
  Standard Rails controllers handling HTTP requests. Controllers created via the framework generator automatically include standard REST actions alongside parallel batch endpoints (`/process_batch`) and statistical metrics endpoints (`/metrics`).
* **`app/services/rust/`**:
  Service layer for isolating specialized business logic that interfaces with Rust without cluttering controllers.
* **`config/initializers/rust_backend.rb`**:
  Initializer that automatically loads the compiled native Rust shared library (`rust_backend.so`) during Rails application boot.
* **`ext/rust_backend/`**:
  Pure Rust crate containing all native code:
  * `Cargo.toml`: Rust dependency configuration (`magnus`, `rb-sys`, `rayon`, `serde`, `serde_json`).
  * `extconf.rb`: Makefile generator script powered by `rb-sys`.
  * `src/lib.rs`: Magnus entry point exporting native Rust functions to the Ruby `RustBackend` namespace.
  * `src/gvl.rs`: Safe wrapper for `rb_thread_call_without_gvl`, releasing the Ruby GVL so multi-threaded CPU tasks run across all physical cores.
  * `src/dynamic_hash.rs`: Bi-directional converter between Ruby dynamic types (`RHash`, `RArray`, `Symbol`, integers, floats, strings, booleans) and Rust `serde_json::Value`.
  * `src/data_processor.rs`: High-throughput batch crunching and parallel reduction metrics implemented using Rayon parallel iterators.
* **`lib/generators/rust/`**:
  Custom Rails scaffolding generators:
  * `resource`: Unified generator creating migrations, models with `RustBacked`, batch/metrics controllers, and routes.
  * `service`: Generator creating standalone Ruby services integrated with native Rust.
* **`lib/tasks/rust.rake`**:
  Automated Rake tasks for the Rust lifecycle: `rust:build`, `rust:test`, and `rust:clean`. Rails test suites automatically invoke `rust:build`.
* **`lib/rust_backend.rb`**:
  Ruby loader responsible for requiring `rust_backend.so`.
* **`bin/ci`**:
  Comprehensive Continuous Integration runner that executes setup, RuboCop linter, security audits, Rust unit tests, and Rails test suites.
* **`bin/railst` & `exe/railst`**:
  Standalone framework CLI executable enabling developers to run all commands without the `bin/` prefix.

---

## 2. The `railst` CLI (Developer Interface Without `bin/` Prefix)

The framework includes a built-in CLI utility named **`railst`** so developers do not need to prefix commands with `bin/` or `bundle exec`. Output is styled in a clean, elegant format inspired by Laravel (`php artisan serve`), featuring automatic port collision handling, clean error boxes, and suppression of noisy system C-library warnings.

### Installing and Activating `railst`

On any machine where this repository is cloned, run the setup task once:

```bash
bin/setup --skip-server
# Or to install the standalone CLI into your PATH:
bin/railst install
```

This copies the `railst` executable to your user gem binary directory (`$(ruby -e 'puts Gem.user_dir')/bin` and `~/.local/bin`) registered in `$PATH`.

### Running the Server (`railst run`)

The `railst run` command automatically verifies and builds the native Rust extension if not yet compiled, filters internal Puma noise, and renders a clean console dashboard:

```bash
railst run                       # Start server on default port 3000
railst run -p 3001               # Start server on a specific port (e.g. 3001)
railst run --find-port           # Automatically select the next open port if occupied
railst run -b 0.0.0.0            # Bind server to all network interfaces
railst run -e production         # Run in a specific environment
railst run --verbose             # Display full raw Rails, SQL query, and Puma logs
```

#### Normal Server Output (Laravel-Style)
```text
   INFO  Server running on [http://127.0.0.1:3001].

  Press Ctrl+C to stop the server

  Environment ......................................... development
  Rust Backend ....................... Rayon + Magnus 0.9 (active)

  2026-10-31 16:10:00  GET    / ............................................. 200 OK ~ 4ms
  2026-10-31 16:10:05  POST   /benchmark .................................... 200 OK ~ 11ms

   INFO  Server stopped.
```

#### Port Collision Handling (Clean Error Reporting)
If port 3000 is occupied by another process (e.g., Docker proxy):
```text
   ERROR  Failed to listen on 127.0.0.1:3000 (reason: Address already in use).

  Port 3000 is currently occupied by another process.
  Try specifying a different port:
    railst run -p 3001

  Or run with automatic port selection:
    railst run --find-port
```

---

### Complete `railst` Command Reference

| Command | Description |
| :--- | :--- |
| `railst run [options]` | Start the Rails development server with Rust auto-compilation and clean output |
| `railst build` | Compile the native `ext/rust_backend` crate via Cargo into `lib/rust_backend/` |
| `railst test [path]` | Run native Rust unit tests (`cargo test`) and the Rails test suite |
| `railst ci` | Run the complete 7-step Continuous Integration verification pipeline |
| `railst g rust:resource <Name> [field:type]` | Scaffold unified resource: migration, `RustBacked` model, controller, and routes |
| `railst g rust:service <Name>` | Generate a dedicated Ruby service wired to native Rust functions |
| `railst c` | Open the interactive Rails console with the `RustBackend` namespace loaded |
| `railst db [action]` | Execute database operations (`migrate`, `rollback`, `prepare`, `seed`) |
| `railst setup` | Install gem dependencies, prepare database, and compile Rust extension |
| `railst clean` | Clean Cargo build target artifacts in the Rust crate |
| `railst install` | Install the `railst` binary globally into the user binary directory |
| `railst help` | Display command-line usage and available options |

---

## 3. Frontend Landing Experience (Rust + Ruby Fusion Palette)

The default Rails welcome screen ("Yay! You're on Rails!") has been replaced with a modern, elegant, and concise frontend interface.

### Design Features:
* **Rust & Ruby Fusion Palette**: Combines signature Rust metallic copper/bronze tones (`#CE412B`, `#E57353`) with rich Ruby crimson and deep garnet accents (`#CC342D`, `#700010`).
* **Dark Glassmorphic Surface**: Built on a deep obsidian canvas (`#0A0A0D`) with subtle ambient radial glow accents and blurred glassmorphic containers.
* **Interactive Live In-Browser Benchmark Widget**: Live sandbox allowing developers to benchmark in-process Rust FFI latency directly from their browser. Choose from 10,000 to 100,000 data points to calculate throughput and sub-millisecond reduction times in real time.
* **Architecture Diagnostics Grid**: Live status indicators for Magnus 0.9 FFI status, Ruby GVL release mode, detected CPU cores via Rayon, Rails 8.1, Ruby 3.4, and database adapters.
* **Zero Emojis**: Crisp vector SVG icons integrated cleanly throughout the layout.

---

## 4. Prerequisites and Installation Guide

### System Requirements
* **Ruby**: Version 3.4.x or later with C header development files (`ruby.h`).
* **Rust & Cargo**: Installed via `rustup` (recommended) or system package manager.
* **Clang / LLVM Libraries**: Required by `bindgen` during `rb-sys` compilation.

### Step 1: Shell Environment Configuration
Add the following configuration lines to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
# User gem binaries and Cargo toolchain paths
export PATH="$HOME/.cargo/bin:$(ruby -r rubygems -e 'puts Gem.user_dir')/bin:$PATH"

# Clang library path and bindgen include arguments
export LIBCLANG_PATH="$HOME/.local/lib"
export BINDGEN_EXTRA_CLANG_ARGS="-I$HOME/.local/lib/clang/23/include"
```

Reload your shell after saving:
```bash
source ~/.bashrc  # Or: source ~/.zshrc
```

### Step 2: Automated Project Setup
In the project root directory, run:

```bash
bin/setup --skip-server
```

This automated setup script:
1. Verifies and installs all gem dependencies (`bundle install`).
2. Compiles the native Rust extension into `lib/rust_backend/rust_backend.so`.
3. Prepares the SQLite database (`bin/rails db:prepare`).
4. Installs the `railst` CLI command.
5. Clears stale log and temporary files.

### Step 3: Starting the Server
```bash
railst run -p 3001
# Or: railst run --find-port
```
Access the application in your browser at `http://127.0.0.1:3001`.

---

## 5. Guide to Building Application Components

The framework preserves 100% of standard Rails conventions while offering native Rust acceleration where needed.

### Method A: Scaffold a Unified Rust Resource (Recommended)
To generate a new resource ready for high-volume data crunching with native Rust:

```bash
railst g rust:resource Invoice customer:string amount:decimal status:string
```

This generator automatically produces:
1. **Database Migration**: File at `db/migrate/..._create_invoices.rb`.
2. **ActiveRecord Model**: File at `app/models/invoice.rb` with `include RustBacked`.
3. **Controller**: File at `app/controllers/invoices_controller.rb` with standard CRUD and parallel endpoints:
   * `POST /invoices/process_batch` (Multi-core batch processing via Rayon).
   * `GET /invoices/metrics?field=amount` (Parallel statistical reduction via Rayon).
4. **Routing**: Declares `resources :invoices` with `process_batch` and `metrics` collection routes in `config/routes.rb`.
5. **Integration Tests**: Test file at `test/controllers/invoices_controller_test.rb`.

Execute the database migration after scaffolding:
```bash
railst db migrate
```

---

### Method B: Connecting Existing Models and Migrations Manually
If you have existing Rails models or prefer creating migrations manually:

#### 1. Create the Database Migration
```bash
bin/rails generate migration CreateProducts name:string price:decimal quantity:integer
railst db migrate
```

#### 2. Attach the Rust Concern to Your Model
Add `include RustBacked` to your model:

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  include RustBacked

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
```

Once included, the model gains high-performance methods:
```ruby
# Single-record processing
product = Product.first
product.process_with_rust

# Batch processing thousands of records concurrently without blocking the HTTP thread
records = Product.all.as_json
Product.rust_batch_process(records, { "multiplier" => 1.1, "compute_field" => "price" })

# Parallel metrics aggregation (count, sum, avg, min, max)
Product.rust_aggregate(Product.all, "price")
```

#### 3. Implement Custom Controller Actions
Generate a standard Rails controller:
```bash
bin/rails generate controller Products
```

Implement the batch call in the controller:
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

### Method C: Creating a Custom Rust Service Layer
For standalone algorithms, heavy analytics, or business logic independent of CRUD operations:

```bash
railst g rust:service AnomalyDetector
```

This generates a service object at `app/services/rust/anomaly_detector_service.rb`:
```ruby
module Rust
  class AnomalyDetectorService
    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end

    def call
      # Call native RustBackend functions directly
      RustBackend.process_batch(@records, @config)
    end
  end
end
```

---

### Method D: Adding New Functions to the Native Rust Crate
To extend the native Rust backend with custom algorithms:

1. Create or edit a module in `ext/rust_backend/src/`.
2. Write the native Rust function:
   ```rust
   // ext/rust_backend/src/custom_calc.rs
   use magnus::{Error, Ruby, Value};

   pub fn complex_hash_operation(ruby: &Ruby, input: String) -> Result<String, Error> {
       // Pure CPU-intensive computation
       Ok(format!("processed: {}", input))
   }
   ```
3. Register the function in `ext/rust_backend/src/lib.rs`:
   ```rust
   pub mod custom_calc;

   #[magnus::init]
   fn init(ruby: &Ruby) -> Result<(), Error> {
       let module = ruby.define_module("RustBackend")?;
       module.define_singleton_method(
           "complex_hash_operation",
           magnus::function!(custom_calc::complex_hash_operation, 1)
       )?;
       Ok(())
   }
   ```
4. Rebuild the extension:
   ```bash
   railst build
   ```

---

## 6. Testing & Quality Assurance

The framework provides three tiers of testing to ensure system stability and performance:

### 1. All-in-One Continuous Integration Pipeline
```bash
railst ci
```
Runs RuboCop style audits, gem vulnerability scanning (`bundler-audit`), importmap auditing, Brakeman static security analysis, native Rust unit tests, and the Rails integration test suite.

### 2. Rails & FFI Integration Test Suite
```bash
railst test
```
Runs Minitest across models, controllers, and FFI integration (`test/lib/rust_backend_test.rb`). Build hooks automatically recompile Rust code if native source files are modified.

### 3. Native Rust Crate Unit Tests
```bash
bin/rake rust:test
```
Runs `cargo test` directly inside the `ext/rust_backend` crate.

---

## 7. Anti-Spaghetti Architectural Principles

To maintain high performance and codebase clarity as your project scales:

1. **Clear Separation of Concerns**:
   * **Rails (Ruby)**: Manages HTTP validation, parameter parsing, database relations, business associations, and schema migrations.
   * **Rust**: Manages compute-intensive algorithms, large-scale data transformations, hashing, and parallel multi-core reductions.
2. **No SQL Queries in Rust**:
   Allow ActiveRecord to govern database connections and query generation. The Rust engine receives in-memory dynamic hashes/arrays or JSON values and returns processed results without database coupling.
3. **Crate Modularity**:
   Avoid centralizing all logic inside `ext/rust_backend/src/lib.rs`. Isolate functional domains into dedicated modules (`data_processor.rs`, `dynamic_hash.rs`, `gvl.rs`) with corresponding `#[test]` unit tests in each file.

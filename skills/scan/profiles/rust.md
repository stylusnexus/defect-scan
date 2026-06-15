---
name: rust
detect_files: Cargo.toml Cargo.lock
extensions: rs
tools: clippy cargo-audit cargo-deny
---
# Profile: rust

**Honesty up front:** Rust's borrow checker + type system reject use-after-free,
double-free, data races on `Send`/`Sync` types, and null derefs **at compile time** —
this profile does **not** claim to catch those (they never reach the scanner). The
residual reasoning surface is narrower than other languages and concentrates on what
the compiler still misses: **panics on recoverable paths, `unsafe` invariants,
logic/API-misuse, and supply chain.**

## Detection
A `Cargo.toml` (always present) or `Cargo.lock`, plus any `*.rs`. The `edition` in
`Cargo.toml` gates a few lints; detection needs only the manifest. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. Build-dependency split: **`clippy` must
build the crate** (it's a rustc driver loading all deps) → degrades on a tree that
won't compile offline (skip-with-hint); **`cargo audit` only needs `Cargo.lock`**
(no build) so it works regardless.
- `cargo clippy --all-targets --message-format=json` (CI form: `… -- -D warnings`) —
  ~750 lints. Groups: **correctness** (default `deny` — almost-certainly bugs),
  **suspicious**, **complexity**, **perf**, **style** (all in `clippy::all`).
  `pedantic`/`nursery`/**`restriction`** are default-`allow` — **never enable
  `restriction` wholesale** (it lints reasonable code); pull individual restriction
  lints by name (`unwrap_used`, `expect_used`, `indexing_slicing`,
  `arithmetic_side_effects`, `undocumented_unsafe_blocks`). Install: `rustup component
  add clippy`.
- `cargo audit --json` — `Cargo.lock` vs the **RustSec advisory DB** (vuln/unmaintained/
  yanked crates); no build; High. Install: `cargo install cargo-audit`. Never auto-fixed.
- `cargo deny check` (optional, broader) — `advisories` + `licenses` + `bans`
  (duplicate/banned crates) + `sources`. Install: `cargo install --locked cargo-deny`.

## Reasoning checklist
The borrow checker already removed memory-safety bugs; focus on the residual:
- Rust-specific (panic-as-uncaught-exception, the #1 real Rust bug): **`.unwrap()`/
  `.expect()`/`panic!`/`todo!`/`unimplemented!`/`unreachable!` on recoverable paths** —
  panics in prod instead of propagating via `?` (clippy::unwrap_used/expect_used/panic —
  restriction, default-allow, **no autofix**; CWE-248/617).
- cat#2: **ignored/swallowed errors** — `let _ = fallible()` deliberately discards a
  `Result` (the implicit `fallible();` form is caught by rustc `unused_must_use`; the
  `let _ =` form is the reasoning catch); `.ok()` dropping the error,
  `.unwrap_or_default()` masking a real failure, `if let Err(_) = … {}` (CWE-252/703).
- cat#1: panic-prone **slicing/indexing** `v[i]`/`&s[a..b]` vs `.get(i)` returning
  `Option` (clippy::indexing_slicing, CWE-125); lossy/truncating **`as` casts**
  (`x as u8`, sign loss, `u64 as f64`) vs `TryFrom`/`try_into`
  (clippy::cast_possible_truncation/cast_sign_loss/cast_precision_loss — **pedantic**
  group, default-allow, enabled differently from the restriction lints; CWE-197/704);
  `Option`/`Result` combinator chains that silently turn `None`/`Err` into a default.
- cat#3 (Rust does NOT prevent these): **command injection** — `std::process::Command`
  with `sh -c` + interpolated untrusted input (CWE-78); **SQL injection** — query built
  with `format!`/`+` vs parameterized/query-builder (CWE-89); path traversal — untrusted
  input into `std::fs`/`Path` without containment (CWE-22).
- cat#4: leaks via `mem::forget`/`Box::leak`/`ManuallyDrop` suppressing `Drop`
  (memory/handle/lock leak — safe, not UB, but a real leak if unintended; CWE-401).
- cat#5: **`Mutex`/`RwLock` poisoning** — `.lock().unwrap()` propagates a poisoned-lock
  panic; **holding a `std::sync` guard across `.await`** (deadlock / non-`Send` —
  clippy::await_holding_lock, CWE-667/833); **blocking calls in `async`** —
  `std::thread::sleep`/`std::fs`/`std::net` inside an `async fn` stalls the executor;
  use `tokio::*`/`spawn_blocking` (reasoning-only; resource starvation).
- Rust-specific: **`unsafe` blocks** lacking a `// SAFETY:` justification (raw-pointer
  deref, `transmute`, FFI, `get_unchecked` — clippy::undocumented_unsafe_blocks/
  missing_safety_doc; never auto-fixed — soundness is a human argument); **integer
  overflow** — `a + b`/`a * b` panics in debug, silently **wraps in release**; use
  `checked_`/`saturating_`/`wrapping_` (clippy::arithmetic_side_effects, CWE-190);
  **float `==`** (clippy::float_cmp — correctness, on by default; CWE-697). Lower-tier: `.clone()` in a hot loop /
  needless allocation (clippy perf — rarely a defect).

## Auto-fix-safe
`cargo fmt` (pure formatting) and the clippy **style/complexity** machine-applicable
rewrites (`needless_return`, `map_clone`, `useless_vec`, idiomatic-iterator) via
`cargo clippy --fix`. **Never auto-fix**: restriction lints (`unwrap_used`/`expect_used`/
`indexing_slicing`/`arithmetic_side_effects`/`undocumented_unsafe_blocks` — no autofix
by design; the fix is a human decision), **correctness** findings (verify intent), any
`unsafe`-related finding (soundness is a human argument), `cargo audit`/`cargo deny`
results (a dep bump needs review + tests), and cat#2/#3/#5 (semantic/security decisions).

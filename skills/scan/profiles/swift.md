---
name: swift
detect_files: Package.swift
extensions: swift
tools: swiftlint swift-format
---
# Profile: swift

## Detection
A `Package.swift` (SwiftPM manifest) or any `*.swift`. Xcode projects are
`*.xcodeproj`/`*.xcworkspace` **directories** (globs, not literal filenames), so they
can't be `detect_files`; the `swift` extension carries detection for Xcode-only apps.
See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. Both are **source-only** — no build/Xcode/
resolved deps needed.
- `swiftlint lint --reporter json` — the main Swift linter (~200 rules). **Critical
  gotcha: the crash-rules are split.** `force_cast` and `force_try` are **default-on**,
  but `force_unwrapping`, `implicitly_unwrapped_optional`, `weak_delegate`, and
  `unowned_variable_capture` are **opt-in** (`opt_in_rules:` in `.swiftlint.yml`) — so on
  a repo without those opt-ins, the #1 Swift footgun (force-unwrap) is **invisible to the
  tool**; the reasoning pass must catch it regardless. Install: `brew install swiftlint`.
- `swift-format lint --recursive --configuration <file> <paths>` — Apple's official
  formatter/linter (bundled with Swift 6 / Xcode 16, or `brew install swift-format`).
  Has correctness rules `NeverForceUnwrap`/`NeverUseForceTry`.
- Deeper: `xcodebuild analyze` / the Clang static analyzer catches data-flow/memory
  issues the source linters miss, but needs the full toolchain + resolved packages —
  out of scope for the source-only default; skip-with-hint.

## Reasoning checklist
Baseline categories specialized (SwiftLint rule / CWE):
- cat#1: **force-unwrap `!`** on an optional — `dict["k"]!`/`view!.frame` crashes on nil,
  the #1 Swift crash (`force_unwrapping`, **opt-in**; swift-format `NeverForceUnwrap`;
  CWE-476); **`try!`** force-try traps on a thrown error (`force_try`, default;
  `NeverUseForceTry`); **`as!`** force cast crashes on a type mismatch — use `as?` +
  bind (`force_cast`, default); **implicitly-unwrapped optionals (`T!`)** read while nil
  (e.g. a `var label: UILabel!` accessed before it's wired — `implicitly_unwrapped_optional`,
  opt-in). All CWE-476.
- cat#2: **`try?`** discarding the thrown error → silent `nil`; empty/`print`-only
  `catch {}` losing the error (CWE-390/703).
- cat#4: **retain cycle** — strong `self` captured in an escaping closure (network
  completion, `Timer`, Combine `sink`, `Task {}`) without `[weak self]` keeps the owner
  alive forever (ARC leak; related `weak_delegate` — a `delegate` must be `weak`;
  CWE-401); **`unowned`** reference that can outlive its referent → crash on access
  (unlike `weak`, which goes nil; `unowned_variable_capture`, opt-in; CWE-416).
- cat#5: **main-thread (UI) violations** — mutating UIKit/SwiftUI state off the main
  thread (e.g. inside a `URLSession` completion or background `DispatchQueue` without
  hopping to `DispatchQueue.main`/`@MainActor`), or blocking the main thread with sync
  I/O (CWE-662); **data races** — a `var`/cache/array read+written from multiple
  `DispatchQueue`/`Task` contexts without a serial queue/lock/actor; passing
  non-`Sendable` types across concurrency boundaries (CWE-362).
- cat#3: **SQL injection** — string-interpolated queries against SQLite/GRDB/FMDB vs `?`
  bound parameters (CWE-89); **insecure secret storage** — keys/tokens in `UserDefaults`
  (unencrypted, backed up) instead of the Keychain, or hardcoded in source (CWE-312/798);
  **weak crypto / insecure randomness** — MD5/SHA-1/DES/ECB for security, or
  `arc4random`/`Int.random` for security tokens where a CSPRNG (`SecRandomCopyBytes`/
  CryptoKit) is required (CWE-327/338).
- Swift-specific: **`fatalError()`/`preconditionFailure()`/`assertionFailure()` on a
  recoverable path** — a hard trap for input validation or a handleable server response
  turns recoverable into a crash (`precondition`/`fatalError` fire in release; `assert`
  does not — so `assert`-guarded logic the code then relies on is its own bug; CWE-617).

## Auto-fix-safe
Only `swiftlint --fix` and `swift-format format -i` (formatting/style — indentation,
spacing, ordering — no semantic change). **Never auto-fix**: `force_unwrapping`/
`force_cast`/`force_try`/`implicitly_unwrapped_optional` (replacing a `!` with safe
binding is a human decision about the nil path), retain-cycle/`[weak self]` findings
(adding `weak` changes ownership), main-thread/data-race/concurrency findings, and all
cat#3 security items (SQLi, Keychain, crypto/randomness).

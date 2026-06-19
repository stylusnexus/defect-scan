---
name: objc
detect_files: Podfile
extensions: m mm
tools: clang-tidy oclint
---
# Profile: objc

## Detection
A `Podfile` (CocoaPods manifest) or any `*.m` (Objective-C implementation) / `*.mm`
(Objective-C++) source. **`.h` is deliberately not claimed** — it is shared with C/C++
and would mislabel pure C/C++ headers as Objective-C; an `.h`-only tree falls through to
`generic`. Xcode projects are `*.xcodeproj`/`*.xcworkspace` **directories** (globs, not
literal filenames), so they can't be `detect_files`; the `m`/`mm` extensions carry
detection for Xcode-only apps. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. Objective-C analysis is **build-context
sensitive** — full data-flow needs the SDK headers and a compilation database; both tools
below degrade to best-effort syntax/AST checks without one (skip-with-hint if absent).
- `clang-tidy <file> -- -x objective-c -fobjc-arc` — runs the Clang static analyzer +
  clang-tidy checks; the source-friendly default (single-file, no `compile_commands.json`
  needed, though SDK headers sharpen it). Pass `-x objective-c++` for `.mm`. Useful checks:
  `clang-analyzer-*` (nil-deref, leaks, use-after-free), `bugprone-*`. Install:
  `brew install llvm` (then `clang-tidy` is on the LLVM path).
- `oclint <file> -- -x objective-c` — dedicated Objective-C/C/C++ linter (~70 rules). For
  a real project it wants a compilation database (`oclint-json-compilation-database`, from
  `xcodebuild` + `xcpretty`); single-file mode is shallower. Install: `brew install oclint`.
- Deeper: `xcodebuild analyze` / `scan-build` (the Clang static analyzer over a full
  build) catches the memory and data-flow issues the source-only pass misses, but needs
  the full toolchain + resolved Pods — out of scope for the source-only default;
  skip-with-hint.

## Reasoning checklist
Baseline categories specialized (Clang-analyzer check / CWE):
- cat#1: **nil-message semantics masking failure** — sending a message to `nil` is a
  silent no-op returning `0`/`nil`/zeroed struct, so a failed `init`/lookup propagates as
  bogus data rather than a crash (CWE-476); **`objectAtIndex:` out of range** throws
  `NSRangeException`, and **inserting `nil`** into `NSArray`/`NSMutableDictionary` throws —
  unchecked, both are hard crashes (`clang-analyzer-core.NullDereference`; CWE-129/476).
- cat#2: empty `@catch (NSException *e) {}` / `print`-only catch swallowing the exception
  (CWE-390); **`NSError**` out-param ignored** — checking `error != nil` *instead of* the
  `BOOL`/`nil` return value is a bug: Cocoa methods may set `error` on success, so the
  return value is the source of truth and the error is only meaningful when it fails
  (CWE-252/703).
- cat#3: **format-string injection** — `NSLog(userInput)`, `[NSString
  stringWithFormat:userControlled]`, `[NSException raise:format:]` with a user-controlled
  format string → info leak / crash via `%@`/`%n` (`clang-analyzer-security.FormatString`;
  CWE-134); **SQL injection** — string-formatted FMDB/`sqlite3_exec` queries vs `?` bound
  parameters (CWE-89); **insecure secret storage** — tokens/keys in `NSUserDefaults`/plist
  (unencrypted, backed up) instead of the Keychain, or hardcoded (CWE-312/798); **weak
  crypto / RNG** — CommonCrypto MD5/SHA-1/DES/`kCCOptionECBMode` for security, or
  `arc4random`/`rand` where a CSPRNG (`SecRandomCopyBytes`) is required (CWE-327/338);
  **disabled TLS validation** — `NSURLSession`/`NSURLConnection` delegate that calls
  `continueWithoutCredentialForAuthenticationChallenge` / trusts any server cert (CWE-295).
- cat#4: **retain cycle (ARC)** — strong `self` captured in a block stored on the object
  (completion handler, `dispatch_after`, `NSTimer`, KVO) without `__weak typeof(self)
  weakSelf = self;` keeps the owner alive forever (CWE-401); **observer not torn down** —
  `dealloc` that fails to `removeObserver:`/invalidate a `NSTimer` → message to a freed
  object when the notification/KVO fires (`clang-analyzer-core.UseAfterFree`; CWE-416);
  **MRC imbalance** (non-ARC files) — `retain`/`alloc` without a matching `release`, or an
  over-release/double-`release` (CWE-401/415).
- cat#5: **main-thread (UI) violations** — UIKit/AppKit mutated off the main thread (inside
  a `NSURLSession` completion or background `dispatch_queue` without hopping to
  `dispatch_get_main_queue()`) (CWE-662); **data races** — a `NSMutableArray`/
  `NSMutableDictionary`/ivar read+written from multiple GCD queues without a serial
  queue/`@synchronized`/lock (CWE-362).
- objc-specific: **format-specifier vs argument mismatch** in `stringWithFormat:`/`NSLog`
  — `%@` given a primitive (or `%d`/`%ld` given an object) crashes or prints garbage
  (`clang-diagnostic-format`; CWE-686); **`BOOL` is a signed char**, so `if (someInt ==
  YES)` (YES == 1) fails for any non-1 truthy value — compare to `!= NO` or `!= 0`;
  **`isEqual:` vs `==`** — `==` compares object identity (pointers), not value, for
  `NSString`/`NSNumber`.

## Auto-fix-safe
**None auto-applied.** `clang-tidy --fix` and `oclint` fix-its for Objective-C are not a
reliably behavior-preserving set (memory-management and nil-handling rewrites change
semantics), and neither bundled tool is a pure formatter. Every finding is human-review;
defer remediation to `/review-merge-pipeline`.

---
name: kotlin
detect_files: build.gradle.kts settings.gradle.kts
extensions: kt kts
tools: detekt ktlint
---
# Profile: kotlin

## Detection
A `build.gradle.kts`/`settings.gradle.kts`, or any `*.kt`/`*.kts`. An
`AndroidManifest.xml` / `android {}` block / `com.android.application` plugin gates the
Android-only toolchain + Android checklist items. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. detekt/ktlint are source-only binaries, **but
detekt's highest-value rules need *type resolution*** (a resolved classpath) — without
it `UnsafeCallOnNullableType`, `UnsafeCast`, `MapGetWithNotNullAssertionOperator`,
`IgnoredReturnValue` **silently produce nothing** (not an error). This is the Kotlin
analog of "SpotBugs needs bytecode": pass `--classpath`/`--jvm-target` or run the Gradle
`detektMain` task; otherwise skip-with-hint — don't read a source-only run as a clean
nullness pass.
- `detekt --input src --report sarif:detekt.sarif` (add `--classpath "<deps>"
  --jvm-target 17`, or run Gradle `detektMain`) — the main analyzer. Rule-sets: comments,
  complexity, coroutines, exceptions, naming, performance, potential-bugs, style, plus a
  `formatting` ruleset wrapping ktlint. Install: `brew install detekt`.
- `ktlint --reporter=json "src/**/*.kt"` — formatting/style; `--format` auto-fixes.
  Source-only. Redundant if detekt runs the `formatting` ruleset — run one. Install:
  `brew install ktlint`.
- `./gradlew lint` (Android only — needs a Gradle build) → `lint-results*.xml`:
  resource/manifest/API-level + security (`ExportedReceiver`/`ExportedService`,
  `SetJavaScriptEnabled`, `AddJavascriptInterface`, `TrustAllX509TrustManager`).

## Reasoning checklist
Baseline categories specialized (detekt rule / CWE):
- cat#1: **`!!` not-null assertion** on a nullable — the #1 Kotlin footgun → NPE
  (`UnsafeCallOnNullableType`, type-resolution; `map[k]!!` is
  `MapGetWithNotNullAssertionOperator`; CWE-476); **platform types from Java interop**
  (a Java value typed `String!` derefed without a null check → NPE at the boundary;
  needs the Java classpath resolved); **`lateinit` read before init** →
  `UninitializedPropertyAccessException` (`LateinitUsage`; guard with
  `::prop.isInitialized`); **unsafe cast `as`** vs `as?` → `ClassCastException`
  (`UnsafeCast` type-resolution / `SafeCast`; CWE-704).
- cat#2: swallowed exceptions — `catch (e: Exception) {}` / caught-but-unused
  (`SwallowedException` — note detekt has **no** `EmptyCatchBlock` rule), over-broad
  catch (`TooGenericExceptionCaught`), `printStackTrace()` as the only handling
  (`PrintStackTrace`), `return`/throw inside `finally` masking the real exception
  (`ReturnFromFinally`/`ThrowingExceptionFromFinally`); CWE-390.
- cat#5: **`GlobalScope`** → unstructured coroutines that outlive the caller and leak
  (`GlobalCoroutineUsage`); **swallowing `CancellationException`** in a `runCatching`/
  generic catch around a suspend call breaks structured concurrency
  (`SuspendFunSwallowedCancellation`); blocking in a coroutine — `Thread.sleep` in a
  suspend fn (`SleepInsteadOfDelay`), `runBlocking` on the UI thread, hardcoded
  `Dispatchers.IO`/`Default` instead of an injected dispatcher (`InjectDispatcher`);
  mutable shared state across coroutines/threads without a `Mutex`/atomic (`DoubleMutability`; CWE-362).
- cat#4: a `Closeable`/`AutoCloseable` (`File`/`InputStream`/`Cursor`/OkHttp `Response`)
  opened without `.use {}` — not closed on the exception path (CWE-404/772).
- cat#3: **SQL injection** — string-template/`+`-built queries vs bound parameters
  (CWE-89); command injection `Runtime.exec`/`ProcessBuilder` with interpolated input
  (CWE-78). Android: exported components without permissions
  (`ExportedReceiver`/`Service`/`ContentProvider`; CWE-926), `WebView`
  `setJavaScriptEnabled(true)` + `addJavascriptInterface` exposing native methods to web
  content (`SetJavaScriptEnabled`/`AddJavascriptInterface`; CWE-749), hardcoded secrets
  (CWE-798), implicit-`Intent` injection (CWE-927).
- Kotlin-specific: `equals`/`hashCode` — overriding one not the other
  (`EqualsWithHashCodeExist`, CWE-581); `==` vs `===` (structural vs referential)
  confusion (reasoning); **ignored return** of a must-use function (`IgnoredReturnValue`,
  type-resolution; CWE-252).

## Auto-fix-safe
Only `ktlint --format` and `detekt --auto-correct` **with the `formatting` ruleset
only** (whitespace/imports/trailing commas — no semantic change). detekt's non-formatting
rulesets do **not** support auto-correct. **Never auto-fix**: every potential-bugs
finding (`UnsafeCallOnNullableType`/`UnsafeCast`/`MapGetWithNotNullAssertionOperator`/
`LateinitUsage`/`IgnoredReturnValue` — removing a `!!`/cast changes behavior),
exceptions/coroutines findings, all injection/security findings, and Android Lint
results (manifest/WebView/exported-component changes need human review + tests).

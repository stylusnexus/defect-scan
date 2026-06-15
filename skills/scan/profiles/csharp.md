---
name: csharp
detect_files: global.json Directory.Build.props Directory.Packages.props nuget.config
extensions: cs csproj
tools: dotnet security-scan roslynator
---
# Profile: csharp

## Detection
A `*.csproj`/`*.sln` or any `*.cs` is the real trigger; `global.json`,
`Directory.Build.props`, `Directory.Packages.props`, `nuget.config` corroborate. The
`<TargetFramework>` in the csproj gates some rules (nullable-reference-types default,
`BinaryFormatter` disabled/throwing in net8, removed in net9). See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. **The SDK analyzers and SCS run as Roslyn
analyzers during compilation, so they need a restorable, buildable project** — on
source that won't restore (no network/missing deps) they degrade; skip-with-hint.
- `dotnet build -c Release /p:EnableNETAnalyzers=true /p:AnalysisLevel=latest /p:ErrorLog=analyzers.sarif%3bversion=2.1`
  — the .NET SDK Roslyn analyzers (CAxxxx); `ErrorLog` emits SARIF. `EnableNETAnalyzers`
  is on by default for net5+; `AnalysisMode=All` widens the rule set. Parse the SARIF
  (don't fail the build). Covers correctness (CA2000, CA2200, CA1062), security
  (CA2100, CA3075, CA53xx, CA23xx), reliability, and IDExxxx style. (resolve `dotnet`)
- `dotnet list package --vulnerable --include-transitive` — known-vuln NuGet deps;
  needs restore only (no full build); High. Findings never auto-fixed.
Optional (deeper, run if installed):
- `security-scan <sln> --export=sarif` — Security Code Scan taint rules (SCS####):
  SQLi (SCS0002), command injection (SCS0001), path traversal (SCS0018), XXE (SCS0007),
  insecure deserialization (SCS0028), XSS (SCS0029), open redirect (SCS0027), weak
  hash/cipher (SCS0006/0010/0013). Install: `dotnet tool install --global security-scan`.
- `roslynator analyze <sln>` — ~200 extra analyzers (dead code, simplifiable LINQ,
  multiple-enumeration). Install: `dotnet tool install -g roslynator.dotnet.cli`.
- `dotnet format analyzers --verify-no-changes --severity warn` — the safe-autofix probe.

## Reasoning checklist
Baseline categories specialized:
- cat#1: public-API args dereferenced without validation (CA1062); `!` null-forgiving
  operator overused to silence the compiler; nullable-reference-types disabled so the
  compiler gives no NRE help (CS8600-series), CWE-476.
- cat#2: empty/swallowing `catch {}` / `catch (Exception) {}` that logs nothing and
  continues (CA1031, CWE-390); `throw ex;` instead of bare `throw;` (resets the stack
  trace — CA2200); `async void` (exceptions can't be caught by the caller and crash the
  process — use `async Task` except for event handlers).
- cat#3: string-concatenated/interpolated SQL into `SqlCommand.CommandText` vs
  parameterized `SqlParameter` (CA2100 + SCS0002, CWE-89); `Process.Start`/
  `ProcessStartInfo.Arguments` with untrusted input (SCS0001, CWE-78); insecure
  deserialization — `BinaryFormatter`/`LosFormatter`/`NetDataContractSerializer`/
  `JavaScriptSerializer`, or Json.NET `TypeNameHandling`, on untrusted data (CA2300-
  series + SCS0028, CWE-502; `BinaryFormatter` throws in net8, removed in net9); XXE —
  `XmlReader`/`XmlDocument` with `DtdProcessing.Parse` or an unsafe `XmlResolver`
  (CA3075 + SCS0007, CWE-611); weak crypto MD5/SHA1 (CA5350/CA5351), DES/3DES/ECB,
  hardcoded keys; `System.Random` for tokens/IDs instead of `RandomNumberGenerator`
  (CA5394, CWE-338).
- cat#4: `IDisposable` created but not disposed before scope exit — missing `using` on
  `Stream`/`SqlConnection`/`DbCommand`/`FileStream` (CA2000, CWE-404/772); disposable
  fields not disposed (CA2213). Ownership nuance: dispose **owned** objects, never
  **injected/borrowed** ones.
- cat#5: sync-over-async deadlock — `.Result`/`.Wait()`/`.GetAwaiter().GetResult()`
  blocking a Task where a `SynchronizationContext` exists (classic ASP.NET, WPF/WinForms)
  — CWE-833; fire-and-forget Task never awaited; missing `ConfigureAwait(false)` in
  **library** code (CA2007 — app-level code is exempt); `DbContext` used concurrently
  (EF Core `DbContext` is not thread-safe — parallel awaits corrupt/throw, CWE-362);
  static mutable shared state / `ThreadStatic` misuse on request-scoped ASP.NET paths.
C#-specific: culture-sensitive `==`/`.ToLower()`/`.Equals` without an explicit
`StringComparison` (CA1310/CA1862); overriding `Equals` without `GetHashCode` or vice
versa (C# emits `CS0659`; `CA1815` for value types); `IEnumerable` multiple enumeration (re-runs the query/DB call);
mass-assignment / over-posting — binding `params`/request directly to EF entities
without a DTO or `[Bind]` allowlist (CWE-915).

## Auto-fix-safe
Only `dotnet format` (whitespace / `style` / the analyzer **formatting** subset —
IDE0xxx style, `using` ordering) and pure-style Roslynator code-fixes. **Never auto-fix**
any security `CAxxxx` (CA2100/CA3075/CA53xx/CA23xx), `CA2000`/`CA2213` (inserting
`using` can dispose a borrowed object / alter lifetime), `CA2200`/`CA1031`/`CA1062`
(error-handling & contract decisions), `CA2007` (context-dependent), any `SCSxxxx`
taint finding, or `dotnet list package --vulnerable` results (package bumps need human
review + tests).

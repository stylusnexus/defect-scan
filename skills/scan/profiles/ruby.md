---
name: ruby
detect_files: Gemfile .ruby-version Rakefile config.ru config/application.rb
extensions: rb rake gemspec ru
tools: rubocop brakeman bundler-audit
---
# Profile: ruby

## Detection
A `Gemfile`, `.ruby-version`, `Rakefile`, `config.ru`, or any `*.rb`/`*.gemspec`/
`*.rake`. A `config/application.rb` or `bin/rails` means treat it as **Rails** (enables
the Rails-specific tools + checks below). See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>` (global gem bin). Skip-with-hint if unresolved.
- `rubocop --format json --no-color <files>` — lint/correctness/security/Rails cops.
  Install: `gem install rubocop rubocop-rails rubocop-performance`. Per-offense JSON
  carries `cop_name` + `correctable`. Works on any Ruby; `Rails/*` cops need
  `require: rubocop-rails`.
Optional (deeper, run if installed):
- `brakeman -f json` (run from the Rails app root) — **Rails-only** data-flow security:
  SQL/command injection, mass assignment, unsafe redirect, dynamic render, XSS, unsafe
  deserialization, dangerous send/eval. No-ops on a non-Rails dir. Findings are High
  (tool-confirmed); its 3 confidence tiers map to High/Medium/Low. Install: `gem install brakeman`.
- `bundle audit check --update --format json` — known-vuln gems vs ruby-advisory-db
  (a dimension reasoning can't see); High. Install: `gem install bundler-audit`.
- `srb tc` — Sorbet type check, only if `sorbet/config` exists. Install: `gem install sorbet`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: method called on a value a prior call may have returned `nil` for
  (`NoMethodError on nil`); `&.` chains followed by an ordinary call that re-raises
  (`Lint/SafeNavigationChain`); `try` overuse hiding a real nil.
- cat#2: bare `rescue` / `rescue => e` with no re-raise or handling (swallows
  `StandardError` — `Lint/SuppressedException`); `rescue Exception` (traps
  `SignalException`/`SystemExit` — Ctrl-C/`exit` swallowed — `Lint/RescueException`).
- cat#3: string-built SQL (`where("x = '#{p}'")`, `order(params[:sort])`, raw
  `find_by_sql`) vs parameterized (Brakeman SQLi / `Rails/SqlInjection`, CWE-89);
  `send`/`public_send`/`constantize`/`eval`/`instance_eval` on user input (RCE/mass-
  assign — Brakeman Dangerous Send/Eval, `Security/Eval`, CWE-94); command injection
  via `system`/backticks/`%x`/`exec`/`open("|…")` with interpolation (Brakeman Command
  Injection, `Security/Open`, CWE-78); unsafe deserialization `YAML.load`/`Marshal.load`/
  `JSON.load` on untrusted data (use `YAML.safe_load` — `Security/YAMLLoad`/`MarshalLoad`,
  CWE-502); `params` into `redirect_to` (open redirect, CWE-601) or `render` (dynamic
  render path / LFI); `html_safe`/`raw`/`<%== %>` on user content (XSS — `Rails/OutputSafety`,
  CWE-79); multiline-anchor regex `^…$` instead of `\A…\z` in `validates format:`
  (validation/auth bypass + ReDoS, CWE-1333).
- cat#4: non-block `File.open`/`TCPSocket`/`Net::HTTP`/DB connection that leaks the
  handle if an exception fires before `close` — use the block form or `ensure`
  (`Style/AutoResourceCleanup`, CWE-772).
- cat#5: shared mutable state without sync under a threaded server (Puma) — class
  variables `@@x` (`Style/ClassVars`), mutable global constants not `freeze`d
  (`Style/MutableConstant`), `Thread.new` over shared collections.
Rails-specific: mass assignment / missing strong params (`Model.new(params[:x])` without
`permit` — Brakeman Mass Assignment, CWE-915); serializer/`render json:` leaking
sensitive attrs (`password_digest`, tokens — audience leak, P3, CWE-200); N+1 queries
(association iterated without `includes`/`preload`); `update_all`/`delete_all`/
`update_column` skipping validations & callbacks (`Rails/SkipsModelValidations`).
Ruby-specific: `||=` memoization of a falsey/`nil` value (re-runs forever); `==` vs
`eql?` vs `equal?` confusion / overriding `==` without `eql?`+`hash` (breaks Hash/Set
keys — `Lint/IdentityComparison`); monkey-patching core classes (silent behavior drift).

## Auto-fix-safe
Only `rubocop -a` (**safe** autocorrect — `SafeAutoCorrect: true`, semantics-preserving:
`Layout/*`, `Style/StringLiterals`, `Style/RedundantReturn`, unused-var cleanup). Never
run `rubocop -A` (`--autocorrect-all` includes unsafe, behavior-changing corrections).
Never auto-fix any `Security/*` cop, `Lint/RescueException`/`Lint/SuppressedException`
(narrowing the rescue changes semantics), `Rails/OutputSafety`/`SqlInjection`/
`SkipsModelValidations`, or `Lint/SafeNavigationChain`. Brakeman, bundler-audit, and
Sorbet findings are never auto-fixed.

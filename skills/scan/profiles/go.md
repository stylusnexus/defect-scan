---
name: go
detect_files: go.mod go.sum
extensions: go
tools: staticcheck golangci-lint govulncheck
---
# Profile: go

## Detection
A `go.mod`, `go.sum`, or any `*.go`. See `detect.sh stacks`. If `golangci-lint` is
installed it subsumes `go vet`/`staticcheck`/`errcheck`/`ineffassign` — prefer it as
the single runner and fall back to the standalone tools otherwise.

## Toolchain
Resolve each via `detect.sh tool <name>`. **All prefer a buildable module** (they load
packages via `go/packages`); on source that won't build (missing deps / no network)
they degrade — skip-with-hint, don't fail.
- `go vet ./...` — built into the toolchain (resolve `go`). Correctness analyzers:
  `printf`, `structtag`, `lostcancel` (context cancel never called), `loopclosure`
  (loop var captured in a closure, pre-1.22), `copylocks`, `httpresponse` (use `resp`
  before checking `err`). `go vet -json ./...` for structured output.
- `staticcheck -f json ./...` — the deep analyzer (SA = correctness, S = simplify,
  ST = style, U = unused). Install: `go install honnef.co/go/tools/cmd/staticcheck@latest`.
Optional (deeper, run if installed):
- `golangci-lint run --output.json.path=stdout ./...` — meta-runner bundling
  errcheck/govet/ineffassign/staticcheck/unused (gosec via `--enable gosec`). Install:
  `go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest`. (v2 JSON
  flag is `--output.json.path=stdout`, not the removed `--out-format`.)
- `govulncheck -json ./...` — official vuln scanner with reachability (low FP); High.
  Install: `go install golang.org/x/vuln/cmd/govulncheck@latest`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: nil-map **write** panic (`m[k]=v` on an unmade map — reads are safe, writes
  panic — staticcheck SA5000); nil-pointer/interface deref, esp. using a returned
  pointer before the `err != nil` check (go vet `httpresponse`, CWE-476); unhandled
  type assertion `v := x.(T)` without the comma-ok form (panics — use `v, ok :=`).
- cat#2: **unchecked errors** (the #1 Go bug) — an `error` return ignored or discarded
  with `_ =` (`errcheck` / gosec G104, CWE-703); `err` checked but the branch does
  nothing / continues on the zero value (staticcheck SA9003); **`err` shadowed** by
  `:=` in an inner scope so the outer `err` stays nil and a later check passes
  spuriously (staticcheck SA4006 / `ineffassign`).
- cat#3: SQL injection via `fmt.Sprintf`/`+` into a query vs placeholders +
  `db.Query(q, args...)` (gosec G201/G202, CWE-89); command injection — `exec.Command`/
  `sh -c` with interpolated input (gosec G204, CWE-78); path traversal — untrusted path
  into `os.Open` without `filepath.Clean`/containment (gosec G304, CWE-22);
  integer-overflow narrowing conversions (gosec G115, CWE-190); `math/rand` where
  `crypto/rand` is required for tokens/IDs (gosec G404, CWE-338).
- cat#4: unclosed `resp.Body`/`*sql.Rows`/`*os.File`/`net.Conn` — missing `defer
  Close()` (HTTP body must close even on non-2xx; CWE-772); **`defer` inside a loop**
  (deferred calls run at *function* return, so handles accumulate); lost context cancel
  — `context.WithCancel/WithTimeout` whose `cancel` is never `defer`-called (goroutine/
  timer leak — go vet `lostcancel`); `time.After` in a `select` loop (timer leak per
  iteration).
- cat#5: data races / unsynchronized shared map/slice/counter across goroutines
  (concurrent map write panics; verify with `go test -race ./...`, CWE-362);
  `sync.WaitGroup` misuse — `wg.Add` inside the goroutine, or `wg.Done` not deferred so
  a panic skips it (staticcheck SA2000); mutex copied by value (go vet `copylocks`);
  deferred `Lock` instead of `Unlock` (staticcheck SA2003).
Go-specific: **loop-variable capture** in goroutines/closures, fixed only if `go.mod`
declares `go 1.22`+ — flag it for modules pinned below 1.22 (go vet `loopclosure`); the
related **taking the address of a range variable** (`&v`) is gosec G601 ("implicit
memory aliasing", Go ≤1.21); slice aliasing — a sub-slice + `append` sharing a backing
array corrupts the parent (no 3-index cap); passing a literal `nil`
`context.Context` (staticcheck SA1012), and the reasoning-only cousin of dropping the
caller's `ctx` for `context.Background()` where cancellation should thread; deprecated
API use, e.g. `io/ioutil` (staticcheck SA1019).

## Auto-fix-safe
Only `gofmt -w` / `goimports -w` (pure formatting + import ordering — never change
semantics). `golangci-lint run --fix` may be used for the formatting/simplification
subset only. `staticcheck` has no general CLI `-fix` (report-only). **Never auto-fix**
`errcheck` (handling a dropped error is a human decision), any `gosec` G-code (security
context), `go test -race` findings, or nil-map/nil-deref/concurrency findings.

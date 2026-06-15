# Recurring Defect Patterns (battle-tested)

Higher-order, cross-cutting patterns distilled from real production incidents.
The reasoning pass (SKILL.md Stage 3) consults these in addition to the five
`baseline-categories.md` and the active profile's checklist. Each pattern is
language-agnostic; the examples show how it tends to manifest.

**What belongs here (the inclusion test).** A pattern earns a `P` slot **only if it
is language-agnostic** — defined by *semantics or architecture*, so the same defect
concept could recur in Python **and** Go **and** Java (charge/refund ordering,
identifier drift across boundaries, authorization-on-output, injection-into-a-sink).
The litmus: *"would this same defect class appear in ≥2 unrelated languages?"* If yes,
it's a pattern here. If the detection keys on a specific language's construct, idiom,
or API (`except:` bare-clause, `key={index}`, an unchecked Go `err`, a C# `IDisposable`
not in a `using`), it belongs in **that language's profile checklist** instead — where
it can map to a `cat#` and *cite* the relevant `P#` rather than re-explaining it.
Product/org-specific detections (one app's billing rules, routes, field names) go in a
repo's **project pattern pack** (`.defect-scan/patterns/`), never here. Keep the three
tiers distinct: `baseline-categories.md` (5 universal categories) → this file (named
cross-cutting patterns) → profiles (language specializations that reference both).

**Default severities** (suggested baselines — *not* confidence; context/project can
override, see `baseline-categories.md`):

| Pattern | Default severity |
|---------|------------------|
| P1 metered-action correctness | High |
| P2 identifier drift | Medium |
| P3 privileged-audience leak | High |
| P4 subprocess/arg injection | High |
| P5 partial-fetch overwrite | High |
| P6 pagination default-limit / N+1 | Medium |
| P7 mock-only tests | Low |
| P8 ETL silent data-loss | High |
| P9 SQL schema/type drift | High |
| P10 missing security headers | Medium |

---

## P1 — Metered-action correctness (charge/quota ordering + compensation)

**Generic defect:** An operation that consumes a metered resource — credits,
quota, rate-limit tokens, a paid external API call, a usage counter, seats —
deducts at the wrong time or fails to compensate on a failure path.

**Invariants to check:**
1. **Deduct after validation.** The charge happens *after* input validation, not
   before — invalid/rejected/sanitization-blocked input must not be billed.
2. **Deduct after (or atomically with) the deliverable.** The charge is committed
   only once the work is durably produced; or every early-return/throw *after* the
   charge runs a compensating refund.
3. **Idempotent retries.** A retried or duplicated request does not double-charge
   (idempotency key, or charge-once semantics).
4. **No charged-but-empty / delivered-but-free.** A success returns iff a charge
   occurred; a no-op/early-return returns neither a charge nor a phantom result.

**Detection heuristic:** Locate the deduct/charge/increment call. Trace every
`return`/`throw`/early-exit between it and successful completion — each must
refund or be unreachable. Confirm validation precedes it. Look for retry paths
lacking an idempotency guard.

**Why it recurs:** the charge call is added once; new return paths (cache hit,
queue enqueue failure, tier check, sanitization block) get added later without
revisiting the compensation contract.

**Seen in the wild:** a charge committed before input validation; no compensating
refund on an async early-return or a downstream failure; a retried/duplicated
request double-charges; a cache-hit or no-op path that returns success without a
charge (delivered-but-free) or charges without delivering (charged-but-empty).

---

## P2 — String-keyed identifier drift across boundaries

**Generic defect:** An identifier — content type, route key, registry/handler
key, enum-as-string, DB discriminator, feature flag name — is defined or derived
in more than one place with **different casing/separator conventions**
(`snake_case` vs `kebab-case` vs `camelCase`) or spelling. Lookups then fail at
runtime ("no configuration/handler for X", 404/500). Type-checkers miss it
because the key is an unconstrained `string`.

**Detection heuristic:** Find string-keyed registry/dispatch/lookup maps and the
sites that build the key. Flag where the key is produced under one convention
(e.g. a route segment) but resolved against keys registered under another. Flag
the same conceptual key duplicated as string literals across files instead of a
shared constant/enum. Recommend a single source of truth + an exhaustive-
registration assertion (every variant registers, or a typed union).

**Why it recurs:** routes, registries, and configs are authored by different code
in different files; nothing forces the keys to agree, so a `_` vs `-` slips
through review and only breaks in prod for that one content type.

**Seen in the wild:** a route path (`some_action`) vs a registry/lookup key
(`some-action`) — a `_` vs `-` (or camelCase vs kebab) mismatch; a handler
registered under a name the dispatcher never calls; an enum/string key on the
producer side that disagrees with the consumer — only 500s in prod for that one
type because nothing forces the two sides to agree.

---

## P3 — Privileged-audience data leak on output paths (broken field/object-level authorization)

**Generic defect:** Data attributed to a privileged audience — GM-only, secret,
hidden, admin, internal, draft, unpublished — leaks into a lower-privilege output
(player view, public/shared export, API response, logs, PDF) because the
audience/visibility filter is not applied on **every** serialization/output path.

**Detection heuristic:** Identify data carrying a visibility/audience attribute
(`isSecret`, `isRevealed`, `audience`, `gmOnly`, `internal`, `role`, `published`).
Enumerate the output/serialize/export/response/log paths. Flag any path that emits
such data without applying the filter. Cross-check that sibling output paths apply
the *same* gate — the bug is usually one path forgetting what its siblings do.

**Why it recurs:** a new export/render/response path is added and reimplements
serialization without re-applying the visibility gate the original path had.

**Seen in the wild:** a secondary export (PDF/CSV) or API response leaks
admin-only / hidden / unpublished fields that the primary UI view filters out; a
newly added serializer emits records carrying `internal`/`gmOnly`/`draft` flags
because it didn't re-apply the visibility gate its sibling path already has.

---

## P4 — Subprocess & argument-injection hygiene (tool-wrapping code)

**Generic defect:** Code that shells out to external CLIs (`gh`, `git`, `yq`,
`docker`, package managers) lets untrusted-ish values — derived from filenames,
branch names, track/slug names, user-supplied paths — reach argv or an expression
without the guards that make subprocess use safe.

**Invariants to check:**
1. **End-of-options separator.** Put `--` before positional args so a value
   beginning with `-`/`--` (e.g. a file named `--repo.md`, a branch `--upload-pack=…`)
   can't be parsed as a flag. This is *option injection*, distinct from shell injection.
2. **List-argv, never `shell=True`** / string concatenation into a command line.
3. **Timeouts on every external call.** A hung `gh`/`git` (network stall) with no
   `timeout=` blocks forever; worse inside a thread pool. Every callsite needs a ceiling.
4. **Path containment.** Resolve user paths and assert they stay within an intended
   root; refuse symlink-following writes that escape it.
5. **Expression-injection guards.** Values interpolated into `yq`/`jq`/template
   expressions need `strenv()`/parameterization, not string building.

**Detection heuristic:** Find every `subprocess`/`spawn`/`exec` callsite and every
external-CLI invocation. Flag: positionals without a preceding `--`; missing
`timeout`; user/derived paths written without a containment check; values
interpolated into `yq -e`/`jq`/templates.

**Why it recurs:** the safe pattern is established once; each new callsite or each
new source of a "name" (a new file-derived identifier) reintroduces one missing guard.

**Seen in the wild:** a user-controlled value (a name, a branch, a path) starting
with `-`/`--` is parsed as an option flag → arbitrary file overwrite; subprocess
calls with no timeout → indefinite hang; a command writing outside its intended
root; expression injection into a config-rewriting tool (e.g. `yq`/`jq`).

---

## P5 — Partial/failed fetch must not overwrite good state

**Generic defect:** A sync from a remote source (API, GraphQL, scrape) writes its
result into canonical/cached state **unconditionally** — so a *partial* or *failed*
fetch overwrites valid existing data with empty values, placeholders, or
`(not fetched)` sentinels.

**Invariants to check:**
1. **Gate the write on fetch success/completeness.** A failed or partial fetch
   leaves prior good data intact; it does not blank it.
2. **Distinguish "absent" from "not fetched."** A sentinel for "we didn't get this"
   must never be persisted as if it were the real value.
3. **Merge, don't replace,** when only a subset was fetched.

**Detection heuristic:** Find code that fetches-then-persists. Flag any path where
the persist runs regardless of fetch status, or writes a placeholder/empty over a
previously-populated field. Check the error/timeout branch specifically.

**Why it recurs:** the happy path (full fetch → write) is written first; the
partial/error path is added later and reuses the same unconditional write.

**Seen in the wild:** a partial/failed remote fetch overwrites valid cached data with
a placeholder/empty value; records never surface because incomplete state was written
over the good state instead of being merged or skipped.

---

## P6 — Paginated-API default-limit & N+1 correctness

**Generic defect:** Code consuming a paginated API either (a) trusts the client's
**silent default page cap** — so it processes only the first page and treats it as
the whole set, or (b) makes an **N+1** call per item instead of batching.

**Invariants to check:**
1. **Never trust a default limit.** Pass an explicit high limit or paginate to
   exhaustion; a silent cap (e.g. `gh` defaults to 30) makes "all" mean "first 30."
2. **Batch, don't N+1.** Fetch sets in one batched/GraphQL call rather than one
   request per item — both for speed and to avoid rate limits.
3. **Say what was capped.** If a bound is applied, surface it; never imply
   completeness over a truncated set.

**Detection heuristic:** Find API-list/search callsites. Flag missing explicit
limit/pagination on calls that feed "all X" logic; flag per-item fetch loops that
could be one batched call.

**Why it recurs:** the default "just works" on small data in dev and silently
truncates / slows in production at scale.

**Seen in the wild:** an export/refresh that issues one API call per item (N+1) and
crawls at scale; a list/search API silently applying a default page cap (often 30) so
a repo/dataset with hundreds of items appears to have only the first page.

---

## P7 — Mock-only tests hide live integration/schema bugs

**Generic defect:** Code with a real external contract — a SQL schema, an HTTP API
shape, a file format, a middleware attribute — is tested *only* against mocks. The
mock encodes the developer's assumed contract, so the test passes green while the
real dependency rejects the call. CI is green; the first real request 500s.

**Invariants to check:**
1. **At least one real-contract test.** Anything touching a DB/external API has a
   test that runs against the real schema (or a schema-validated fake), not only a
   hand-written mock.
2. **The mock must match reality.** If mocks are used, something pins them to the
   actual schema/contract (generated types, a contract test, a migration check).

**Detection heuristic:** Find modules that touch a database/external API. Check
whether *every* test for them mocks that dependency. Flag modules with zero
integration/contract coverage — especially raw-SQL query builders and middleware
on the request hot path (a bug there 500s every request).

**Why it recurs:** mocks are faster to write and keep unit tests hermetic; the
real-contract test is "added later" and never is, so schema drift goes unseen.

**Seen in the wild:** an endpoint 500s on every *real* call because of a SQL bug the
mocks never exercised ("live SQL bug behind mock-only tests"); a route 500s on a fresh
install because a migration/schema step is missing; a middleware throws on every API
request because of a contract change the unit tests stubbed past.

---

## P8 — Silent data-loss / incomplete mapping in ETL

**Generic defect:** A transform/ingest step reads a source record and persists only
a subset of its fields, silently dropping the rest — no error, no warning. The loss
is invisible until someone queries the missing data downstream.

**Invariants to check:**
1. **Account for every source field.** Fields read from the source but never
   written to the destination are detected (schema diff, completeness assertion),
   not silently dropped.
2. **Completeness is observable.** Post-ingest, populated-row counts per column are
   checked; a column that is NULL across the whole corpus is an alarm, not normal.
3. **Safe-by-default on regression** (see also P5): a parser regression or partial
   parse must not overwrite populated destination data with empty/NULL via upsert.

**Detection heuristic:** Find parse/transform → persist mappings. Flag source keys
that are read (or present in the source schema) but never written. Flag upserts
that unconditionally set columns derivable from a fragile parse.

**Why it recurs:** the mapping is written against a few sample records; fields
absent from the samples (or added later to the source) are never wired through.

**Seen in the wild:** a bulk ingest silently drops several source fields (they end up
NULL across the entire table); a scheduled upsert wipes destination data when the
parser regresses and emits empty/partial records over the good ones.

---

## P9 — DB schema/type-contract drift in raw SQL

**Generic defect:** Raw SQL built as strings assumes a schema the database doesn't
actually have — a column name that doesn't exist or is aliased differently, a value
written into an incompatible column type, a table/column missing on a fresh
install. The compiler/type-checker can't see inside the SQL string, so it ships.

**Invariants to check:**
1. **Column references resolve.** Names used in `ORDER BY`/`WHERE`/`JOIN` (and CTE
   chains) match the columns actually projected upstream — watch alias drift across
   CTEs.
2. **Types match.** Values bound/inserted match the destination column type (no
   string into a `bigint`, no implicit-cast-that-aborts).
3. **Schema exists where assumed.** Migrations create every table/column the code
   queries, including on a fresh install.

**Detection heuristic:** Find raw-SQL strings and ORM raw writes. Cross-check column
names against the schema/migrations; flag unqualified or re-aliased columns in
multi-CTE queries; flag inserts whose value type can mismatch the column. Pairs
with P7 — these are exactly what mock-only tests miss.

**Why it recurs:** SQL lives in strings outside the type system; a refactor renames
or re-aliases a column in one CTE and the downstream reference rots silently.

**Seen in the wild:** `column "x" does not exist` from an unqualified reference vs an
aliased column in a CTE; a string value inserted into an integer column → every insert
aborts; a query referencing a column a migration renamed or dropped.

---

## P10 — Missing / weak security response headers (CSP & friends)

**Generic defect:** A web app ships responses without the baseline security
headers, or with a Content-Security-Policy weak enough to neuter its own
protection. This is a defense-in-depth backstop for XSS (cat#3) and clickjacking;
it's also a common compliance/baseline gap rather than a flashy bug, so it gets
skipped.

**Invariants to check:**
1. **The baseline headers are set** on app responses: `Content-Security-Policy`,
   `Strict-Transport-Security`, `X-Frame-Options` (or CSP `frame-ancestors`),
   `X-Content-Type-Options: nosniff`.
2. **CSP isn't self-defeating** — flag `unsafe-inline` / `unsafe-eval`, wildcard
   `*` sources, and a missing/over-broad `default-src`. Prefer nonce/hash over
   `unsafe-inline`.
3. **Applied everywhere** — headers set in one place (a route, one middleware
   branch) but not on all responses is the P3/P5 "one path forgets" shape. Check
   error responses and statically-served paths too.

**Detection heuristic:** Find where response headers are configured — Next.js
`headers()` in `next.config.*` or middleware, Express `helmet()`, FastAPI/Starlette
middleware, Django `SECURE_*` settings / `SecurityMiddleware`, nginx/CDN config.
Flag any baseline header absent, any weak CSP directive, and CSP defined on a
subset of routes. `semgrep` (`p/owasp-top-ten`) confirms several of these — treat
those as High (tool-confirmed); reasoning-only header-absence is Medium.

**Why it recurs:** headers are infra-adjacent and invisible in normal use — the
app works fine without them, so they're easy to omit or weaken (`unsafe-inline`
"just to ship") and nothing fails a test.

**Seen in the wild:** the security baseline most web apps are measured against
(OWASP secure-headers). Surfaced as "CSP nits" in webview/SSR hardening, where a
strict CSP with a per-load nonce (no `unsafe-inline`) is the correct bar.

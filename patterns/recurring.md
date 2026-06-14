# Recurring Defect Patterns (battle-tested)

Higher-order, cross-cutting patterns distilled from real production incidents.
The reasoning pass (SKILL.md Stage 3) consults these in addition to the five
`baseline-categories.md` and the active profile's checklist. Each pattern is
language-agnostic; the examples show how it tends to manifest.

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

**Manifested as (CritForge):** charge on sanitization-blocked input; no refund on
async early-return; double-charge + charge-on-rejected-request; charge-before-
validation; "button no-ops — no result, no error, credits not deducted."

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

**Manifested as (CritForge):** `random_table` route vs `random-table` registry;
`skill_challenge` "No pipeline configuration"; `legendary_hero` vs
`legendary-hero` 500s in prod; validator registration mismatch; handler/intent
type mismatch.

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

**Manifested as (CritForge):** player map/PDF exports leak secret rooms, hidden
traps, and element names/positions; `pass2-player.json` leaks GM-secret NPC
fields; map legend leaks secret-room contents — reachability/audience gate applied
on one path but not its sibling.

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

**Manifested as (work-plan-toolkit):** option injection via `--`-prefixed track
names and dash-led branch names → arbitrary file overwrite; 33/37 subprocess
callsites with no timeout → indefinite hang; `init` clobbers files outside
`notes_root`; yq expression injection rewriting `config.yml`.

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

**Manifested as (work-plan-toolkit):** partial GitHub fetches overwrite valid
canonical-table data with `(not fetched)`; untracked issues never surface for a
registered repo because of incomplete state.

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

**Manifested as:** work-plan-toolkit export/refresh slow at scale via per-issue
`gh` fetches (#94, #106); and — first-hand — `gh issue list` silently capping at
30 made a 720-open-issue repo look like it had 30 (caught while building this skill).

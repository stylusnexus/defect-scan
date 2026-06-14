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

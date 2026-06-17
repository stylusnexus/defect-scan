# Supply-Chain Defect Pattern Pack (npm-first) — Design Spec

**Date:** 2026-06-17
**Issue:** stylusnexus/defect-scan#66
**Status:** Approved (brainstorming) → ready for plan

---

## Plain-English summary

npm keeps getting hit by attacks where a package runs malicious code the moment you
install it (a `postinstall` worm, install-time credential theft), or where you're
tricked into installing a fake package whose name is a near-miss of a real one
(typosquatting), or an internal-looking name that secretly resolves to the public
registry (dependency confusion). The usual tools (`npm audit`, `osv-scanner`) miss
these because they only know about *already-reported* bad packages — not a brand-new
malicious one. The malicious package *is* the payload, so there's no published CVE yet.

This work teaches defect-scan to look at the project's own dependency files
(`package.json`, the lock file, `.npmrc`) and flag the *shape* of these attacks. As
everywhere in this tool, the deterministic shell layer does the mechanical part —
locate the manifests and pull out the relevant slices — and the model does the
judgement — is this lifecycle script malicious? does this dependency name look like a
typo of a popular package? We add a new defect **category** for supply-chain /
dependency-integrity (every major security framework treats this as its own class,
distinct from injection), a new **pattern pack** describing the four detections, a
deterministic **manifest hook**, a labeled **eval corpus** so the pattern is measured
not vibed, updates to **both harness drivers** (Claude + Codex), and **all the docs**
that currently say "five categories."

Honest caveats: this is **offline** — no live registry/integrity verification and the
scanner never executes manifest content (running it would be the very install-RCE we
flag). Typosquat and dependency-confusion are inherently lower-precision (model
judgement, tunable by a project allowlist), so they ship at lower confidence tiers. It
**complements** the existing react-typescript `npm audit`/`osv-scanner` known-vuln
coverage; it does not replace it.

---

## Goals & non-goals

**Goals**
- Detect, from the dependency manifest/lockfile alone, four npm supply-chain defect
  classes: (1) malicious lifecycle scripts, (2) typosquatting, (3) dependency
  confusion, (4) install-time credential/env exfil.
- Keep the deterministic/reasoning split: `detect.sh` locates + slices; the model reasons.
- Gate the pattern with a labeled, model-free eval corpus and a committed baseline.
- Keep both harnesses (Claude `SKILL.md`, Codex `codex/defect-scan.md` + `AGENTS.md`) in lockstep.
- Update every doc that enumerates categories/patterns.

**Non-goals**
- **No network.** No live registry lookups, no integrity verification against npm, no
  fetching popular-package lists at runtime.
- **No manifest execution.** Never run `npm install`/lifecycle scripts; only read.
- **npm-first only.** PyPI / crates.io / RubyGems are explicitly future work; the hook
  is *designed* to extend but v1 implements npm.
- **No runtime learning store** (carried from #15). Typosquat uses the model's own
  knowledge as the corpus, not a baked-in or fetched list.

---

## Design decisions (with rationale)

### D1 — Scope: all four detections in v1
Lifecycle abuse, lockfile tampering, and install-exfil are decidable from the
manifest/lockfile in front of the scanner (high signal). Typosquat and
dependency-confusion need knowledge of "popular package names" and "which scopes are
internal" — which we get from **the model's reasoning** (its training-time knowledge of
the npm ecosystem) plus an optional **project-layer allowlist**, *not* a baked-in
dataset. They ship at **Low/Medium** confidence with mandatory adversarial verification.

### D2 — New category `cat#6` "Supply-chain / dependency integrity" (High)
Settled after a security-analyst review against standard taxonomies. Supply-chain
compromise is universally treated as its **own class**, orthogonal to injection:
OWASP A08 (Software & Data Integrity Failures, separate from A03 Injection), CWE-1357 /
CWE-829 / CWE-494 (integrity pillar, not CWE-77/78/89), SLSA (its entire threat model),
MITRE ATT&CK **T1195**. The decisive point for *this* codebase: the eval grader is
**model-free and trusts the labels**, so mislabeling an identity-confusion defect (no
interpreter, no sanitization step) as `cat#3` injection is a mislabel the grader cannot
catch — it poisons the "data reaches an interpreter" signal that makes `cat#3` gradable.

> **Spec one-liner:** Supply-chain compromise is an integrity/provenance class (OWASP
> A08, CWE-1357/829, SLSA, MITRE T1195), not an injection variant — the trust boundary
> is violated, not an interpreter; `cat#6` keeps the four detections coherent and avoids
> mislabeling identity-confusion defects as `cat#3`.

Rejected: reuse `cat#3` (taxonomically wrong, poisons grader); hybrid cat#3+cat#6
(splits one coherent class on a seam no framework draws → labeler/model disagreement).

### D3 — Detection mechanism: a deterministic `detect.sh manifest` hook
Triage keeps only source extensions (`react-typescript` = `ts tsx`), so `package.json`
and lock files never reach the reasoning pass today, and lock files are too large to
dump wholesale. A new subcommand **locates + slices** the manifest data and feeds only
the relevant parts to the reasoning pass. Rejected: forcing manifests into triage
(dumps huge lockfiles, muddies the source-file model); profile-checklist-only (lockfiles
unreachable, welds supply-chain to the JS profile, won't generalize).

### D4 — Structure: new built-in `patterns/supply-chain.md` with new P-numbers
Matches the issue's "new P-numbered cross-cutting class," keeps the class coherent and
extensible to other ecosystems, and doesn't bloat `recurring.md`. Rejected: P-slots in
`recurring.md` (bloats the "language-agnostic" pack with ecosystem-specific detection);
extending P4 (the analyst's taxonomy rules out folding integrity into injection, and the
detection surface — manifest vs app code — is different).

---

## Components

### C1 — `cat#6` in the category registry
- **`skills/scan/baseline-categories.md`** — add `## 6. Supply-chain / dependency integrity · default severity: High` with the D2 one-liner and the four sub-classes described.
- **`detect.sh` `cmd_eval_categories`** — the hardcoded `printf 'cat#1\n…cat#5\n'` → include `cat#6`.
- **Runner legend** — *no code change*: the awk in `claude.sh`/`codex.sh` builds the legend from `## N.` headers, so `## 6.` is picked up automatically. (Verify in a test.)
- **`detect.sh` usage string** — unchanged (no new top-level verb here).

### C2 — `detect.sh manifest <repo>` (new subcommand, deterministic, read-only)
Emits, when an npm ecosystem is detected (`package.json` present), a structured,
**sliced** view for the reasoning pass:
- **lifecycle scripts** — the `scripts` entries `preinstall`/`install`/`postinstall`/`prepare`/`prepublish`(`Only`) from `package.json`.
- **dependency name list** — keys of `dependencies` + `devDependencies` + `optionalDependencies` (for typosquat/confusion reasoning).
- **lockfile entries** — per-package `resolved` URL + `integrity` from `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` (a relevant subset, never the whole file).
- **registry config** — `.npmrc` `registry=` and `@scope:registry=` lines.

**JSON parsing decision:** prefer **`jq`** (already an optional dependency — used in
`cmd_issues`, listed optional in `cmd_preflight`); fall back to a constrained `awk`/`grep`
extraction of the `scripts` block + dependency keys when `jq` is absent. If neither path
can parse a manifest, emit the file **path** and mark the manifest pass **inconclusive**
(never silently "clean") — consistent with the tool's graceful-degradation rule. Resolve
`jq` via the existing tool-lookup, never execute manifest content.

**Security:** read-only; never runs `npm`, scripts, or any manifest-derived string. A
scanned repo's manifest is untrusted input (this is literally the P4 RCE class), so the
hook only reads and slices text.

### C3 — `patterns/supply-chain.md` (new built-in pattern pack)
New P-numbers, each mapping to `cat#6`, npm-first examples, default severity, confidence
guidance, and adversarial-verification notes:
- **P11 — Malicious lifecycle script** (High confidence; pattern-matchable: network/`exec`/`child_process`/obfuscation/`curl|sh` in `pre/postinstall`/`prepare`).
- **P12 — Typosquat / dependency confusion** (Low–Medium; model-reasoned). Typosquat = lookalike of a popular name; dependency confusion = internal-looking scope resolving to the public registry. Tunable by a **project-layer internal-scope allowlist** (see C4).
- **P13 — Lockfile tampering** (Medium; heuristic over surfaced entries: `resolved` host that isn't the configured registry, missing/malformed `integrity`, a version's resolution inconsistent with the manifest range).
- **P14 — Install-time credential/env exfil** (High; reads `process.env`/tokens/`~/.npmrc`/`~/.aws` and ships them to the network during install).

**`cmd_patterns` wiring:** change the hardcoded single `recurring.md` echo to **glob
built-in `patterns/*.md`** (with `recurring.md` first for stable ordering), so this pack
and any future built-in pack are auto-consulted. Update the bats assertion accordingly.

### C4 — Project-layer config: internal-scope allowlist
A consumer repo declares its internal scopes/registries (e.g. in
`.defect-scan/supply-chain.conf` or a documented key) so dependency-confusion findings
on *legitimately* internal scopes are suppressed and precision rises. Built-in default:
none (every `@scope` resolving to the public registry that *looks* internal is a
Low-confidence finding the model flags for human confirmation). Honors the existing
layering model; the allowlist is read, never executed.

### C5 — Both harness drivers (divergence between harnesses is a bug)
- **`skills/scan/SKILL.md`** — when an npm ecosystem is detected, run `detect.sh manifest`
  and feed its slices into the Stage-3 reasoning pass; document `cat#6`; the pattern is
  auto-consulted via `cmd_patterns`.
- **`codex/defect-scan.md` + `AGENTS.md`** — mirror exactly.
- **`skills/scan/report-format.md`** — `cat#6` appears in the category grouping/reporting.

### C6 — Eval corpus (`tests/eval/supply-chain/`)
- **buggy fixtures:** `package.json` with a malicious `postinstall`; a dependency-confusion manifest; a tampered lockfile entry; an install-exfil snippet — each labeled `cat#6` in its `.expected` sidecar.
- **clean near-misses:** a legitimate `postinstall` build step; a correctly-resolved scoped internal package; a normal lockfile — empty `.expected` (the false-positive tripwire).
- baseline calibrated via `eval-run` → committed through a **CODEOWNERS** PR (the corpus + grader are protected).

**Eval `--lang` decoupling (the one mechanism wrinkle):** `eval-run <lang>` uses `<lang>`
as both the corpus dir and the `--lang` passed to the scan, but `supply-chain` is a
*pattern*, not a profile, so `--lang supply-chain` has no profile to load. `eval-categories`
already only needs the corpus dir to exist (no profile), so it works as-is. Resolution:
add an optional **scan-profile override** for a corpus — an `eval-run --as <profile>` flag
(or a `tests/eval/<corpus>/.scan-profile` sidecar), defaulting to the corpus name to
preserve current behavior. The supply-chain corpus sets it to **`react-typescript`** so the
npm ecosystem is detected and the manifest hook fires, while the corpus dir / labels stay
under `supply-chain`. The implementation plan validates this end-to-end before relying on it.

### C7 — Docs (first-class deliverable)
- **`README.md`** — "five baseline categories" → six; add the supply-chain pack to the capabilities list.
- **`tests/eval/README.md`** — category list + the new `supply-chain` corpus (data-flow diagram already corrected in #77).
- **`commands/help.md`** — category count; correct the stale "9 battle-tested patterns" (already 10 in `recurring.md`) and reflect the new pack; mention supply-chain detection.
- **`EXTENDING.md` / `CONTRIBUTING.md`** — use `supply-chain.md` as the worked example of a built-in pattern pack; document the internal-scope allowlist as a project-layer extension point.
- **`CLAUDE.md`** — architecture note: six categories; the `manifest` hook; the supply-chain pack.

---

## Testing & gates

- **bats (`tests/detect.bats`):**
  - category enumeration is `cat#1..6` (and `eval-categories` reflects it);
  - `cmd_patterns` lists `supply-chain.md` (built-in) alongside `recurring.md`;
  - `detect.sh manifest` emits the expected slices on a fixture repo (lifecycle scripts, dep list, lockfile entries, `.npmrc`), and degrades gracefully (path + inconclusive) when `jq` is forced absent;
  - the new pattern pack declares its required sections / valid shape (mirror the profile-invariant tests);
  - usage string lists `manifest` if it becomes a documented verb.
- **eval:** the `supply-chain` corpus scores against its committed baseline; clean fixtures produce zero findings (FP tripwire).
- **CI:** green on **ubuntu + macos** (POSIX, BSD-vs-GNU awk); `sh -n` clean; gitleaks clean.
- **Cross-harness:** a test (or reviewer checklist) that the Codex driver references the manifest hook + `cat#6` the same way Claude's does.

---

## Files touched (anticipated)

**New**
- `skills/scan/patterns/supply-chain.md`
- `tests/eval/supply-chain/{seen,…}/…` fixtures + `.expected` + `baseline.seen.txt`

**Modified**
- `skills/scan/lib/detect.sh` — new `cmd_manifest`; `cmd_eval_categories` (`cat#6`); `cmd_patterns` (glob built-ins); `eval-run` `--as`/scan-profile override; usage string.
- `skills/scan/baseline-categories.md` — `cat#6`.
- `skills/scan/SKILL.md`, `codex/defect-scan.md`, `AGENTS.md` — wire the hook + `cat#6`.
- `skills/scan/report-format.md` — `cat#6`.
- `tests/eval/runners/{claude,codex}.sh` — only if the `--as`/scan-profile override touches them.
- `tests/detect.bats` — new assertions above.
- `README.md`, `tests/eval/README.md`, `commands/help.md`, `EXTENDING.md`, `CONTRIBUTING.md`, `CLAUDE.md` — docs.
- `.github/CODEOWNERS` — confirm the new corpus path is covered.

---

## Phasing (for the implementation plan)

1. **Category** — `cat#6` in `baseline-categories.md` + `eval-categories` + bats; legend auto-picks it up.
2. **Hook** — `detect.sh manifest` (jq-preferred, awk fallback, graceful degrade) + bats on a fixture.
3. **Pattern** — `patterns/supply-chain.md` (P11–P14) + `cmd_patterns` glob + bats.
4. **Drivers** — wire `SKILL.md` and Codex; `report-format.md`.
5. **Eval** — corpus + `--as` decoupling + baseline (CODEOWNERS PR).
6. **Docs** — READMEs, help, EXTENDING/CONTRIBUTING, CLAUDE.md.

Each phase is a commit/checkpoint; phases 1–4 are shippable behind the pattern even before
the corpus baseline lands, but the eval gate (phase 5) is required before declaring #66 done.

---

## Open questions (resolve during planning, not blockers)

- **`manifest` as a public verb vs internal helper** — does SKILL.md call it directly, or
  is it folded into `scope`/`triage` output? Leaning: a distinct, separately-testable verb.
- **Exact project-allowlist file shape** (`.defect-scan/supply-chain.conf` vs a key in an
  existing project config) — pick the lowest-friction form consistent with EXTENDING.md.
- **`--as` flag vs `.scan-profile` sidecar** for the eval corpus profile override — pick
  one in planning; both are small and backward-compatible.

## References
- Issue #66; P4 (install-RCE) in `patterns/recurring.md`; #15 eval harness; #71/#72 (runner determinism).
- OWASP Top 10 A06/A08; CWE-1357/829/494; SLSA dependency-threat model; MITRE ATT&CK T1195; CAPEC-538.

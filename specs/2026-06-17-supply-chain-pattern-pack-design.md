# Supply-Chain Defect Pattern Pack (npm-first) — Design Spec

**Date:** 2026-06-17
**Issue:** stylusnexus/defect-scan#66
**Status:** Approved (brainstorming) → revised after Codex spec-review (DO NOT SHIP → addressed) → ready for plan

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
(`package.json`, the lock file, `.npmrc`) — and, when a lifecycle script points at a
local script in the repo, that script too — and flag the *shape* of these attacks. As
everywhere in this tool, the deterministic shell layer does the mechanical part (locate
the manifests, pull out the relevant slices, resolve a referenced local install script)
and the model does the judgement (is this script malicious? does this name look like a
typo of a popular package?). We add a new defect **category** for supply-chain /
dependency integrity, a new **pattern pack**, a deterministic **manifest hook** (with a
bounded local-script resolver), a **multi-file eval corpus** (which requires a small,
backward-compatible extension to the eval harness so a fixture can be a mini-repo, not
just one file), updates to **both harness drivers** (Claude + Codex), and **all the docs**
that currently say "five categories."

Honest caveats: this is **offline** — no live registry/integrity verification, and the
scanner never executes manifest or script content (running it would be the very
install-RCE we flag). The local-script resolver reads only repo-local, size-bounded,
non-recursive references; payloads in a *remote* or *transitively-fetched* script are out
of scope. Typosquat and dependency-confusion are inherently lower-precision (model
judgement, tunable by a project allowlist) and ship at lower confidence tiers. It
**complements** the existing react-typescript `npm audit`/`osv-scanner` known-vuln
coverage; it does not replace it — and those known-vuln findings now share the new
`cat#6` category.

---

## Goals & non-goals

**Goals**
- Detect four npm supply-chain defect classes: (1) malicious lifecycle scripts,
  (2) typosquatting, (3) dependency confusion, (4) install-time credential/env exfil —
  from `package.json` + lockfile + `.npmrc`, **plus referenced local install scripts**
  (bounded; see C2.1).
- Keep the deterministic/reasoning split: `detect.sh` locates + slices + resolves; the model reasons.
- Gate the pattern with a labeled, model-free eval corpus + committed baseline.
- Extend the eval harness to support **multi-file fixture repos**, backward-compatibly.
- Keep both harnesses (Claude `SKILL.md`, Codex driver + `AGENTS.md`) in lockstep.
- Make `cat#6` the category home for **all** supply-chain findings — the new reasoned
  ones (A08) *and* the existing `npm audit`/`osv-scanner` known-vuln ones (A06).
- Update every doc that enumerates categories/patterns.

**Non-goals**
- **No network.** No live registry lookups, integrity verification, or popular-package fetches.
- **No execution.** Never run `npm`/lifecycle scripts/resolved scripts; only read.
- **No remote/transitive script resolution.** The resolver follows one level of
  *repo-local* references only (see C2.1); it does not fetch or recurse.
- **#66 does not build CVE/known-vuln detection** — that already exists (`npm audit`/
  `osv-scanner`); #66 only adds the `cat#6` *category tag* for those findings.
- **npm-first only.** PyPI / crates.io / RubyGems are future; the hook is designed to extend.
- **No runtime learning store** (from #15). Typosquat uses the model's knowledge, not a baked-in list (see #78 for the separate "curated corpus?" exploration).
- **Semver-range consistency** (a lockfile version outside the manifest range) is left to
  **model-only** reasoning in v1, not deterministic checking.

---

## Design decisions (with rationale)

### D1 — Scope: all four detections in v1
High-signal manifest-local detections (lifecycle abuse, lockfile tampering, install-exfil)
plus the two judgement detections (typosquat, dependency-confusion) as model reasoning +
optional project allowlist, at Low/Medium confidence with mandatory adversarial verification.

### D2 — New category `cat#6` "Supply-chain / dependency integrity" (High)
Settled via security-analyst review against standard taxonomies (OWASP A06+A08, CWE-1357/
829/494, SLSA, MITRE T1195). Supply-chain compromise is its own class, orthogonal to
injection. Decisive for *this* codebase: the eval grader is **model-free and trusts the
labels**, so labeling an identity-confusion defect (no interpreter) as `cat#3` is a mislabel
the grader can't catch and which poisons the `cat#3` signal.

> **Spec one-liner:** Supply-chain compromise is an integrity/provenance class (OWASP A06/
> A08, CWE-1357/829, SLSA, MITRE T1195), not an injection variant — the trust boundary is
> violated, not an interpreter; `cat#6` keeps the detections coherent and avoids mislabeling.

`cat#6` covers both sub-axes: **A06** known-vulnerable/outdated components (detected by the
existing tool pass) and **A08** integrity failures (the new reasoned detections). Rejected:
reuse `cat#3` (taxonomically wrong, poisons grader); hybrid cat#3+cat#6 (splits one class).

### D3 — Detection mechanism: a deterministic, **documented** `detect.sh manifest` verb
A new top-level subcommand (listed in usage + asserted by bats — resolving the spec-review
inconsistency) that locates + slices manifest data and resolves bounded local scripts, so it
reaches the reasoning pass. Rejected: forcing manifests into triage (dumps huge lockfiles);
profile-only (lockfiles unreachable, welds to JS profile).

### D4 — Structure: new built-in `patterns/supply-chain.md`, new P-numbers (P11–P14)
Matches the issue, keeps the class coherent and ecosystem-extensible, doesn't bloat
`recurring.md`. `cmd_patterns` changes to glob built-in `patterns/*.md` (recurring.md first).

### D5 — Eval fixtures are **multi-file repos**; the harness gets a backward-compatible extension
(Codex HIGH-2/HIGH-1.) The current harness is single-file-per-fixture (`eval-run` loops files,
runners copy one file, grader keys by basename). Supply-chain cases need `package.json` +
lockfile + `.npmrc` together. We extend the harness so a fixture may be a **directory** (a
mini-repo) — **additively**: existing single-file corpora are unchanged. See C6.

### D6 — Detection reach includes **referenced local install scripts** (bounded)
(Codex HIGH-3.) `postinstall: node scripts/install.js` hides the payload in a file. The
manifest hook resolves one level of repo-local script references, size/path-bounded,
read-only, never executed (C2.1). Remote/transitive references are out of scope and the
"manifest alone" wording in Goals is corrected accordingly.

---

## Components

### C1 — `cat#6` in the category registry
- **`baseline-categories.md`** — add `## 6. Supply-chain / dependency integrity · default severity: High` with the D2 one-liner; describe both A06 (known-vuln) and A08 (the four detections) sub-axes.
- **`detect.sh` `cmd_eval_categories`** — the hardcoded `cat#1..cat#5` printf → include `cat#6`.
- **Runner legend** — no code change (awk builds it from `## N.` headers; verified `## 6.` is picked up). Cover with a test.
- **Tool-pass tagging** — `SKILL.md` + `report-format.md` tag existing `npm audit`/`osv-scanner` known-vuln findings as `cat#6` (A06). This is a *categorization* change, not new detection.

### C2 — `detect.sh manifest <repo>` (new documented subcommand; deterministic, read-only)
Emits a structured, **sliced** view when an npm ecosystem is detected (`package.json` present):
- **lifecycle scripts** — `scripts` entries `preinstall`/`install`/`postinstall`/`prepare`/`prepublishOnly`.
- **dependency name list** — keys of `dependencies` + `devDependencies` + `optionalDependencies`.
- **lockfile entries** — per-package `resolved` URL + `integrity` from `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` (relevant subset, never the whole file).
- **registry config** — `.npmrc` `registry=` and `@scope:registry=` lines.
- **resolved local scripts** — see C2.1.

**JSON parsing:** prefer **`jq`** (already an optional dependency — used in `cmd_issues`,
listed optional in `cmd_preflight`); fall back to constrained `awk`/`grep` for the `scripts`
block + dependency keys. If neither can parse a manifest, emit the file **path** and mark the
manifest pass **inconclusive** (never silently "clean"). Resolve `jq` via the existing tool
lookup. **Add it to the `detect.sh` usage string and assert it in bats.**

**Security:** read-only; never executes `npm`, scripts, or any manifest-derived string. The
scanned repo's manifest is untrusted input (literally the P4 RCE class) — read + slice only.

#### C2.1 — Bounded local-script resolver
When a lifecycle command references a local script (`node scripts/x.js`, `sh ./setup.sh`,
`./bin/postinstall`), surface that file's content alongside the inline command, bounded by:
- **repo-local relative paths only** — reject absolute paths, `..` traversal outside the repo, and anything under `node_modules/`;
- **size cap** — first N KB / N lines (exact value pinned in the plan; emit a truncation marker);
- **depth 1** — do not recurse into scripts that the resolved script itself invokes;
- **read-only, never executed.** If a reference can't be safely resolved, surface the inline command only + a note. The model reasons over the inline command + any resolved script.

### C3 — `patterns/supply-chain.md` (new built-in pattern pack)
New P-numbers, each mapping to `cat#6`, npm-first examples, default severity, confidence
guidance, adversarial-verification notes:
- **P11 — Malicious lifecycle script** (High; pattern-matchable: network/`exec`/`child_process`/obfuscation/`curl|sh` in a lifecycle command **or its resolved local script** per C2.1).
- **P12 — Typosquat / dependency confusion** (Low–Medium; model-reasoned). Tunable by the C4 allowlist.
- **P13 — Lockfile tampering** (Medium; **deterministic-detectable cases**: `resolved` host that isn't the configured/default registry, **absent** `integrity`, **malformed** `integrity`. Semver-range inconsistency is **model-only**, per non-goals).
- **P14 — Install-time credential/env exfil** (High; reads `process.env`/tokens/`~/.npmrc`/`~/.aws` and ships them out during install — visible in the inline command **or the resolved local script**).

**`cmd_patterns` wiring:** glob built-in `patterns/*.md` (recurring.md first); update bats.

### C4 — Project-layer config: internal-scope allowlist (fully specified)
(Codex MEDIUM-4 — no existing generic config layer, so define it precisely.)
- **File:** `<repo>/.defect-scan/supply-chain.conf` (project layer) and `~/.config/defect-scan/supply-chain.conf` (user layer); project shadows user.
- **Syntax:** one directive per line, `#` comments allowed; v1 keys: `internal_scope=@acme` (repeatable) and `internal_registry=https://npm.acme.internal` (repeatable). Unknown keys ignored with a stderr note.
- **Consumed by:** a new `detect.sh` reader (mirroring `fm_get`/layer-walk style) that emits the resolved allowlist; the manifest hook annotates which `@scope`s are declared-internal so P12 suppresses dependency-confusion findings on them (or flags an internal scope resolving to the *public* registry as **higher** confidence).
- **Invalid file:** parse errors are a stderr warning + treated as empty (never abort the scan).
- **Tests:** bats coverage for project-layer present, user-layer fallback, absent (default empty), and malformed.

### C5 — Both harness drivers (divergence between harnesses is a bug)
- **`SKILL.md`** (Claude) — run `detect.sh manifest` when npm ecosystem detected; feed slices + resolved scripts into Stage 3; tag known-vuln tool findings `cat#6`; pattern auto-consulted via `cmd_patterns`.
- **`codex/defect-scan.md` + `AGENTS.md`** (Codex) — mirror exactly.
- **`report-format.md`** — `cat#6` grouping; known-vuln tool findings appear under it.

### C6 — Eval harness extension + corpus (multi-file)
**Harness change (shared; must stay backward-compatible — existing single-file corpora unchanged):**
- A fixture under `tests/eval/<corpus>/<split>/` may be a **file** (today) or a **directory** = a mini-repo.
- **Directory fixture contract:** case `foo/` is a directory; its sidecar is `foo.expected` (sibling, mirroring the `<file>.expected` convention). Runners copy the whole directory into temp and scan it as a repo (not one file). Findings are keyed by **path relative to the case root**; `.expected` lines become `<relpath>:<line>:<cat>`. The grader matches within a `(case, relpath, category)` bucket; single-file fixtures keep matching by basename.
- **Runner interface (Codex HIGH-1):** the runner is invoked with the fixture path, the **corpus label-set key**, and the **scan profile** as *separate* arguments — `runner <fixture> <corpus> <scan-profile>` — so `eval-categories <corpus>` supplies labels while the scan runs as `<scan-profile>`. `eval-run` gains `--as <profile>` (default: the corpus name, preserving current behavior). Both runners and `.github/workflows/eval-run.yml` updated; a test asserts `supply-chain` labels are used while the scan runs as `react-typescript`.

**Corpus (`tests/eval/supply-chain/`, scan-profile `react-typescript`):** each case is a mini-repo:
- **buggy:** malicious-`postinstall` (inline) repo; `postinstall`-references-local-script repo (exercises C2.1); dependency-confusion repo (`package.json` + `.npmrc`); tampered-lockfile repo (non-registry `resolved`; absent integrity; malformed integrity); install-exfil repo. Each labeled `cat#6`.
- **clean near-misses:** legitimate `postinstall` build step; correctly-resolved scoped internal package (+ allowlist); normal lockfile — empty `.expected` (FP tripwire).
- baseline calibrated via `eval-run --as react-typescript supply-chain` → committed via **CODEOWNERS** PR.

### C7 — Docs (first-class deliverable)
- **`README.md`** — five → six categories; add the supply-chain pack.
- **`tests/eval/README.md`** — category list; new `supply-chain` corpus; **document the multi-file fixture-repo format** (the harness change).
- **`commands/help.md`** — category count; correct the stale "9 battle-tested patterns" (→ now includes P11–P14); mention supply-chain.
- **`EXTENDING.md` / `CONTRIBUTING.md`** — `supply-chain.md` as the built-in pattern-pack example; document the `supply-chain.conf` allowlist as a project-layer extension point.
- **`CLAUDE.md`** — architecture: six categories; the `manifest` hook + resolver; multi-file eval fixtures.

---

## Testing & gates

- **bats (`tests/detect.bats`):**
  - category enumeration is `cat#1..6` (`eval-categories` reflects it; legend picks up `## 6.`);
  - `cmd_patterns` lists built-in `supply-chain.md` alongside `recurring.md`;
  - `detect.sh manifest` emits expected slices on a fixture repo; resolves a referenced local script within bounds; **refuses** absolute/`..`/`node_modules` paths; truncates over the size cap; degrades gracefully (path + inconclusive) when `jq` is forced absent; **`manifest` appears in the usage string**;
  - the allowlist reader: project/user/absent/malformed (C4);
  - lockfile deterministic cases: non-registry `resolved`, absent integrity, malformed integrity (P13);
  - **multi-file harness:** a directory fixture is scanned as a repo and graded by case-relative path, **and existing single-file corpora still grade by basename** (backward-compat);
  - new pattern pack declares required sections / valid shape.
- **eval:** the `supply-chain` corpus scores against its committed baseline; clean fixtures → zero findings.
- **CI:** green on **ubuntu + macos** (POSIX, BSD-vs-GNU awk); `sh -n` clean; gitleaks clean.
- **Cross-harness:** test/checklist that the Codex driver references the manifest hook + `cat#6` the same way Claude's does.

---

## Files touched (anticipated)

**New**
- `skills/scan/patterns/supply-chain.md`
- `tests/eval/supply-chain/seen/<case>/…` mini-repos + `<case>.expected` + `baseline.seen.txt`
- Possibly `skills/scan/lib/` reader for the allowlist (or a `cmd_` in detect.sh)

**Modified**
- `skills/scan/lib/detect.sh` — `cmd_manifest` (+ C2.1 resolver); allowlist reader; `cmd_eval_categories` (`cat#6`); `cmd_patterns` (glob built-ins); `cmd_eval_run` (directory fixtures, `--as`); grader path-keying (case-relative); usage string (`manifest`).
- `skills/scan/baseline-categories.md` — `cat#6`.
- `skills/scan/SKILL.md`, `codex/defect-scan.md`, `AGENTS.md` — wire hook + resolver + `cat#6` (incl. tool-pass tagging).
- `skills/scan/report-format.md` — `cat#6`.
- `tests/eval/runners/{claude,codex}.sh` — 3-arg interface (fixture, corpus, scan-profile); scan a directory fixture as a repo.
- `.github/workflows/eval-run.yml` — pass the scan-profile / `--as`.
- `tests/detect.bats` — all assertions above.
- `README.md`, `tests/eval/README.md`, `commands/help.md`, `EXTENDING.md`, `CONTRIBUTING.md`, `CLAUDE.md` — docs.
- `.github/CODEOWNERS` — confirm new corpus path covered (verified: `tests/eval/` already covered).

---

## Phasing (for the implementation plan)

1. **Category** — `cat#6` in `baseline-categories.md` + `eval-categories` + bats; tool-pass tagging in drivers/report-format.
2. **Manifest hook + resolver** — `cmd_manifest` (jq-preferred, awk fallback, graceful degrade) + bounded local-script resolver + usage string + bats.
3. **Allowlist** — `supply-chain.conf` reader (C4) + bats.
4. **Pattern** — `patterns/supply-chain.md` (P11–P14) + `cmd_patterns` glob + bats.
5. **Eval harness extension** — directory fixtures + 3-arg runner + `--as` + grader path-keying, **backward-compatible** (existing corpora green) + bats. *(Prerequisite for the corpus; the riskiest phase — touches the shared harness.)*
6. **Drivers** — wire `SKILL.md` + Codex; `report-format.md`.
7. **Corpus + baseline** — `tests/eval/supply-chain/` mini-repos; calibrate via `eval-run --as react-typescript`; CODEOWNERS PR.
8. **Docs** — READMEs, help, EXTENDING/CONTRIBUTING, CLAUDE.md.

Phase 5 (shared-harness change) lands behind passing existing single-file corpora before the
corpus depends on it. The eval gate (phase 7) is required before declaring #66 done.

---

## Open questions (resolve during planning, not blockers)

- **Resolver bounds** — exact size cap (KB vs line count) and whether to follow `&&`-chained
  commands; pick conservative defaults in the plan.
- **Allowlist precedence vs profiles** — confirm the reader's layer-walk matches `fm_field`
  semantics exactly so behavior is consistent with profile/pattern layering.

## References
- Issue #66; #78 (curated-typosquat-corpus exploration); P4 in `recurring.md`; #15 (eval harness); #71/#72 (runner determinism).
- OWASP Top 10 A06/A08; CWE-1357/829/494; SLSA; MITRE ATT&CK T1195; CAPEC-538.
- Codex spec-review (2026-06-17): findings HIGH-1/2/3 + MEDIUM-4/5/6 addressed above.

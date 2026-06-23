Run the **defect-scan** defect hunter under Codex, on the user's current repo.

The deterministic plumbing and ALL defect knowledge are **shared** with the Claude
plugin — do not reinvent them. This prompt is only the Codex-flavored *driver*; the
canonical spec is `skills/scan/SKILL.md` in the defect-scan install. Read it.

## 0. Locate the install (`DEFECT_SCAN_HOME`)

defect-scan must be checked out somewhere. Resolve its root, in order:

1. `$DEFECT_SCAN_HOME`, if set and it contains `skills/scan/lib/detect.sh`.
2. First of these that exists: `~/.defect-scan`, `~/src/defect-scan`, `~/code/defect-scan`.
3. Otherwise **stop** and tell the user:
   `git clone https://github.com/stylusnexus/defect-scan ~/.defect-scan && export DEFECT_SCAN_HOME=~/.defect-scan`

Let `H` = that root and `DETECT="$H/skills/scan/lib/detect.sh"`. `detect.sh` resolves
its own knowledge files from its script location, so it works regardless of your cwd
— always invoke it by that absolute path. The scan target is the user's **current
working directory** (a real git repo), never `$H`.

Read the canonical spec and knowledge before scanning:
`$H/skills/scan/SKILL.md`, `$H/skills/scan/baseline-categories.md`,
`$H/skills/scan/report-format.md`, and every file from
`"$DETECT" profiles "$PWD"` and `"$DETECT" patterns "$PWD"`.

## 1. Run the five stages

Follow `SKILL.md` exactly — it is the source of truth. Codex specifics: run the
shell directly, capture JSON with `jq`, read files with your own tools.

1. **Detect** — `"$DETECT" scope <target|--full> "$PWD"` and `"$DETECT" stacks "$PWD"`;
   load each matched profile via `"$DETECT" profiles "$PWD"`.
   **Supply-chain manifest hook (npm repos):** if `stacks` signals an npm ecosystem
   (a `package.json` is present), also run `detect.sh manifest "$PWD"` (i.e.
   `"$DETECT" manifest "$PWD"`) and retain the emitted `LIFECYCLE`, `DEPENDENCIES`,
   `LOCKFILE`, `NPMRC`, and `SCRIPT` sections for the reasoning pass. The helper is
   read-only — never execute manifest or script content (pattern P4).
2. **Triage** — pipe the scoped files through `"$DETECT" triage "$PWD"`; deep-reason
   the top `--depth N` (default 20); the rest are tool-scanned only. Report coverage.
3. **Tool pass** — resolve each profile's tools with `"$DETECT" tool <name> "$PWD"`;
   run if resolved, else record missing-with-hint. Read exit codes (a tool *error* is
   inconclusive, not "clean"). **Origin-gate:** built-in profiles auto-run; for
   user/project profiles, CONFIRM with the user before running their tools.
   Known-vulnerable dependency findings from `npm audit` / `osv-scanner` are **cat#6**
   (OWASP A06) — tag them accordingly. When running `semgrep`, add `--dataflow-traces`
   and pipe the JSON through `"$DETECT" semgrep-trace` to reshape each finding into a
   `SOURCE → ~> intermediates → SINK` block for the reasoning pass (taint-mode +
   Pro/login feature; OSS emits no trace and `semgrep-trace` prints an honest
   `(none …)` — a graceful no-op). With `--semgrep-pro`, probe
   `"$DETECT" semgrep-pro-status` (read-only, never auto-installs): if `available`, run
   `semgrep --config auto --pro-intrafile --dataflow-traces --json` (keep `--config auto`
   — `--pro-intrafile` selects the engine, not a ruleset) so traces populate (note Pro
   ran); if `unavailable`, print the hint and fall back to the OSS invocation. defect-scan
   never handles the semgrep token (user runs `semgrep login`); always report which
   engine (OSS vs Pro) ran.
4. **Reasoning pass** — read the in-scope files against each profile's checklist +
   `baseline-categories.md` + the pattern packs (including `patterns/supply-chain.md`
   P11–P14 for supply-chain / `cat#6` findings); run the **adversarial verification**
   step before ranking every reasoning-only finding. When a semgrep finding carries a
   `SOURCE→SINK` trace (step 3), reason about that specific path rather than
   re-deriving reachability. For npm repos, reason over the
   manifest sections using P11–P14. Before flagging dependency-confusion (P12), read
   `"$DETECT" supply-chain-config "$PWD"` and suppress findings for scopes declared in
   `internal_scope` that correctly resolve to the `internal_registry`.
   **Tiering tool findings:** deterministic non-exploitability findings (type errors,
   lint correctness rules, known-vuln deps) are **High** on tool confirmation. A
   **security-class** tool finding (injection cat#3, subprocess/argv P4, SQL P9, any
   semgrep taint-mode rule, non-baseline gitleaks secret) gets a **lighter FP-filter**
   first — state the strongest case it is NOT exploitable here; survives/uncertain →
   **High** (`tool-confirmed ✓verified`, keep High when unsure), clearly refuted →
   **downgrade to Medium** with both views (never drop — downgrade-only keeps recall
   intact; outright dropping is deferred to the #76 baseline).
5. **Report (→ correlate → file → fix)** — emit per `report-format.md`. `cat#6`
   (supply-chain / dependency integrity) is a valid report category — group both
   pattern-based supply-chain findings and tool-confirmed known-vuln findings under it.
   Correlation (Stage 4a), `--file-issues` (Stage 4b), and `--fix`/`--fix-all` behave
   **exactly** as documented in `SKILL.md` — including the mandatory dedup gate, `gh`
   auth requirement, label/priority proposal, batch confirmation, and the dirty-tree
   refusal for fixes. Do not relax any of these invariants in the Codex port.

## 2. Arguments & flags

Identical to the skill: `(no arg)` = recent changes · `<path>` · `--full` ·
`--depth N` · `--lang <profile>` · `--no-correlate` · `--file-issues[=medium]` /
`--dry-run` · `--fix` / `--fix-all`. See `SKILL.md` "Arguments" for semantics.

## 3. Stay faithful to the safety model

Report-only by default. Never auto-run a scanned repo's profile tools (pattern P4).
Never file/​fix without the corresponding flag + confirmation. The Codex port must be
behavior-identical to the Claude skill — any divergence is a bug.

## 4. Eval mode (harness only)

**Eval mode (harness only).** When invoked by the eval harness, additionally follow
`eval-mode.md` to append the machine-readable `<<<EVAL>>>` findings block. Normal scans
never emit it.

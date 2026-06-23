---
name: defect-scan
description: Use to hunt latent defects in code — a file, directory, diff, or whole repo. Detects the stack, triages files by risk, runs that language's real analyzers (ruff/mypy, tsc/eslint), reasons about defects tools miss, and reports findings in confidence tiers. Report-only by default; --fix applies the high-confidence tier. Use when asked to scan/audit code for bugs, find defects, or check a codebase for problems (not for debugging a known bug — use systematic-debugging — and not for reviewing a diff/PR — use /code-review).
---

# defect-scan

Language-aware defect hunter. Five stages: **detect → triage → tool pass →
reasoning pass → report (→ fix)**. The deterministic plumbing is `lib/detect.sh`;
the defect knowledge is in `profiles/`, `baseline-categories.md`, and
`report-format.md`.

**Paths:** `lib/detect.sh` and the knowledge files live in *this skill directory*,
not the user's project. The scan runs against the user's `cwd`, so invoke the
helper by its skill-dir path — as a plugin that is
`${CLAUDE_PLUGIN_ROOT}/skills/scan/lib/detect.sh`. The `lib/detect.sh …` snippets
below are shorthand for that absolute path.

## Arguments
- (no arg) → scan recent changes. `<path>` → scan that file/dir. `--full` → whole repo.
- `--depth N` → deep-reason the top **N** triaged source files (default **20**).
  `--depth 0` / `--full` with no cap means everything (expensive). The rest are
  tool-scanned only. This is the rabbit-hole floor — without it, a large repo
  deep-reasons until it exhausts the budget.
- `--fix` → apply the high-confidence tier, then re-run the tool to confirm.
- `--fix-all` → also apply the medium tier (after confirmation prompts).
- `--lang <profile>` → force a profile, skip detection.
- `--no-correlate` → skip the tracker-correlation stage (Stage 4a). Correlation is
  **on by default** when a GitHub remote and `gh` are available.
- `--cross-model` → verify reasoning findings through a second model (Codex) for a
  different-model second opinion (Stage 3b). Opt-in; needs `codex` installed; runs
  read-only. Worth it on load-bearing code (security, billing, retry/error paths).
- `--semgrep-pro` → run semgrep with the **Pro engine** (`--pro-intrafile`), which
  populates dataflow traces (Stage 3 path reasoning) and adds path-sensitivity the OSS
  engine lacks. Opt-in; requires the user's own Pro auth (`semgrep login &&
  semgrep install-semgrep-pro` — defect-scan never handles the token). Degrades to OSS
  with a hint if Pro is unavailable. See Stage 2.
- `--file-issues` → after the report, file a GitHub issue for each **[NEW]** finding
  (High tier by default; `--file-issues=medium` also files Medium; Low is never
  filed). A **write action** — see Stage 4b for the auth requirement, the mandatory
  dedup gate, label handling, and the batch confirmation. `--dry-run` pairs with it
  to preview without filing.
- `--help` → print this usage and exit; do not scan.

## Stage 1 — Detect
Resolve scope and stacks:
```
SCOPE=$(lib/detect.sh scope "<target>" <--full?> "<repo-root>")   # MODE + file list
lib/detect.sh stacks "<repo-root>"                                 # one profile per line
```
A repo may match multiple profiles; run each matched profile over its own files.
`--lang` overrides detection.

Profiles are discovered across three layers (built-in, `~/.config/defect-scan`,
`./.defect-scan`); `lib/detect.sh profiles <repo>` lists `name⇥path⇥origin`. Load
each matched profile by its path. `--no-user-profiles` / `--no-project-profiles`
set `DEFECT_SCAN_NO_USER=1` / `DEFECT_SCAN_NO_PROJECT=1` for a built-in-only scan.

**Supply-chain manifest hook (npm repos only).** When `detect.sh stacks` reports a
profile that signals an npm ecosystem (i.e. a `package.json` is present), also run:
```
lib/detect.sh manifest "<repo-root>"
```
This emits structured read-only sections — `LIFECYCLE`, `DEPENDENCIES`, `LOCKFILE`,
`NPMRC`, and `SCRIPT` (inline content of any referenced local install scripts) — that
feed the Stage 3 supply-chain reasoning pass. The helper never executes manifest or
script content; it only reads and surfaces it. Running install-time content would make
the scanner itself the attack vector (pattern P4 — do not relax this invariant).

## Stage 1b — Triage (approach a large codebase methodically)
Rank the in-scope files so the deep passes hit the highest-risk code first:
```
lib/detect.sh scope ... | tail -n +2 | lib/detect.sh triage "<repo-root>"
```
This scores each file by git churn, size (LOC), and security-sensitive
path/name matches, printing `<score>\tpath` highest-first. It ranks **source
files only** (docs/config/data are excluded, so high-churn `.md`/`.json` can't
out-rank code). Take the top **N** (`--depth N`, default 20) for the deep
reasoning pass:
```
... | lib/detect.sh triage "<repo-root>" | head -n "${DEPTH:-20}"
```
Lower-ranked files are tool-scanned only, not deep-reasoned — this is the
rabbit-hole floor. Record in the report header how many of how many ranked files
the deep pass reached (honest-about-coverage). On a single-file target this is a
trivial pass-through. Never silently drop files — always say how far the deep
pass reached.

## Stage 2 — Tool pass
For each profile, read its `## Toolchain`. Resolve every tool with
`lib/detect.sh tool <name> <project-dir>`. If a tool resolves, run it on the
in-scope files and capture structured output (`jq` for JSON). If it does not
resolve, record it as **missing** with the profile's install hint and continue —
never abort the scan. If a tool crashes or times out, capture stderr, mark that
check **inconclusive**, and continue.

**Origin-gated execution.** For a profile with `origin=builtin`, run its tools
automatically. For `origin=user` or `origin=project`, the profile came from a
scanned/user location — surface the suggested tool and CONFIRM with the user
before running it; resolve it via `lib/detect.sh tool <name>` (never a raw shell
string from the profile). This prevents a scanned repo's profile from executing
arbitrary commands (pattern P4).

**Cross-cutting deep analyzers (optional, any stack — run if installed).** These
sharpen ground truth for the reasoning categories tools usually miss; resolve each
via `lib/detect.sh tool <name>` and skip-with-hint if absent:
- **`semgrep`** — `semgrep --config auto --dataflow-traces --json <paths>` —
  multi-language taint rules covering injection (cat#3), subprocess/argv hygiene
  (P4), and SQL misuse (P9). The single highest-value optional add. These are
  **security-class** findings — Stage 3 runs the FP-filter verification before tiering
  them (don't auto-promote to High). Pipe the JSON through
  `lib/detect.sh semgrep-trace` to reshape each finding into a compact
  `SOURCE → ~> intermediates → SINK` block for the Stage 3 reasoning pass — feeding
  the model the actual tainted path beats re-deriving reachability from the location
  alone. The populated trace is a **taint-mode + Pro-engine/login** feature; OSS
  semgrep returns `dataflow_trace=null` and `semgrep-trace` prints an honest
  `(none …)` per finding — a graceful no-op, not an error. (Trace is single-file /
  intra-procedural; the cross-file version is tracked separately.)
  **Pro engine (`--semgrep-pro`).** OSS semgrep emits no dataflow trace. When the user
  passes `--semgrep-pro`, first probe `lib/detect.sh semgrep-pro-status` (read-only,
  never auto-installs):
  - `available` → run `semgrep --config auto --pro-intrafile --dataflow-traces --json
    <paths>` (keep `--config auto` — `--pro-intrafile` selects the *engine*, not a
    ruleset) so the trace actually populates (real path-sensitive traces → richer
    Stage 3); note in the report header that the **Pro** engine ran.
  - `unavailable: …` → print the hint and **fall back to the OSS invocation above**; the
    scan continues (Pro is an enhancement, never a hard dependency).
  defect-scan never handles the semgrep token — the user authenticates once with
  `semgrep login` and semgrep stores its own credentials. Without `--semgrep-pro`, run
  OSS exactly as above; if `semgrep-pro-status` reports `available` but the flag wasn't
  passed, you may note in the report that re-running with `--semgrep-pro` would deepen
  the taint analysis. Always report which engine (OSS vs Pro) ran — they find different
  things.
- **`gitleaks`** — committed secrets/credentials (cat#3-adjacent supply-chain).
  **Scan committed content, and pre-filter, or it's pure noise.** Use git mode with the
  bundled baseline config:
  `gitleaks git --report-format json -c ${CLAUDE_PLUGIN_ROOT}/skills/scan/gitleaks-baseline.toml`
  — **git mode** (not `--no-git`) only sees *tracked/committed* files, so it skips
  `node_modules/`, build output, and gitignored `.env*` automatically; the baseline
  allowlists those paths and well-known **public demo keys** (e.g. the Supabase demo
  anon/service JWTs) that otherwise generate thousands of false positives.
  **Triage before reporting — never dump the raw count:**
  1. Only a **committed** secret is a real leak — a hit in a gitignored/untracked file
     is not (confirm with `git ls-files --error-unmatch <file>`); for a *public* repo,
     only committed history matters.
  2. **Collapse mass-duplicates** — one demo/example key repeated across N CI files is
     one finding (note the count), not N. If the raw count is huge and dominated by one
     pattern, say so and report the *triaged* number.
  3. A genuine committed, non-demo secret is **High**; everything else is noise — drop it.
  The baseline allowlists only generated/vendored paths (node_modules, build output) +
  demo-key *values* — it does **not** allowlist `examples/`/`.env.local` etc., so a real
  secret committed there still fires. Tradeoff: git-mode misses a secret in an
  *uncommitted* working file (the `DEFECT_SCAN_HOOK` pre-commit advisory covers that lane).
  (Dogfood lesson, issue #20: a raw `--no-git` run produced 8522 findings, 100% false
  positive — all public demo JWTs + gitignored files — burying the one real check.)
Install hints: `brew install semgrep gitleaks` (or `pipx install semgrep`).

**Read exit codes — do not equate "ran" with "clean."** A non-zero exit that means
*problems found* (e.g. eslint `1`, tsc with diagnostics) is data to parse. A
non-zero exit that means *tool/usage/config error* (e.g. eslint `2`, "No files
matching the pattern", a config parse failure) is **inconclusive** — report it as
such with the stderr reason; never let a tool error read as a passing file.

## Stage 3 — Reasoning pass
Read the in-scope files against the profile's `## Reasoning checklist`,
`baseline-categories.md`, and
consult every file listed by `lib/detect.sh patterns <repo>` (built-in `patterns/recurring.md`
P1–P10, `patterns/supply-chain.md` P11–P14, plus any user/project pattern packs). For EVERY
reasoning-only finding, run an **adversarial verification** pass before ranking: state the
strongest case that the finding is NOT a real defect (guard exists elsewhere, input is trusted,
path unreachable).

When a semgrep finding carries a `SOURCE → ~> intermediates → SINK` trace (from
`lib/detect.sh semgrep-trace`, Stage 2), reason about *that specific path* — is the
source attacker-controlled, is there a sanitizer between it and the sink — rather than
re-deriving reachability from the finding location. A `(none …)` trace (the common
case on OSS semgrep) means reason from the location as before.

**Supply-chain reasoning (npm repos — `cat#6`).** When manifest sections are available
(Stage 1 supply-chain hook), reason over the `LIFECYCLE`, `DEPENDENCIES`, `LOCKFILE`,
`NPMRC`, and `SCRIPT` sections using `patterns/supply-chain.md` (P11–P14) as the
reasoning checklist. Before flagging dependency-confusion candidates (P12), read the
project's internal-scope allowlist:
```
lib/detect.sh supply-chain-config "<repo-root>"
```
Declared `internal_scope` / `internal_registry` pairs suppress false positives for
scoped packages that legitimately resolve to a private registry. Known-vulnerable and
outdated dependency findings produced by `npm audit` / `osv-scanner` (tool pass) are
also **cat#6** (A06 / OWASP) — tag those tool findings `cat#6` so they group with
other supply-chain findings in the report.
- Survives with a clear repro path → eligible for **High**.
- Survives but no clear repro → **Medium**.
- Refuted → drop it (or **Low** if genuinely ambiguous).

**Tiering tool findings.** A deterministic, non-exploitability finding — a type error
(tsc/mypy), a lint *correctness* rule, a known-vuln dependency (npm audit / osv) — is
**High** as soon as the tool confirms it; there is no exploitability question to verify.
A **security-class** tool finding — one whose category turns on *reachability /
exploitability*: injection (cat#3), subprocess/argv hygiene (P4), SQL misuse (P9), any
semgrep taint-mode rule, or a non-baseline secret (gitleaks) — gets a **lighter
FP-filter verification** first. SAST rules fire on patterns, not proof (standalone
precision runs ~⅓), so the tool having located the finding is the cheap half; don't
re-derive it — just state the strongest case it is NOT exploitable *here* (unreachable,
sanitized upstream, a test/fixture/example file, a demo/placeholder value, or a rule
mis-fire). Then:
- Survives, or genuinely uncertain → **High**, tagged `tool-confirmed ✓verified`. Keep
  High when unsure — never downgrade on a hunch.
- Clearly refuted with a stated reason → **downgrade to Medium**, surfacing BOTH the
  tool's claim and the refutation. Do **not** drop it: downgrade-only keeps every
  finding in the report (and the eval block), so coverage/recall is unchanged — only the
  tier shifts, which is what gates `--file-issues` and `--fix`. Dropping clearly-false
  security findings outright is deferred until the eval baseline (#76) confirms it does
  not regress recall.

The above is the **confidence tier**. Also assign each finding a **severity** (how bad
if real) on a *separate* axis: take the default from its category
(`baseline-categories.md`) or pattern (`recurring.md`), adjust for context, and honor
any project `.defect-scan/` severity policy (highest-precedence layer wins). Report
both axes (`report-format.md`); severity is what `--file-issues` maps to a priority.

### Stage 3b — Cross-model verification (only when `--cross-model`)
Get a second opinion from a **different model** (Codex) — different models have
different blind spots, so this catches both false positives the scanning model is
overconfident about and real defects it rationalized away. `codex-verify`
self-resolves the `codex` binary (honoring `DEFECT_SCAN_CODEX`) and returns **exit 3**
when it's absent — treat that as the skip signal: say so in the header and continue
(never block). For each reasoning finding eligible for **High/Medium**, write a verification prompt
to a temp file — the `file:line`, the evidence, the surrounding code, and *"state the
strongest case this is NOT a real defect, then answer real / not-real with a one-line
reason"* — and run:
```
lib/detect.sh codex-verify <prompt-file>
```
This runs Codex **read-only** (it cannot write or execute side-effecting commands —
a verification must never mutate the scanned repo, pattern P4). Consolidate:
- Both models agree it's real → keep the tier; tag **cross-model ✓**.
- Codex **refutes** a finding the scan rated High → downgrade to Medium and surface
  both views; don't silently keep or drop it.
- Codex surfaces a real defect the scan missed → add it (tag **cross-model**, the
  catching model noted).
Tool-confirmed findings are already High and don't need cross-model. Note in the
report header that cross-model ran (and against which model), so coverage is honest.

## Stage 4 — Report (→ fix)
Merge tool + reasoning findings, dedupe by `file:line + category`, rank by
tier then severity, and emit using `report-format.md`. Always print the header
with tools-run vs tools-missing and how far triage's deep pass reached.

### Stage 4a — Correlate with the tracker (on by default; `--no-correlate` to skip)
Before presenting (and before filing/fixing), cross-check each finding against
existing issues so you neither re-report nor re-file a known defect:
```
lib/detect.sh issues "<key terms from the finding: file/symbol + defect words>"
```
This is **search-driven** (one targeted query per finding, capped at
`DEFECT_SCAN_ISSUE_LIMIT`) — it must not bulk-pull, because `gh`'s default list
cap is 30 and real repos have thousands of issues. Reason over the returned
candidates (don't string-match) and tag each finding:
- **[NEW]** — no matching issue.
- **[LIKELY FILED #N]** — an open issue describes this same defect; don't re-file,
  point at #N.
- **[RELATED #N]** — same family/root cause, different instance (e.g. the
  `billing-integrity` cluster); link it.
- A **closed** match → **[VERIFY REGRESSION #N]**: previously fixed; flag that it
  may have regressed.
If correlation is unavailable (no `gh`/remote — exit 3), say so in the header and
treat every finding as uncorrelated; never imply NEW when you simply couldn't check.

### Stage 4b — File issues (offer always; act on --file-issues)
Turn confirmed findings into tracker issues — **deduped, opt-in, and write-gated.**

**Offer it even without the flag.** When a GitHub remote and `gh` are available and
the report has one or more **[NEW]** findings, end the report by offering: *"N new
High finding(s) — file them as GitHub issues? This is a write action and needs `gh`
authentication (`gh auth status`)."* If `--file-issues` was passed, skip the offer
and go straight to the confirmation batch below.

**Dedup is mandatory — never file a duplicate.** Filing is gated on Stage 4a:
- `--file-issues` **requires** correlation. If the user combined it with
  `--no-correlate`, refuse and explain — you cannot dedup without the tracker check.
- File **only** findings tagged **[NEW]**. For **[LIKELY FILED #N]** / **[RELATED #N]**,
  do not create — point at / link the existing issue instead. For
  **[VERIFY REGRESSION #N]**, do not create — flag the possible regression on #N.
- Immediately before creating each issue, re-run `lib/detect.sh issues "<terms>"`
  one final time and **also** dedup against titles you've already filed earlier in
  this same batch — this catches races and within-run duplicates.

**Authentication.** Filing needs an authenticated `gh`. If `gh auth status` fails or
`issues-create` returns exit 3, stop and tell the user to authenticate; never treat
a failed file as "filed."

**Labels — propose the repo's existing labels; don't assume.** List them once with
`lib/detect.sh labels` and reason over the result for two dimensions:

*Kind label.*
- If a defect-related label already exists (e.g. `bug`, `defect`, `defect-scan`),
  **propose using it** and confirm — prefer reusing the repo's own taxonomy.
- Only if none fits, offer to create a `defect-scan` label via
  `lib/detect.sh issues-ensure-label defect-scan` (best-effort; never blocks filing).

*Priority label.* Carry each finding's severity through to a priority on the issue.
- Look for an existing priority scheme in the label list — any shape: `P0`/`P1`/`P2`,
  `priority: high`/`priority/high`, `critical`/`major`/`minor`, etc. If one exists,
  **propose mapping into it** (don't invent a parallel scheme): tier+severity →
  priority, e.g. High+critical → highest, High → high, Medium → medium.
- If **no** priority labels exist, **offer to create** `P0`/`P1`/`P2` (confirm first;
  `lib/detect.sh issues-ensure-label P0 …`), then apply. If the user declines, file
  with the kind label only — priority is additive, never a blocker.
- Pass both labels comma-joined to `issues-create` (e.g. `"defect-scan,P1"`).

If the labels query is unavailable (exit 3), file without labels rather than guessing
ones that may not exist (a missing label makes `gh issue create` fail).

**Confirm the batch, then file.** Print the proposed issue titles (and the chosen
label) and get a yes before writing — a `--full` pre-launch scan can surface many
findings, and mass-filing spams the tracker. With `--dry-run`, print exactly what
would be filed and stop. Otherwise, for each [NEW] finding:
```
# body built from report-format.md: file:line, category, severity, tier,
# the evidence/adversarial-verification note, and the tool/pattern that flagged it.
lib/detect.sh issues-create "<title>" "<body-file>" "<kind-label>[,<priority-label>]"
```
The helper prints the new issue URL. Capture it, re-tag the finding **[FILED #N]** in
the final report, and summarize: *"Filed N issues: #.. #.. ; skipped M already-filed."*

### Fixing (only when --fix / --fix-all)
- **Refuse if the working tree is dirty** (uncommitted changes) unless the user
  has committed/stashed — so fixes stay revertable. Tell them why.
- `--fix`: apply only the profile's `## Auto-fix-safe` items in the **High** tier
  (e.g. run `ruff check --fix` / `eslint --fix` for the safe rule subset). After
  applying, re-run that tool on the touched files and confirm the finding cleared.
  Report what was fixed and what was confirmed.
- `--fix-all`: additionally walk Medium findings, but confirm each with the user
  before editing.
- Never auto-fix type-checker findings or behavior-changing lint rules
  (`exhaustive-deps`, bare-except→named). List them for the human.

### Eval mode (harness only)
**Eval mode (harness only).** When invoked by the eval harness, additionally follow
`eval-mode.md` to append the machine-readable `<<<EVAL>>>` findings block. Normal scans
never emit it.

## Handing off
Heavy remediation is not this skill's job — once defects are reported, point the
user to `systematic-debugging` (root-cause a specific one) or
`review-merge-pipeline` (ship the fixes).

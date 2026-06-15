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
- **`semgrep`** — `semgrep --config auto --json <paths>` — multi-language taint
  rules covering injection (cat#3), subprocess/argv hygiene (P4), and SQL misuse
  (P9). The single highest-value optional add. Findings are **High** (tool-confirmed).
- **`gitleaks`** — `gitleaks detect --no-git --report-format json` — committed
  secrets/credentials (cat#3-adjacent supply-chain). Any hit is **High**.
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
P1–P10 plus any user/project pattern packs). For EVERY reasoning-only finding, run an
**adversarial verification** pass before ranking: state the strongest case that the finding is
NOT a real defect (guard exists elsewhere, input is trusted, path unreachable).
- Survives with a clear repro path → eligible for **High**.
- Survives but no clear repro → **Medium**.
- Refuted → drop it (or **Low** if genuinely ambiguous).
Tool-confirmed findings are **High** by definition.

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

## Handing off
Heavy remediation is not this skill's job — once defects are reported, point the
user to `systematic-debugging` (root-cause a specific one) or
`review-merge-pipeline` (ship the fixes).

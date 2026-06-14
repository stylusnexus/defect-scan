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
- `--help` → print this usage and exit; do not scan.

## Stage 1 — Detect
Resolve scope and stacks:
```
SCOPE=$(lib/detect.sh scope "<target>" <--full?> "<repo-root>")   # MODE + file list
lib/detect.sh stacks "<repo-root>"                                 # one profile per line
```
A repo may match multiple profiles; run each matched profile over its own files.
`--lang` overrides detection.

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

**Read exit codes — do not equate "ran" with "clean."** A non-zero exit that means
*problems found* (e.g. eslint `1`, tsc with diagnostics) is data to parse. A
non-zero exit that means *tool/usage/config error* (e.g. eslint `2`, "No files
matching the pattern", a config parse failure) is **inconclusive** — report it as
such with the stderr reason; never let a tool error read as a passing file.

## Stage 3 — Reasoning pass
Read the in-scope files against the profile's `## Reasoning checklist`,
`baseline-categories.md`, and `patterns/recurring.md` (battle-tested cross-cutting
patterns: metered-action charge/refund correctness, string-keyed identifier drift,
privileged-audience data leaks). For EVERY reasoning-only finding, run an
**adversarial verification** pass before ranking: state the strongest case that the finding is
NOT a real defect (guard exists elsewhere, input is trusted, path unreachable).
- Survives with a clear repro path → eligible for **High**.
- Survives but no clear repro → **Medium**.
- Refuted → drop it (or **Low** if genuinely ambiguous).
Tool-confirmed findings are **High** by definition.

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

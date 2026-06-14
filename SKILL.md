---
name: defect-scan
description: Use to hunt latent defects in code — a file, directory, diff, or whole repo. Detects the stack, triages files by risk, runs that language's real analyzers (ruff/mypy, tsc/eslint), reasons about defects tools miss, and reports findings in confidence tiers. Report-only by default; --fix applies the high-confidence tier. Use when asked to scan/audit code for bugs, find defects, or check a codebase for problems (not for debugging a known bug — use systematic-debugging — and not for reviewing a diff/PR — use /code-review).
---

# defect-scan

Language-aware defect hunter. Five stages: **detect → triage → tool pass →
reasoning pass → report (→ fix)**. The deterministic plumbing is `lib/detect.sh`;
the defect knowledge is in `profiles/`, `baseline-categories.md`, and
`report-format.md`.

## Arguments
- (no arg) → scan recent changes. `<path>` → scan that file/dir. `--full` → whole repo.
- `--fix` → apply the high-confidence tier, then re-run the tool to confirm.
- `--fix-all` → also apply the medium tier (after confirmation prompts).
- `--lang <profile>` → force a profile, skip detection.
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
out-rank code). Process files in that order. On `--full` or any large file set, focus the reasoning pass on the top of
the ranking and note in the report that lower-ranked files were tool-scanned but
not deep-reasoned (honest-about-coverage). On a single-file target this is a
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
Read the in-scope files against the profile's `## Reasoning checklist` and
`baseline-categories.md`. For EVERY reasoning-only finding, run an
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

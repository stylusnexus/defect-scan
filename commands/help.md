---
description: Show defect-scan usage — what it does, arguments, and how to run it.
---

Print the following help verbatim to the user (do not scan anything):

# defect-scan — help

Language-aware defect hunter. Pipeline: **detect → triage → tool pass → reasoning → report (→ fix)**.

## Run it
- `/defect-scan:scan` — scan recent changes (uncommitted, else last commit)
- `/defect-scan:scan <path>` — scan a file or directory
- `/defect-scan:scan --full` — scan the whole repo (triaged, depth-capped)

## Flags
- `--depth N` — deep-reason the top N triaged source files (default 20)
- `--fix` — apply the high-confidence, tool-confirmed tier (re-verified)
- `--fix-all` — also apply the medium tier (with confirmation)
- `--lang <profile>` — force a profile (react-typescript | python | generic)
- `--no-correlate` — skip GitHub-issue correlation (on by default when `gh` is present)

## What it uses
- **Real analyzers if installed** (project-local first): `ruff`/`mypy`, `tsc`/`eslint`;
  optional deeper: `semgrep`, `gitleaks`, `bandit`, `pip-audit`, `npm audit`, `osv-scanner`.
  Install the optional set: `sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup-optional-tools.sh`
- **9 battle-tested patterns** (`patterns/recurring.md`) + per-language reasoning checklists.
- **Confidence tiers**: High (tool-confirmed / adversarially verified) · Medium · Low.
- **Tracker correlation**: tags findings NEW / LIKELY FILED #N / RELATED #N / VERIFY REGRESSION #N.

## Optional pre-commit advisory (off by default)
Set `DEFECT_SCAN_HOOK=1` to get a one-line, non-blocking advisory on changed files
when committing. Run `/defect-scan:scan` for the full report.

## Not the right tool when…
- Debugging a *known* bug → use `systematic-debugging`.
- Reviewing a diff/PR → use `/code-review`.

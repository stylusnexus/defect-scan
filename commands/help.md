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
- `--lang <profile>` — force a profile (react-typescript | python | ruby | go | csharp | java | yaml | rust | kotlin | swift | php | shell | dart | objc | generic)
- `--no-correlate` — skip GitHub-issue correlation (on by default when `gh` is present)
- `--cross-model` — verify reasoning findings through a second model (Codex, read-only)
  for a different-model second opinion; needs `codex` installed
- `--file-issues[=medium]` — file a GitHub issue per NEW finding (High only by default;
  `=medium` includes Medium). Write action: needs `gh` auth, dedupes against existing
  issues (requires correlation), reuses the repo's existing defect + priority labels
  (offers to add P0/P1/P2 if none exist), and confirms the batch first. Pair with
  `--dry-run` to preview without filing.
- `--sarif <path>` — also write a SARIF 2.1.0 report to `<path>` (for GitHub
  code-scanning / the VS Code SARIF viewer). Opt-in; the prose report is unchanged.

## What it uses
- **Real analyzers if installed** (project-local first): `ruff`/`mypy`, `tsc`/`eslint`;
  optional deeper: `semgrep`, `gitleaks`, `bandit`, `pip-audit`, `npm audit`, `osv-scanner`.
  Install the optional set: `sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup-optional-tools.sh`
- **14 battle-tested patterns** across two built-in packs: `patterns/recurring.md` (P1–P10,
  cross-cutting correctness/security) and `patterns/supply-chain.md` (P11–P14, npm supply-chain:
  malicious lifecycle scripts, typosquat/dependency-confusion, lockfile tampering, install-time
  exfil) + per-language reasoning checklists. Supply-chain findings (cat#6) complement
  `npm audit` and `osv-scanner` with reasoning over the manifest and lifecycle surface.
- **Confidence tiers**: High (tool-confirmed / adversarially verified) · Medium · Low.
- **Tracker correlation**: tags findings NEW / LIKELY FILED #N / RELATED #N / VERIFY REGRESSION #N.
- **Issue filing** (`--file-issues`, opt-in): files NEW findings, deduped against the
  tracker, using the repo's existing defect labels — handy for a pre-launch sweep.
- **Extensible:** add a language or defect pack by dropping files in `.defect-scan/`
  — see `EXTENDING.md` (copy `profiles/TEMPLATE.md.example`, fill 4 fields).

## Optional pre-commit advisory (off by default)
Set `DEFECT_SCAN_HOOK=1` to get a one-line, non-blocking advisory on changed files
when committing. Run `/defect-scan:scan` for the full report.

## Platforms
macOS, Linux, and Windows (WSL/Git-Bash). Native PowerShell: use
`windows/defect-scan.ps1`. Verify tooling with `detect.sh preflight`.

## Not the right tool when…
- Debugging a *known* bug → use `systematic-debugging`.
- Reviewing a diff/PR → use `/code-review`.

# defect-scan

Language-aware defect-finding **plugin** for Claude Code. Detects the stack,
triages files by risk, runs the real analyzers a project already has, reasons
about what tools miss using battle-tested patterns, and reports findings in
confidence tiers (correlated against the issue tracker). Report-only by default;
`--fix` applies the high-confidence tier.

## Layout (plugin)
```
.claude-plugin/plugin.json     # plugin manifest
skills/scan/                   # the skill — invoked as /defect-scan:scan
  SKILL.md  profiles/  patterns/  baseline-categories.md  report-format.md
  lib/detect.sh                # deterministic plumbing (scope/stacks/tool/triage/issues)
tests/                         # bats suite (run: bats tests/detect.bats)
specs/  plans/                 # design + implementation history
```

## Install (team, via marketplace)
```
/plugin marketplace add stylusnexus/agent-plugins
/plugin install defect-scan@agent-plugins
```
Then invoke with `/defect-scan:scan` (or let the model auto-invoke it).

## Help
`/defect-scan:help` prints usage, flags, and what it uses.

## Optional analyzers (richer coverage, all degrade-gracefully)
The scan runs whatever's installed and skips the rest with an install hint:
- **`semgrep`** — multi-language taint (injection, subprocess, SQL) — highest-value add
- **`gitleaks`** — committed secrets
- **`bandit` / `pip-audit`** (Python), **`npm audit` / `osv-scanner`** (JS/TS) — security + vuln deps

`brew install semgrep gitleaks` · `pip install bandit pip-audit`

## Optional pre-commit advisory (off by default)
Set `DEFECT_SCAN_HOOK=1` to get a one-line, **non-blocking** advisory on changed
source files when committing. It runs only the deterministic tool pass; for the
full reasoning report run `/defect-scan:scan`.

## Local dev
`./install.sh` symlinks `skills/scan/` into `~/.claude/skills/defect-scan` so it
loads while you iterate. Remove that symlink once the plugin is installed, to
avoid a double-load. Run tests: `bats tests/detect.bats`.

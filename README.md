# defect-scan

Language-aware defect-finding **plugin** for Claude Code (and Codex). Detects the
stack, triages files by risk, runs the real analyzers a project already has, reasons
about what tools miss using battle-tested patterns, and reports findings in
confidence tiers (correlated against the issue tracker). Report-only by default;
`--fix` applies the high-confidence tier.

## Built-in languages
14 profiles, each pairing the language's real analyzers with a reasoning checklist
mapped to the five baseline defect categories + language-specific footguns:

| Profile | Analyzers (auto-run if installed) |
|---|---|
| **python** | ruff, mypy · +bandit, pip-audit |
| **react-typescript** | tsc, eslint (type-aware) · +npm audit, osv-scanner |
| **ruby** | rubocop · +brakeman, bundler-audit |
| **go** | go vet, staticcheck, golangci-lint, govulncheck |
| **csharp** | Roslyn analyzers, dotnet list --vulnerable · +Security Code Scan, roslynator |
| **java** | Error Prone, SpotBugs + find-sec-bugs, PMD, OWASP dependency-check |
| **kotlin** | detekt, ktlint · +Android Lint |
| **swift** | SwiftLint, swift-format |
| **php** | PHPStan, Psalm (+taint), composer audit |
| **rust** | clippy, cargo-audit, cargo-deny |
| **dart** (Flutter) | dart/flutter analyze |
| **yaml** | yamllint · +actionlint/zizmor (Actions), kube-linter (k8s), ansible-lint |
| **shell** | shellcheck |
| **generic** | cross-cutting patterns + optional semgrep/gitleaks on any stack |

Missing analyzers are reported with an install hint and skipped — the scan never
aborts. Add your own language or rules with zero core edits (see *Extending it*).

## Layout (plugin)
```
.claude-plugin/plugin.json     # plugin manifest
skills/scan/                   # the skill — invoked as /defect-scan:scan
  SKILL.md  profiles/  patterns/  baseline-categories.md  report-format.md
  lib/detect.sh                # deterministic plumbing (scope/stacks/tool/triage/issues/labels)
commands/help.md               # /defect-scan:help
hooks/                         # opt-in pre-commit advisory (hooks.json + pre-commit-scan.sh)
scripts/setup-optional-tools.sh# one-liner installer for the optional analyzers
tests/                         # bats suite (run: bats tests/detect.bats)
specs/  plans/                 # design + implementation history
```

## Install (team, via marketplace)
```
/plugin marketplace add stylusnexus/agent-plugins
/plugin install defect-scan@stylus-nexus
```
The repo is `stylusnexus/agent-plugins`; the marketplace **name** is `stylus-nexus`
— so the install suffix is `@stylus-nexus`, not `@agent-plugins`. Then invoke with
`/defect-scan:scan` (or let the model auto-invoke it). If a fresh install reports
"not found," run `/plugin marketplace update stylus-nexus` first (stale cache).

## Help
`/defect-scan:help` prints usage, flags, and what it uses.

## Codex
defect-scan also runs under the [Codex CLI](https://github.com/openai/codex) — the
scan logic, profiles, and patterns are shared; only the entrypoint differs. See
[`codex/README.md`](./codex/README.md) to install the Codex prompt.

## Supported platforms
The engine is one POSIX-sh library, so it runs on **macOS** (BSD userland), **Linux**
(GNU userland), and **Windows via WSL or Git-Bash**. CI runs the suite on both Ubuntu
and macOS to catch BSD-vs-GNU regressions. **Native PowerShell** users get a fallback
shim (`windows/defect-scan.ps1`) that delegates to the bash bundled with Git for
Windows — see [`windows/README.md`](./windows/README.md). Check your environment with
`detect.sh preflight` (verifies git/awk/sed/grep/jq… are present).

## Optional analyzers (richer coverage, all degrade-gracefully)
The scan runs whatever's installed and skips the rest with an install hint:
- **`semgrep`** — multi-language taint (injection, subprocess, SQL) — highest-value add
- **`gitleaks`** — committed secrets (run git-mode with the bundled
  `skills/scan/gitleaks-baseline.toml`, which allowlists node_modules/build output and
  well-known public demo keys so the scan isn't drowned in false positives)
- **`bandit` / `pip-audit`** (Python), **`npm audit` / `osv-scanner`** (JS/TS) — security + vuln deps

One-liner to install them all (best-effort, per your package managers):
`sh scripts/setup-optional-tools.sh`
(or manually: `brew install semgrep gitleaks osv-scanner` · `pip install bandit pip-audit`)

## Optional pre-commit advisory (off by default)
Set `DEFECT_SCAN_HOOK=1` to get a one-line, **non-blocking** advisory on changed
source files when committing. It runs only the deterministic tool pass; for the
full reasoning report run `/defect-scan:scan`.

## Extending it (zero core edits)
Add a language or custom defect rules by dropping files in `.defect-scan/` (team)
or `~/.config/defect-scan/` (personal) — no core changes. Copy
`skills/scan/profiles/TEMPLATE.md.example`, fill four frontmatter fields, done.
**Full step-by-step guide: [`EXTENDING.md`](./EXTENDING.md).**

### Three layers — and what belongs where
Both **profiles** (languages) and **patterns** (cross-cutting defect classes) resolve
across three layers, low→high precedence; higher layers shadow lower **by name**:

| Layer | Profiles | Patterns | What belongs here |
|-------|----------|----------|-------------------|
| **Built-in (global)** | `skills/scan/profiles/` | `skills/scan/patterns/recurring.md` | **Generic** detections useful to *everyone* — no product/org/customer specifics. This is a public, shared plugin. |
| **User** (`~/.config/defect-scan/`) | `profiles/*.md` | `patterns/*.md` | Your personal rules across all your repos. |
| **Project** (`<repo>/.defect-scan/`) | `profiles/*.md` | `patterns/*.md` | **Product/org-specific** detections — your billing rules, your naming conventions, your internal APIs. Committed with the repo, scoped to it. |

The dividing line: **built-ins stay generic; anything specific to one product, codebase,
or company goes in that repo's project layer.** Example — the built-in P1 "metered-action
correctness" pattern is generic billing-integrity; a specific product's billing
manifestations (exact routes, field names, known incidents) belong in *its*
`.defect-scan/patterns/`, not here. `lib/detect.sh profiles <repo>` and `… patterns <repo>`
show every layer's contributions with their origin (`builtin`/`user`/`project`); set
`DEFECT_SCAN_NO_USER=1` / `DEFECT_SCAN_NO_PROJECT=1` (the `--no-user-profiles` /
`--no-project-profiles` scan flags) to restrict to built-ins only.

## Local dev
`./install.sh` symlinks `skills/scan/` into `~/.claude/skills/defect-scan` so it
loads while you iterate. Remove that symlink once the plugin is installed, to
avoid a double-load. Run tests: `bats tests/detect.bats`.

## Contributing
PRs welcome — see **[CONTRIBUTING.md](./CONTRIBUTING.md)** for setup, conventions,
and step-by-step guides to **add** a language profile, **enhance** an existing one,
or add a defect pattern. To extend defect-scan *privately* (no PR), see
[EXTENDING.md](./EXTENDING.md). Be excellent to each other:
[Code of Conduct](./CODE_OF_CONDUCT.md). Security issues: [SECURITY.md](./SECURITY.md)
(private reporting — don't open a public issue).

CI runs the bats suite, a POSIX-shell syntax check, and a gitleaks secret scan on
every PR. Scan quality is measured against a labeled corpus (`tests/eval/`); the
loop-closing harness that scores it is **maintainer-run** (manual, not on PR), and a
green eval means the change *didn't get worse*, not that it got better at the real job.
Releases are automated: [release-please](https://github.com/googleapis/release-please)
generates [CHANGELOG.md](./CHANGELOG.md) and bumps the version from Conventional
Commit titles at deploy.

## License
[MIT](./LICENSE) © Stylus Nexus.

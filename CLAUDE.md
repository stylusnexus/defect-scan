# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`defect-scan` is a **Claude Code plugin**, not an application. The deliverable is a
skill: prose knowledge (markdown) that a model executes, plus one POSIX-shell
library (`skills/scan/lib/detect.sh`) that does the deterministic plumbing. There
is no build step and no runtime service. "Running" the scan means a Claude session
loads `SKILL.md` and follows its five stages against a *target* repo (the user's
`cwd`), shelling out to `detect.sh` for the mechanical parts.

**Two harnesses, one brain.** The same pipeline also runs under **Codex**
(`codex/defect-scan.md` + `AGENTS.md`). Both Claude (`skills/scan/SKILL.md`) and
Codex are thin *drivers* over the shared `detect.sh` + `profiles/` + `patterns/` +
`report-format.md`/`baseline-categories.md` — those are the single source of truth.
A behavior change goes in the shared layer; if it changes the pipeline, update **both**
drivers. Divergence between harnesses is a bug. (`detect.sh` resolves its knowledge
files from its own script location, so it runs from any cwd under either harness.)
Separately, `--cross-model` (Stage 3b) uses Codex as a read-only *second-opinion
verifier* on the Claude scan's findings (`detect.sh codex-verify`) — different models,
different blind spots. That's distinct from running the whole scan under Codex.

Distributed via the `stylusnexus/agent-plugins` marketplace (name `stylus-nexus`);
installed as `/plugin install defect-scan@stylus-nexus`, invoked as
`/defect-scan:scan`.

## Commands

There is no build step — `bats tests/detect.bats` is the verification gate; run it
before shipping (it stands in for a build check, e.g. in `/review-merge-pipeline`).

```sh
bats tests/detect.bats          # the entire test suite — exercises detect.sh + asserts SKILL/profile invariants
./install.sh                    # symlink skills/scan/ → ~/.claude/skills/defect-scan for local iteration
sh scripts/setup-optional-tools.sh   # best-effort install of optional analyzers (semgrep, gitleaks, etc.)

# Run one detect.sh subcommand directly while developing:
skills/scan/lib/detect.sh stacks   <repo>
skills/scan/lib/detect.sh scope    <target> <--full?> <repo>
skills/scan/lib/detect.sh triage   <repo>      # reads file list on stdin
skills/scan/lib/detect.sh profiles <repo>      # name⇥path⇥origin, one per line
skills/scan/lib/detect.sh tool <name> <cwd>    # resolve an analyzer binary (exit 1 = unresolved)
skills/scan/lib/detect.sh issues <terms>       # search tracker (correlation/dedup; read; exit 3 if no gh)
skills/scan/lib/detect.sh labels               # list repo labels (for label/priority proposal; exit 3 if no gh)
skills/scan/lib/detect.sh issues-create <title> <body-file> [labels]   # file an issue (write; exit 3 if no gh)

# Maintainer eval loop (#15) — measure, don't regress. Both model-free:
skills/scan/lib/detect.sh eval <corpus-dir> <findings-file>   # grader: score a findings file (P/R/tp/fp/fn)
scripts/eval-run <lang> [--runs N] [--split seen|held-out|all] [--update-baseline]   # orchestrate: scan fixtures via a runner, then grade
```

Run a single test by description: `bats tests/detect.bats -f "triage: ranks"`.
The suite has no external network deps — `gh` is stubbed via `DEFECT_SCAN_GH`
(see `tests/fixtures/gh-stub/gh`), and analyzer tests `skip` when the tool is absent.

## Architecture — the split that matters

**`detect.sh` is deterministic; the model does the reasoning.** This boundary is
the central design decision. Anything mechanical and repeatable (scope resolution,
stack detection, file ranking, tool-binary lookup, issue search) lives in shell
so it's testable and fast. Everything judgment-based (which findings are real,
confidence tiers, adversarial verification) lives in the markdown and is done by
the model. Do not push reasoning into `detect.sh`, and do not re-implement in prose
what a `detect.sh` subcommand already provides.

**Self-improvement is measured, not learned.** `tests/eval/<lang>/` is a labeled
fixture corpus; eval has two model-free layers. `detect.sh eval <corpus-dir>
<findings-file>` is the **grader** (precision/recall/tp/fp/fn) — it scores a findings
file, it does not run the scan. `detect.sh eval-run <lang>` (wrapper: `scripts/eval-run`)
is the **orchestrator** — itself model-free, it scans each fixture via a *swappable*
runner (`DEFECT_SCAN_EVAL_RUNNER` → `tests/eval/runners/{claude,codex}.sh`, the only
place a model enters), accumulates findings, then grades the split once with `eval`
and aggregates mean/stddev against the per-lang `baseline.{seen,held-out}.txt`.
Improvement happens only via human-reviewed PRs that add fixtures/checks and must not
regress the baseline — there is deliberately **no runtime learning store** (that would
be the P4 prompt-injection surface). The grader + corpus are CODEOWNERS-protected so a
PR can't silently weaken them. See issue #15.

**Five stages** (`SKILL.md` is the orchestrator): detect → triage → tool pass →
reasoning pass → report (→ fix). `--depth N` (default 20) caps how many triaged
files get the expensive reasoning pass — this is the "rabbit-hole floor"; the rest
are tool-scanned only. Coverage is always reported honestly (N of M ranked files).

**Layered profiles, resolved by `name`.** A *profile* (`profiles/<name>.md`) carries
4 frontmatter fields (`name`, `detect_files`, `extensions`, `tools`) plus prose
sections (`## Detection / Toolchain / Reasoning checklist / Auto-fix-safe`).
Profiles are discovered across three layers, low→high precedence:

1. built-in (`skills/scan/profiles/`)
2. user (`~/.config/defect-scan/profiles/`)
3. project (`<repo>/.defect-scan/profiles/`)

Higher layers **shadow by `name`**, and shadowing is **field-by-field**: a profile
that redefines one field inherits the rest from the profile it shadows (`fm_field`
implements this — walk layers high→low, first non-empty value wins). This is what
makes the plugin extensible with zero core edits — see `EXTENDING.md`. Pattern packs
(`patterns/*.md`) layer the same way via `cmd_patterns`.

**Origin gating is a security boundary.** Built-in profiles auto-run their
analyzers. User/project profiles came from a scanned location, so their tools must
be **confirmed with the user before running**, and always resolved via
`detect.sh tool <name>` — never executed as a raw shell string from the profile.
A scanned repo dropping a malicious `tools:` entry is exactly pattern P4 (the RCE
class the scan flags); don't let the scanner become the vector.

## Conventions specific to this repo

- **`detect.sh` is POSIX `sh`, not bash** (`#!/usr/bin/env sh`, `set -eu`). Keep it
  portable: no bashisms, no GNU-only flags. It must scale to large repos — note the
  single-pass churn tally in `cmd_triage` (per-file `git log` was deliberately
  avoided; 16k files = 16k processes). When editing it, preserve that O(history)-once
  property and the BSD-awk `getline`-on-a-directory guard.
- **Cross-platform: macOS (BSD), Linux (GNU), Windows (WSL/Git-Bash).** CI runs the
  bats suite on ubuntu **and** macos — BSD-vs-GNU divergence (e.g. `sed -i`, `head -1`
  vs `-n 1`, `wc` whitespace, awk dialects) is the trap (GNU-green CI can break a Mac).
  `detect.sh preflight` checks required tools. Native Windows has no PowerShell
  re-implementation by design (every subcommand needs `git`, and Git-for-Windows
  bundles `bash`); `windows/defect-scan.ps1` is a thin shim that delegates to that
  bash — keep it a delegator, never a second engine to avoid drift.
- **Frontmatter is parsed by `fm_get`** (a small awk reader), not a YAML lib. Stick
  to the supported shape: scalar keys, comma/space lists normalized to
  space-separated, trailing `# comments` stripped. The block is between the first
  two `---` lines only.
- **Every built-in profile must declare all four `##` sections in order** and valid
  frontmatter — `tests/detect.bats` asserts this. Adding a built-in profile means
  updating the profile list in those tests too.
- **Graceful degradation everywhere.** A missing tool is reported with an install
  hint and the scan continues; a tool *error* (vs "problems found") is marked
  *inconclusive*, never "clean". Reading exit codes correctly is load-bearing
  (eslint `1`=findings vs `2`=usage error; tsc-with-diagnostics, etc.).
- **`cmd_scope` (no-arg `MODE=changes`) must never dead-end silently.** Its fallback
  chain is intentional and tested: uncommitted changes → `git diff HEAD~1` (a normal
  `--no-ff` merge's first-parent diff = the merged work) → last **non-merge** commit's
  diff (the no-op back-merge / post-deploy clean-tree case) → a stderr diagnostic
  pointing at `<path>`/`--full`. Don't collapse this back to a bare `HEAD~1` diff.
- **The local-dev symlink double-loads** with an installed plugin. Remove
  `~/.claude/skills/defect-scan` once the plugin is installed.

## Scope boundaries (and what to hand off)

This skill *finds and reports* defects; it is not a debugger or a PR reviewer. The
`description` in `SKILL.md` deliberately steers users elsewhere: a known bug →
`systematic-debugging`; a diff/PR → `/code-review`; shipping the fixes →
`review-merge-pipeline`. Keep that framing; don't expand the skill into remediation.

`--fix` applies only the `## Auto-fix-safe` subset of the **High** tier and re-runs
the tool to confirm; it **refuses on a dirty working tree** so fixes stay revertable.
Type-checker findings and behavior-changing lint rules are never auto-fixed.

`--file-issues` (Stage 4b) files a tracker issue per **[NEW]** finding — opt-in,
write-gated (needs authenticated `gh`), and **dedup-mandatory**: it requires Stage 4a
correlation (refuses with `--no-correlate`) and only files [NEW], never re-filing a
[LIKELY FILED]/[RELATED]/[VERIFY REGRESSION] match. It reuses the repo's existing
defect/priority labels (via `detect.sh labels`) rather than assuming, and confirms
the batch first. The shell primitives (`issues-create`, `issues-ensure-label`,
`labels`) are dumb create/list helpers — the dedup and label/priority *policy* live
in SKILL.md because they require reasoning over search results, not string matching.

## Shipping work

Use the **global, genericized** commands — do not hand-roll the review/merge/deploy
steps or add repo-local copies:

- **`/review-merge-pipeline`** — run on every finished feature: it code-reviews the
  uncommitted changes, fixes what it finds, commits, pushes, opens a PR, and
  squash-merges. This is the path to ship a change here; it is repo-agnostic and
  detects this repo's conventions.
- **`/deploy`** — promote `dev` → `main` for a production release. Also repo-agnostic;
  it defers to any repo-local runbook (there is none here, so its built-in flow
  applies). Run once work has merged to `dev` and you're ready to release.

After a `--fix` run, defect-scan itself hands off remediation to
`/review-merge-pipeline` rather than shipping fixes directly (see Scope boundaries).

**Releasing → marketplace repin (do BOTH manifests).** After a `/deploy` cuts a new
release `vX.Y.Z`, repin defect-scan in **both** of `stylusnexus/agent-plugins`'
marketplace manifests — they are read by different harnesses and drift silently
(this is what hid defect-scan from Codex; see issue #45):
- `.claude-plugin/marketplace.json` (Claude Code) — entry uses `source: github` + `repo`
  + `ref`. Bump `ref` → `vX.Y.Z`.
- `.agents/plugins/marketplace.json` (Codex) — entry uses `source: url` + `<repo>.git`
  + `ref`, **plus** a `policy` block (`installation: AVAILABLE`) and `category`. Bump
  `ref` → `vX.Y.Z`.
The display name a user sees is separate from the install slug: the slug is the
manifest `name` (`defect-scan`, invoked `defect-scan@stylus-nexus` / `/defect-scan:scan`);
the Codex **display name** ("Defect Scan") comes from this repo's
`.codex-plugin/plugin.json` → `interface.displayName` (Claude title-cases the slug).
release-please bumps the version in BOTH local plugin manifests (`.claude-plugin` and
`.codex-plugin`) via `extra-files` — keep them in sync. agent-plugins has a CI check
(issue #45) that fails if the two marketplace manifests disagree on a plugin's `ref`.

**Repo infrastructure (public-readiness):** `.github/workflows/ci.yml` runs the bats
suite + `sh -n` + a gitleaks secret scan on every PR — keep it green and POSIX-clean.
Releases are automated: `release-please` (`release-please-config.json`,
`.release-please-manifest.json`, `.github/workflows/release-please.yml`) generates
`CHANGELOG.md` and bumps `.claude-plugin/plugin.json` from Conventional Commit titles
when `dev` is deployed to `main` — so **PR titles are the changelog**; never hand-edit
released CHANGELOG sections. Contributor docs: `CONTRIBUTING.md` (add/enhance a
profile, add a pattern), `EXTENDING.md` (private drop-in extension), plus
`SECURITY.md` / `CODE_OF_CONDUCT.md` / issue + PR templates. License: MIT.

## Workspace inheritance

This repo lives locally under `/Applications/Development/Projects`; the workspace
`CLAUDE.md` there applies — notably: feature branches with issue numbers
(`feat/N-name`), Conventional Commit PR titles, never commit directly to `dev`/`main`,
and squash-merge. Design specs and implementation plans for past work are in
`specs/` and `plans/`.

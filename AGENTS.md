# AGENTS.md

Guidance for Codex (and other agents) working **on** the defect-scan repo. To *run*
defect-scan as a tool under Codex instead, see [`codex/README.md`](./codex/README.md).
This mirrors the essentials of [`CLAUDE.md`](./CLAUDE.md) — read that for the full
architecture.

## What this repo is

A Claude Code **plugin** (a defect-hunting skill), not an application. The deliverable
is markdown knowledge (`skills/scan/SKILL.md`, `profiles/`, `patterns/`,
`report-format.md`, `baseline-categories.md`) executed by a model, plus one
POSIX-shell library `skills/scan/lib/detect.sh` for the deterministic plumbing. There
is **no build step**.

## Core rule: keep the harnesses behavior-identical

The scan logic is **shared** across Claude (`skills/scan/SKILL.md`) and Codex
(`codex/defect-scan.md`). Both drive the same `detect.sh` + profiles + patterns.
`detect.sh` and the knowledge files are the single source of truth; the harness files
are thin drivers. A change to scan behavior goes in the shared layer — and if it
changes the pipeline, update **both** drivers. Divergence between harnesses is a bug.

## Commands

```sh
bats tests/detect.bats        # the verification gate — run before shipping (no build step)
bats tests/detect.bats -f "<desc>"   # one test
sh -n skills/scan/lib/detect.sh      # POSIX-shell syntax check
```

## Conventions

- `detect.sh` is strict POSIX `sh` (`set -eu`) — no bashisms, no GNU-only flags;
  keep deterministic logic in shell, judgement/reasoning in the markdown.
- Conventional Commits on PR titles (they become the changelog via release-please at
  deploy). Feature branches `feat/<name>` / `fix/<name>`; PRs target `dev`, never
  commit directly to `dev`/`main`; merge-commit deploys `dev → main`.
- Update docs in lockstep; CI runs `sh -n` + bats + a gitleaks secret scan on every PR.

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) to add/enhance a language profile or a
defect pattern.

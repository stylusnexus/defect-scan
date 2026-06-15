# Contributing to defect-scan

Thanks for helping make defect-scan better. This guide covers local setup, the
conventions we enforce, and — in detail — **how to add a new language**, both
privately for your own use and as a contribution back to the skill.

By participating you agree to abide by our [Code of Conduct](./CODE_OF_CONDUCT.md).
For security issues, do **not** open an issue — see [SECURITY.md](./SECURITY.md).

## TL;DR: two ways to add a language

| You want to… | Do this | Doc |
|---|---|---|
| Support a language **in your own repo / for yourself**, no PR | Drop a profile in `.defect-scan/profiles/` (team) or `~/.config/defect-scan/profiles/` (personal) | **[EXTENDING.md](./EXTENDING.md)** |
| **Contribute** a language as a built-in everyone gets | Add it under `skills/scan/profiles/`, wire a fixture + tests, open a PR | **this file, below** |

The private path needs **zero core edits** and is the right choice most of the time.
Only contribute a built-in when the language is broadly useful.

## Local setup

```sh
git clone https://github.com/stylusnexus/defect-scan
cd defect-scan
./install.sh          # symlinks skills/scan/ → ~/.claude/skills/defect-scan for live iteration
```

Remove that symlink (`rm ~/.claude/skills/defect-scan`) once you install the real
plugin, to avoid a double-load.

### The test gate (there is no build step)

```sh
bats tests/detect.bats           # the whole suite — this is the gate
bats tests/detect.bats -f "scope" # run a subset by description
sh -n skills/scan/lib/detect.sh  # POSIX-shell syntax check
```

Install the runners if needed: `brew install bats-core jq` (the suite uses `jq`).
CI runs exactly these checks on every PR, so green locally ≈ green in CI.

## Conventions

- **Conventional Commits** on PR titles: `type(scope): description` (`feat`, `fix`,
  `docs`, `chore`, `test`, `refactor`, `perf`, `ci`). The CHANGELOG and version bump
  are generated from these by release-please at deploy — so the title is the
  changelog entry. Write it for a reader.
- **Branch naming**: `feat/<short-name>` / `fix/<short-name>` (add an issue number
  when one exists: `feat/123-thing`). Never commit directly to `dev` or `main`; PRs
  target `dev`.
- **`detect.sh` is POSIX `sh`**, `set -eu` — no bashisms, no GNU-only flags; it must
  stay portable and scale to large repos. Keep mechanical/deterministic logic in the
  shell library and judgement/reasoning in the markdown (`SKILL.md`, profiles).
- **Update docs in lockstep** with code (README, help, EXTENDING, SKILL).
- Don't add backwards-compat shims or "removed for X" comments — delete cleanly.

## Contributing a new built-in language profile

A built-in profile is the same file format as a drop-in profile (see EXTENDING.md
for the frontmatter field reference), but it lives in `skills/scan/profiles/` and
must be wired into the test suite so it can't silently regress. Worked end-to-end:

### 1. Create the profile

Copy the template and fill it in:

```sh
cp skills/scan/profiles/TEMPLATE.md.example skills/scan/profiles/ruby.md
```

Every built-in profile **must** declare valid frontmatter (`name`, plus
`detect_files` and/or `extensions`, and `tools`) and the four sections **in this
order**: `## Detection`, `## Toolchain`, `## Reasoning checklist`, `## Auto-fix-safe`.
The test suite asserts this. Example:

```markdown
---
name: ruby
detect_files: Gemfile
extensions: rb
tools: rubocop
---
# Profile: ruby
## Detection
A `Gemfile` or any `.rb` file.
## Toolchain
- `rubocop --format json <files>` — lint/correctness. Install: `gem install rubocop`.
## Reasoning checklist
- cat#2: `rescue` with an empty body / `rescue => e` that swallows the error.
- cat#4: `File.open` without a block; connections never closed.
- ruby-specific: `==` vs `eql?`, mutable default args via `||=`, monkey-patch hazards.
## Auto-fix-safe
Only `rubocop -a` autocorrectable cops in a safe (layout/style) set.
```

Guidance:
- **Toolchain** commands are resolved via `detect.sh tool <name>` (project-local →
  venv → global) and must degrade gracefully (skip-with-hint if absent). Tool output
  is High-confidence; reasoning-only findings go through adversarial verification.
- **Reasoning checklist** should specialize the five baseline categories
  (`skills/scan/baseline-categories.md`) plus language-specific footguns.
- **Auto-fix-safe** lists ONLY tool-applied, behavior-preserving fixes (never
  type-checker output or semantics-changing lint rules).

### 2. Add a fixture

Create a tiny fixture repo under `tests/fixtures/<lang>/` containing the detection
signal (e.g. `tests/fixtures/ruby/Gemfile`) and a small source file. Look at
`tests/fixtures/python/` and `tests/fixtures/dart/` for the shape.

### 3. Wire it into the tests

The suite hardcodes the built-in profile list in a few places — update **all** of
them in `tests/detect.bats` (search for `dart` to find them quickly):

- the **four-sections** test — add your name to `for p in generic python react-typescript dart`
- the **frontmatter** test — add an assertion for your profile's `name`/signals
- add a **detection** test for your fixture, e.g.:
  ```bash
  @test "stacks: detects ruby from Gemfile" {
    run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/ruby"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ruby"* ]]
  }
  ```

### 4. Verify and document

```sh
bats tests/detect.bats        # must be green
```

Update `commands/help.md` (the `--lang` list) if you want it advertised, and mention
the language in `README.md`. Then open a PR to `dev` with a `feat(defect-scan): add
<lang> profile` title.

## Enhancing an existing language profile

Most contributions aren't new languages — they sharpen one we already ship (a
missed reasoning category, a better analyzer, a new file extension). You're editing
`skills/scan/profiles/<lang>.md` in place. Keep these rules:

- **Preserve the structure.** The four sections (`## Detection`, `## Toolchain`,
  `## Reasoning checklist`, `## Auto-fix-safe`) must stay present and in order, and
  the frontmatter must stay valid — the suite asserts both. Don't drop a section
  while editing another.
- **Never rename `name`.** It's the dedupe/shadow key that drop-in profiles inherit
  from and shadow by (see EXTENDING.md). Renaming it silently breaks every user who
  extended that profile. Adding/clarifying prose is always safe; changing keys is not.

Common enhancements:

- **Add a reasoning check** — add a bullet under `## Reasoning checklist`, ideally
  tied to a baseline category (`cat#1`–`cat#5`) or a recurring pattern (`P1`–`P10`).
  No test wiring needed; this is pure model-side knowledge. This is the highest-value,
  lowest-risk contribution.
- **Add or change an analyzer** — add a bullet under `## Toolchain` with the exact
  invocation and an install hint. It must resolve via `detect.sh tool <name>` and
  degrade gracefully (skip-with-hint if absent) — never hard-depend on it. If it's a
  new tool name, prefer adding it to the `tools:` frontmatter list too.
- **Broaden detection** (`detect_files` / `extensions`) — if you add an extension or
  detect-file, **add or extend a fixture** under `tests/fixtures/<lang>/` and a
  detection/triage assertion so the new signal is actually exercised. An added
  extension also widens what triage ranks, so a triage test is worthwhile.
- **Adjust `## Auto-fix-safe`** — only ever list tool-applied, behavior-preserving
  fixes. Promoting a rule into the auto-fix set is a correctness claim; justify it in
  the PR (and never add type-checker output or semantics-changing lint rules).

Always finish with `bats tests/detect.bats` green, and update `README`/`help.md` if
the change is user-visible (e.g. a newly recommended analyzer).

> Just want the tweak for your own repo, not for everyone? Don't edit core — **shadow
> the built-in** with a drop-in profile of the same `name`; field-by-field inheritance
> means you override only what you change. See EXTENDING.md.

## Contributing defect patterns

Recurring, cross-language defect patterns live in `skills/scan/patterns/recurring.md`
(P1–P10). To add one, follow the existing `## P<N>` format and add it to the
`P1 P2 …` assertion list in `tests/detect.bats`. Org- or repo-specific patterns
belong in a drop-in pattern pack instead (see EXTENDING.md) — not in the built-ins.

## Pull requests

Open PRs against `dev`. The PR template's checklist mirrors what reviewers (and CI)
check: tests pass, shell stays POSIX, docs updated, no secrets, conventions followed.
Maintainers squash-merge with a Conventional Commit title.

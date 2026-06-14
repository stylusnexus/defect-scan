# defect-scan Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `defect-scan`, a global, language-aware Claude Code skill that detects latent defects in arbitrary code (file / dir / diff / full repo), runs the real analyzers a stack already has, reasons about what they miss, and reports findings in confidence tiers — fixing the high-confidence tier on `--fix`.

**Architecture:** The defect *knowledge* lives in Markdown (`SKILL.md` orchestration, `profiles/*.md`, `baseline-categories.md`, `report-format.md`) so Claude reads it directly and profiles are drop-in extensible. The deterministic *plumbing* — adaptive scope resolution, stack detection, and project-local-first tool resolution — lives in `lib/detect.sh`, a POSIX shell library with a thin CLI, unit-tested with `bats`. The skill is developed in this git repo (`/Applications/Development/Projects/defect-scan-skill`) and installed globally by symlinking `~/.claude/skills/defect-scan` → the repo, matching how the other global skills are wired.

**Tech Stack:** POSIX `sh` (`lib/detect.sh`), `bats` (tests), `jq` (parse tool JSON), Markdown (skill + profiles). Analyzers invoked at runtime: `ruff`/`mypy` (Python), `tsc`/`eslint` (React/TS) — all resolved project-local-first, skipped-with-hint if absent.

---

## Plain-English summary

We're building a bug-finder you can point at any code. It works out what language it's looking at, runs that language's real bug-checking tools (the ones already installed on the project), then thinks hard about the bug types tools can't catch — and gives you a ranked list with exact locations and proof. By default it only reports. If you ask it to fix, it repairs only the bugs it's sure about and leaves the rest for you.

The plan builds it in two halves. The **plumbing** half (`detect.sh`) is ordinary shell code with real tests: "given this folder, which language is it?", "where's the eslint binary?", "what files am I scanning?". The **knowledge** half is Markdown that tells Claude how to scan, how to rank confidence, and when it's allowed to fix. We test the plumbing automatically; we verify the knowledge half with a set of planted-bug fixtures and a written checklist, because judging a race condition isn't something a shell script can assert.

---

## File structure

```
defect-scan-skill/                 # git repo = source of truth
  SKILL.md                         # orchestration: 4 stages, flags, tiers, --fix safety
  baseline-categories.md           # the 5 cross-cutting defect categories
  report-format.md                 # ranked-findings template + tier definitions
  profiles/
    generic.md                     # fallback: baseline categories, reasoning-only
    python.md                      # ruff/mypy + Python reasoning checklist
    react-typescript.md            # tsc/eslint + React/TS reasoning checklist
  lib/
    detect.sh                      # scope | stacks | tool  (deterministic CLI)
  tests/
    detect.bats                    # unit tests for lib/detect.sh
    fixtures/
      react-ts/   package.json, tsconfig.json, src/Bug.tsx
      python/     pyproject.toml, app/bug.py
      empty/      README.md            (→ generic)
      local-eslint/ node_modules/.bin/eslint (stub), package.json
    scenarios.md                   # manual-verification cases for reasoning/--fix
  install.sh                       # symlink ~/.claude/skills/defect-scan → repo
  specs/2026-06-14-defect-scan-design.md   # (exists)
  plans/2026-06-14-defect-scan.md          # (this file)
```

**`lib/detect.sh` CLI contract** (every later task depends on these exact signatures):

- `detect.sh stacks <dir>` → prints one profile name per line (`react-typescript`, `python`, `generic`); `generic` only when nothing else matched.
- `detect.sh tool <name> [<cwd>]` → prints the resolved absolute invocation path (project-local-first), exit 0; prints nothing, exit 1 if unresolved.
- `detect.sh scope [<target>] [--full] [<cwd>]` → first line `MODE=changes|path|full`, then one repo-relative file path per line.

---

## Task 1: Scaffold repo structure, bats harness, and install script

**Files:**
- Create: `lib/detect.sh`
- Create: `tests/detect.bats`
- Create: `install.sh`
- Create: `.gitignore`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
tests/fixtures/**/node_modules/
*.tmp
.DS_Store
```

- [ ] **Step 2: Create the `lib/detect.sh` skeleton with subcommand dispatch**

```sh
#!/usr/bin/env sh
# detect.sh — deterministic plumbing for the defect-scan skill.
# Subcommands: stacks <dir> | tool <name> [cwd] | scope [target] [--full] [cwd]
set -eu

cmd_stacks() { :; }   # implemented in Task 2
cmd_tool()   { :; }   # implemented in Task 3
cmd_scope()  { :; }   # implemented in Task 4

main() {
  sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    stacks) cmd_stacks "$@" ;;
    tool)   cmd_tool "$@" ;;
    scope)  cmd_scope "$@" ;;
    *) echo "usage: detect.sh {stacks|tool|scope} ..." >&2; return 2 ;;
  esac
}
main "$@"
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x lib/detect.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Write a smoke test in `tests/detect.bats`**

```bash
#!/usr/bin/env bats

setup() {
  DETECT="$BATS_TEST_DIRNAME/../lib/detect.sh"
}

@test "detect.sh prints usage and exits 2 on unknown subcommand" {
  run "$DETECT" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
```

- [ ] **Step 5: Run the smoke test**

Run: `bats tests/detect.bats`
Expected: 1 test, passing.

- [ ] **Step 6: Create `install.sh`**

```sh
#!/usr/bin/env sh
# Install defect-scan globally by symlinking it into ~/.claude/skills/.
set -eu
REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills/defect-scan"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "refusing: $DEST exists and is not a symlink" >&2; exit 1
fi
ln -snf "$REPO" "$DEST"
echo "linked $DEST -> $REPO"
```

- [ ] **Step 7: Make install.sh executable and verify it dry-resolves**

Run: `chmod +x install.sh && sh -n install.sh && echo OK`
Expected: `OK` (syntax check only; we install for real in Task 9).

- [ ] **Step 8: Commit**

```bash
git add lib/detect.sh tests/detect.bats install.sh .gitignore
git commit -m "feat(defect-scan): scaffold detect.sh, bats harness, install script"
```

---

## Task 2: Stack detection (`detect.sh stacks`)

**Files:**
- Modify: `lib/detect.sh` (implement `cmd_stacks`)
- Modify: `tests/detect.bats`
- Create: `tests/fixtures/react-ts/package.json`, `tests/fixtures/react-ts/tsconfig.json`, `tests/fixtures/python/pyproject.toml`, `tests/fixtures/empty/README.md`

- [ ] **Step 1: Create fixtures**

`tests/fixtures/react-ts/package.json`:
```json
{ "name": "fx-react", "dependencies": { "react": "^18.0.0" } }
```
`tests/fixtures/react-ts/tsconfig.json`:
```json
{ "compilerOptions": { "strict": true } }
```
`tests/fixtures/python/pyproject.toml`:
```toml
[project]
name = "fx-python"
version = "0.0.0"
```
`tests/fixtures/empty/README.md`:
```markdown
# empty fixture (no recognized stack)
```

- [ ] **Step 2: Write failing tests in `tests/detect.bats`**

```bash
@test "stacks: detects react-typescript from package.json + tsconfig" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/react-ts"
  [ "$status" -eq 0 ]
  [[ "$output" == *"react-typescript"* ]]
}

@test "stacks: detects python from pyproject.toml" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/python"
  [ "$status" -eq 0 ]
  [[ "$output" == *"python"* ]]
}

@test "stacks: falls back to generic when nothing matches" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/empty"
  [ "$status" -eq 0 ]
  [ "$output" = "generic" ]
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `bats tests/detect.bats`
Expected: the 3 new tests FAIL (cmd_stacks prints nothing).

- [ ] **Step 4: Implement `cmd_stacks`**

```sh
cmd_stacks() {
  root="${1:?usage: detect.sh stacks <dir>}"
  found=""
  # React/TypeScript: a package.json plus either a tsconfig or any .ts/.tsx file.
  if [ -f "$root/package.json" ]; then
    if [ -f "$root/tsconfig.json" ] || \
       find "$root" -type f \( -name '*.ts' -o -name '*.tsx' \) 2>/dev/null | head -1 | grep -q .; then
      found="$found react-typescript"
    fi
  fi
  # Python: pyproject.toml, setup.py, or any .py file.
  if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] || \
     find "$root" -type f -name '*.py' 2>/dev/null | head -1 | grep -q .; then
    found="$found python"
  fi
  [ -n "$found" ] || found="generic"
  for p in $found; do echo "$p"; done
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `bats tests/detect.bats`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/detect.sh tests/detect.bats tests/fixtures
git commit -m "feat(defect-scan): stack detection with generic fallback"
```

---

## Task 3: Project-local-first tool resolution (`detect.sh tool`)

**Files:**
- Modify: `lib/detect.sh` (implement `cmd_tool`)
- Modify: `tests/detect.bats`
- Create: `tests/fixtures/local-eslint/package.json`, `tests/fixtures/local-eslint/node_modules/.bin/eslint`

- [ ] **Step 1: Create a stub project-local binary fixture**

`tests/fixtures/local-eslint/package.json`:
```json
{ "name": "fx-local-eslint" }
```
`tests/fixtures/local-eslint/node_modules/.bin/eslint`:
```sh
#!/usr/bin/env sh
echo "stub-eslint"
```

- [ ] **Step 2: Make the stub executable**

Run: `chmod +x tests/fixtures/local-eslint/node_modules/.bin/eslint`
Expected: no output.

- [ ] **Step 3: Write failing tests**

```bash
@test "tool: prefers project-local node_modules/.bin over global" {
  run "$DETECT" tool eslint "$BATS_TEST_DIRNAME/fixtures/local-eslint"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fixtures/local-eslint/node_modules/.bin/eslint" ]]
}

@test "tool: falls back to global PATH when no local binary" {
  run "$DETECT" tool sh "$BATS_TEST_DIRNAME/fixtures/empty"
  [ "$status" -eq 0 ]
  [ -x "$output" ]
}

@test "tool: exits 1 and prints nothing when unresolved" {
  run "$DETECT" tool no_such_tool_xyz "$BATS_TEST_DIRNAME/fixtures/empty"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
```

- [ ] **Step 4: Run to verify they fail**

Run: `bats tests/detect.bats`
Expected: the 3 new tests FAIL.

- [ ] **Step 5: Implement `cmd_tool`**

```sh
cmd_tool() {
  name="${1:?usage: detect.sh tool <name> [cwd]}"
  cwd="${2:-$PWD}"
  # 1. JS/TS project-local
  if [ -x "$cwd/node_modules/.bin/$name" ]; then
    echo "$cwd/node_modules/.bin/$name"; return 0
  fi
  # 2. Python venv (active env, then project .venv)
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/$name" ]; then
    echo "$VIRTUAL_ENV/bin/$name"; return 0
  fi
  if [ -x "$cwd/.venv/bin/$name" ]; then
    echo "$cwd/.venv/bin/$name"; return 0
  fi
  # 3. Global PATH
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"; return 0
  fi
  return 1
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `bats tests/detect.bats`
Expected: all tests PASS.

- [ ] **Step 7: Add node_modules ignore note and commit**

```bash
git add lib/detect.sh tests/detect.bats tests/fixtures/local-eslint
git commit -m "feat(defect-scan): project-local-first tool resolution"
```

Note: the stub lives under `tests/fixtures/local-eslint/node_modules/.bin/` and must be committed (it is a test fixture, not a real dependency). The `.gitignore` rule from Task 1 ignores `tests/fixtures/**/node_modules/`, so force-add it: `git add -f tests/fixtures/local-eslint/node_modules/.bin/eslint`.

---

## Task 4: Adaptive scope resolution (`detect.sh scope`)

**Files:**
- Modify: `lib/detect.sh` (implement `cmd_scope`)
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing tests using a throwaway git repo**

```bash
@test "scope: --full lists all tracked files, MODE=full" {
  repo="$BATS_TEST_TMPDIR/full"
  mkdir -p "$repo" && cd "$repo" && git init -q
  echo a > a.txt && echo b > b.txt && git add . && git -c user.email=t@t -c user.name=t commit -qm init
  run "$DETECT" scope "" --full "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "MODE=full" ]]
  [[ "$output" == *"a.txt"* && "$output" == *"b.txt"* ]]
}

@test "scope: a path argument yields MODE=path and files under it" {
  repo="$BATS_TEST_TMPDIR/pathmode"
  mkdir -p "$repo/sub" && cd "$repo" && git init -q
  echo x > sub/x.py && git add . && git -c user.email=t@t -c user.name=t commit -qm init
  run "$DETECT" scope "sub" "" "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "MODE=path" ]]
  [[ "$output" == *"sub/x.py"* ]]
}

@test "scope: no arg yields MODE=changes from uncommitted edits" {
  repo="$BATS_TEST_TMPDIR/changes"
  mkdir -p "$repo" && cd "$repo" && git init -q
  echo one > f.txt && git add . && git -c user.email=t@t -c user.name=t commit -qm init
  echo two >> f.txt           # uncommitted modification
  echo new > g.txt            # untracked
  run "$DETECT" scope "" "" "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "MODE=changes" ]]
  [[ "$output" == *"f.txt"* && "$output" == *"g.txt"* ]]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/detect.bats`
Expected: the 3 new tests FAIL.

- [ ] **Step 3: Implement `cmd_scope`**

```sh
cmd_scope() {
  target=""; full=""; cwd=""
  # positional: [target] [--full|""] [cwd]; tolerate --full in any slot
  for a in "$@"; do
    case "$a" in
      --full) full="1" ;;
      "") : ;;
      *) if [ -z "$target" ] && [ ! -d "$a" ] && [ ! -f "$a" ] && [ -z "$cwd" ]; then
           target="$a"
         elif [ -d "$a" ] && [ -z "$cwd" ] && [ "$a" != "$target" ]; then
           cwd="$a"
         elif [ -z "$target" ]; then target="$a"
         else cwd="$a"; fi ;;
    esac
  done
  cwd="${cwd:-$PWD}"
  cd "$cwd" || return 1

  if [ -n "$full" ]; then
    echo "MODE=full"; git ls-files; return 0
  fi
  if [ -n "$target" ]; then
    echo "MODE=path"
    if [ -d "$target" ]; then git ls-files -- "$target"; else echo "$target"; fi
    return 0
  fi
  echo "MODE=changes"
  if ! git rev-parse --git-dir >/dev/null 2>&1; then return 1; fi
  changed="$(git diff --name-only; git diff --cached --name-only; \
             git ls-files --others --exclude-standard)"
  if [ -z "$changed" ]; then
    changed="$(git diff --name-only HEAD~1 2>/dev/null || true)"
  fi
  printf '%s\n' "$changed" | sort -u | sed '/^$/d'
}
```

Note: the positional parser is fiddly because tests pass `scope "" --full "$repo"` and `scope "sub" "" "$repo"`. The dispatcher in `main()` already `shift`s off the subcommand, so `cmd_scope` receives only these three slots. Keep the parser as written; the tests pin its behavior.

- [ ] **Step 4: Run to verify they pass**

Run: `bats tests/detect.bats`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/detect.bats
git commit -m "feat(defect-scan): adaptive scope resolution (changes/path/full)"
```

---

## Task 5: Baseline categories and report format (Markdown)

**Files:**
- Create: `baseline-categories.md`
- Create: `report-format.md`
- Modify: `tests/detect.bats` (structure assertions)

- [ ] **Step 1: Write `baseline-categories.md`**

```markdown
# Baseline Defect Categories

These five categories are cross-cutting. Every profile references this file and
specializes each category to its language.

## 1. Null / undefined & unchecked returns
Null/undefined dereferences, ignored error returns, unchecked `Optional`/`nil`,
accessing a value that a prior call may have failed to produce.

## 2. Silent failures & swallowed errors
Empty catch blocks, `except: pass`, log-and-continue where the caller needed the
error, ignored return/status codes, swallowed promise rejections.

## 3. Injection & untrusted input
SQL injection, command injection, path traversal, XSS, unsanitized input reaching
an interpreter, a shell, a file path, or the DOM.

## 4. Resource leaks
Unclosed files/sockets/connections/handles, missing `finally`/`defer`/`with`/
`using`, leaked subscriptions/listeners/timers.

## 5. Concurrency hazards
Data races, unsynchronized shared mutable state, await/lock misuse, check-then-act
races, deadlock-prone lock ordering.

Each finding cites the category number so the report can group by it.
```

- [ ] **Step 2: Write `report-format.md`**

```markdown
# Report Format & Confidence Tiers

## Confidence tiers
- **High** — tool-confirmed (an analyzer flagged it with a named rule) OR a
  reasoning finding that survived adversarial verification with a clear repro
  path. Eligible for `--fix`.
- **Medium** — credible reasoning finding with no ground-truth signal. Reported,
  never auto-fixed unless `--fix-all`.
- **Low** — possible/stylistic. Listed in a collapsed appendix.

## Header (always printed first)
```
defect-scan — <target> (MODE=<changes|path|full>)
Stacks: <profiles>   Tools run: <list>   Tools missing: <list + install hint>
Findings: High <n> · Medium <n> · Low <n>
```
If a tool was missing, the header says so — never imply clean coverage.

## Per-finding line
```
[<SEVERITY>] (<tier>) <file>:<line> · cat#<n> <short title>
  evidence:  <one line: the rule id, or the reasoning + why it survives>
  fix:       <one-line suggested remedy>
```
Sorted High→Low, then by severity. Low tier goes under a `<details>`-style
"Low-confidence appendix" heading.
```

- [ ] **Step 3: Write structure tests**

```bash
@test "baseline-categories.md defines all five categories" {
  f="$BATS_TEST_DIRNAME/../baseline-categories.md"
  for n in 1 2 3 4 5; do grep -qE "^## $n\." "$f"; done
}

@test "report-format.md defines all three tiers" {
  f="$BATS_TEST_DIRNAME/../report-format.md"
  grep -qi "High" "$f"; grep -qi "Medium" "$f"; grep -qi "Low" "$f"
}
```

- [ ] **Step 4: Run tests**

Run: `bats tests/detect.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add baseline-categories.md report-format.md tests/detect.bats
git commit -m "docs(defect-scan): baseline categories and report format"
```

---

## Task 6: Profiles (generic, python, react-typescript)

**Files:**
- Create: `profiles/generic.md`, `profiles/python.md`, `profiles/react-typescript.md`
- Modify: `tests/detect.bats` (each profile declares the 4 required sections)

Each profile MUST contain these four `##` sections, in this order: `## Detection`,
`## Toolchain`, `## Reasoning checklist`, `## Auto-fix-safe`. The structure test
pins exactly that.

- [ ] **Step 1: Write `profiles/generic.md`**

```markdown
# Profile: generic (fallback)

## Detection
Selected when no language-specific profile matches. See `detect.sh stacks`.

## Toolchain
None. Reasoning-only against `baseline-categories.md`.

## Reasoning checklist
Walk all five baseline categories. With no tool ground truth, every finding here
is at most Medium unless adversarial verification produces a clear repro path.

## Auto-fix-safe
Nothing is auto-fix-safe in the generic profile (no tool confirmation available).
```

- [ ] **Step 2: Write `profiles/python.md`**

```markdown
# Profile: python

## Detection
`pyproject.toml`, `setup.py`, or any `*.py`. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>` (venv-first, then global). Skip-with-hint
if unresolved.
- `ruff check --output-format=json <files>`  — lint/correctness rules.
- `mypy --no-error-summary <files>`           — type errors.
Install hints: `pip install ruff mypy` (or `uv pip install ruff mypy`).

## Reasoning checklist
Baseline categories specialized:
- cat#1: unchecked `dict[...]`/attribute access, functions that may return `None`.
- cat#2: bare `except:` / `except Exception: pass`, swallowed errors.
- cat#3: f-string/`%`-built SQL, `subprocess(..., shell=True)`, `os.system`.
- cat#4: files/sockets opened without `with`, sessions not closed.
- cat#5: shared state without locks, `asyncio` blocking calls, mutable default args.
Python-specific: `==` vs `is` for identity, mutable default arguments,
late-binding closures in loops, `assert` used for runtime validation.

## Auto-fix-safe
Only `ruff`-confirmed rules with an autofix (`ruff check --fix` applies them) AND
the rule is in the safe set: bare-except → named except is NOT auto-safe (changes
semantics); unused-import / f-string-without-placeholder ARE. Type findings from
`mypy` are never auto-fixed (require human-chosen types).
```

- [ ] **Step 3: Write `profiles/react-typescript.md`**

```markdown
# Profile: react-typescript

## Detection
`package.json` plus a `tsconfig.json` or any `*.ts`/`*.tsx`. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name> <project-dir>` (node_modules/.bin first,
then global). Skip-with-hint if unresolved.
- `tsc --noEmit`                              — type errors.
- `eslint --format json <files>`              — lint/correctness rules.
Install hints: `npm i -D typescript eslint`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: non-null assertions (`!`), `any` escapes hiding null, optional chaining gaps.
- cat#2: empty `catch {}`, `.catch(() => {})`, unhandled promise rejections.
- cat#3: `dangerouslySetInnerHTML` with non-sanitized input, `href`/`src` from input.
- cat#4: `useEffect` subscriptions/timers/listeners without cleanup return.
- cat#5: stale closures over state, `useEffect` missing/incorrect deps, setState in
  render, race between async effect and unmount.
React-specific: missing `key` in lists, conditional hook calls, derived-state-in-
effect anti-pattern, hydration mismatches (non-deterministic render output).

## Auto-fix-safe
Only `eslint`-confirmed rules invoked with `--fix` AND in the safe set
(`react-hooks/exhaustive-deps` is NOT auto-safe — it can change behavior; formatting
and unused-var removals ARE). `tsc` findings are never auto-fixed.
```

- [ ] **Step 4: Write structure tests**

```bash
@test "every profile declares the four required sections in order" {
  for p in generic python react-typescript; do
    f="$BATS_TEST_DIRNAME/../profiles/$p.md"
    [ -f "$f" ]
    grep -qE '^## Detection'         "$f"
    grep -qE '^## Toolchain'         "$f"
    grep -qE '^## Reasoning checklist' "$f"
    grep -qE '^## Auto-fix-safe'     "$f"
  done
}
```

- [ ] **Step 5: Run tests**

Run: `bats tests/detect.bats`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add profiles tests/detect.bats
git commit -m "docs(defect-scan): v1 profiles (generic, python, react-typescript)"
```

---

## Task 7: SKILL.md orchestration

**Files:**
- Create: `SKILL.md`
- Modify: `tests/detect.bats` (front-matter + required-sections assertions)

- [ ] **Step 1: Write `SKILL.md`**

````markdown
---
name: defect-scan
description: Use to hunt latent defects in code — a file, directory, diff, or whole repo. Detects the stack, runs that language's real analyzers (ruff/mypy, tsc/eslint), reasons about defects tools miss, and reports findings in confidence tiers. Report-only by default; --fix applies the high-confidence tier. Use when asked to scan/audit code for bugs, find defects, or check a codebase for problems (not for debugging a known bug — use systematic-debugging — and not for reviewing a diff/PR — use /code-review).
---

# defect-scan

Language-aware defect hunter. Four stages: **detect → tool pass → reasoning pass →
report (→ fix)**. The deterministic plumbing is `lib/detect.sh`; the defect
knowledge is in `profiles/`, `baseline-categories.md`, and `report-format.md`.

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

## Stage 2 — Tool pass
For each profile, read its `## Toolchain`. Resolve every tool with
`lib/detect.sh tool <name> <project-dir>`. If a tool resolves, run it on the
in-scope files and capture structured output (`jq` for JSON). If it does not
resolve, record it as **missing** with the profile's install hint and continue —
never abort the scan. If a tool crashes or times out, capture stderr, mark that
check **inconclusive**, and continue.

## Stage 3 — Reasoning pass
Read the in-scope files against the profile's `## Reasoning checklist` and
`baseline-categories.md`. For EVERY reasoning-only finding, run an **adversarial
verification** pass before ranking: state the strongest case that the finding is
NOT a real defect (guard exists elsewhere, input is trusted, path unreachable).
- Survives with a clear repro path → eligible for **High**.
- Survives but no clear repro → **Medium**.
- Refuted → drop it (or **Low** if genuinely ambiguous).
Tool-confirmed findings are **High** by definition.

## Stage 4 — Report (→ fix)
Merge tool + reasoning findings, dedupe by `file:line + category`, rank by
tier then severity, and emit using `report-format.md`. Always print the header
with tools-run vs tools-missing.

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
````

- [ ] **Step 2: Write SKILL.md structure tests**

```bash
@test "SKILL.md has name and description front matter" {
  f="$BATS_TEST_DIRNAME/../SKILL.md"
  grep -qE '^name: defect-scan$' "$f"
  grep -qE '^description: ' "$f"
}

@test "SKILL.md documents all four stages and the fix-safety gate" {
  f="$BATS_TEST_DIRNAME/../SKILL.md"
  grep -q "Stage 1 — Detect" "$f"
  grep -q "Stage 2 — Tool pass" "$f"
  grep -q "Stage 3 — Reasoning pass" "$f"
  grep -q "Stage 4 — Report" "$f"
  grep -qi "Refuse if the working tree is dirty" "$f"
  grep -qi "adversarial verification" "$f"
}
```

- [ ] **Step 3: Run tests**

Run: `bats tests/detect.bats`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md tests/detect.bats
git commit -m "feat(defect-scan): SKILL.md orchestration (4 stages, fix safety)"
```

---

## Task 8: Planted-bug fixtures and manual-verification scenarios

The reasoning and `--fix` behaviors depend on Claude's judgment and cannot be
asserted by `bats`. This task creates the fixtures and a written checklist that a
human (or a verifying agent) runs once after install. The one deterministic case
(`ruff` flags a real bug) IS auto-tested.

**Files:**
- Create: `tests/fixtures/python/app/bug.py`, `tests/fixtures/react-ts/src/Bug.tsx`
- Create: `tests/scenarios.md`
- Modify: `tests/detect.bats`

- [ ] **Step 1: Create the Python planted-bug fixture**

`tests/fixtures/python/app/bug.py`:
```python
def load(path):
    try:
        f = open(path)          # cat#4: never closed
        return f.read()
    except:                     # cat#2: bare except swallows everything
        pass                    # ruff: E722 (bare-except), tool-confirmable
```

- [ ] **Step 2: Create the React/TS planted-bug fixture**

`tests/fixtures/react-ts/src/Bug.tsx`:
```tsx
import { useEffect, useState } from "react";

export function Timer({ ms }: { ms: number }) {
  const [n, setN] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setN(n + 1), ms);  // cat#5: stale closure on n
    // cat#4: no cleanup — interval leaks on unmount
  }, []);                                            // cat#5: missing dep `ms`, `n`
  return <span>{n}</span>;
}
```

- [ ] **Step 3: Auto-test the deterministic case (ruff flags the bare-except)**

Add to `tests/detect.bats` (skips cleanly if ruff is unavailable, so CI without
ruff still passes):
```bash
@test "ruff flags the planted bare-except in the python fixture" {
  tool="$("$DETECT" tool ruff "$BATS_TEST_DIRNAME/fixtures/python" || true)"
  [ -n "$tool" ] || skip "ruff not installed"
  run "$tool" check --select E722 --output-format=json \
      "$BATS_TEST_DIRNAME/fixtures/python/app/bug.py"
  [[ "$output" == *"E722"* ]]
}
```

- [ ] **Step 4: Write `tests/scenarios.md` (manual verification checklist)**

```markdown
# Manual verification scenarios

Run after `./install.sh`. Each is a behavior the automated tests cannot assert.

1. **Python tool-confirmed (High).** `/defect-scan tests/fixtures/python`
   → reports the bare-except (cat#2) as **High, tool-confirmed (ruff E722)**, and
   the unclosed file (cat#4) at least Medium.
2. **React reasoning (Medium/High).** `/defect-scan tests/fixtures/react-ts`
   → reports the leaked interval (cat#4) and the stale closure / missing deps
   (cat#5). exhaustive-deps may be tool-confirmed if eslint+plugin present.
3. **Adversarial refutation.** Point the scan at a file where a guard clause makes
   a suspected null-deref unreachable → the finding must be **dropped or Low**, not
   reported as High. (Plant one when testing.)
4. **Missing toolchain.** Temporarily rename `ruff` off PATH and re-run scenario 1
   → scan still completes; header lists ruff under "Tools missing" with an install
   hint; the bare-except now appears as a **reasoning** finding, not tool-confirmed.
5. **--fix safety on dirty tree.** With uncommitted changes present, `--fix`
   → refuses and explains; after committing, `--fix` applies only Auto-fix-safe
   High items and re-runs the tool to confirm.
6. **Generic fallback.** `/defect-scan tests/fixtures/empty` → uses the generic
   profile, reasoning-only, nothing ranked above Medium.
```

- [ ] **Step 5: Run the full suite**

Run: `bats tests/detect.bats`
Expected: all PASS (the ruff test passes or skips).

- [ ] **Step 6: Commit**

```bash
git add -f tests/fixtures/python/app/bug.py tests/fixtures/react-ts/src/Bug.tsx
git add tests/scenarios.md tests/detect.bats
git commit -m "test(defect-scan): planted-bug fixtures + manual scenarios"
```

---

## Task 9: Install globally and smoke-test

**Files:**
- Modify: none (runs `install.sh`)
- Create: `README.md`

- [ ] **Step 1: Write a short `README.md`**

```markdown
# defect-scan

Language-aware defect-finding skill for Claude Code. See `specs/` for the design,
`plans/` for the build plan. Install: `./install.sh` (symlinks into
`~/.claude/skills/defect-scan`). Run tests: `bats tests/detect.bats`.
```

- [ ] **Step 2: Run the installer**

Run: `./install.sh`
Expected: `linked /Users/.../.claude/skills/defect-scan -> /Applications/Development/Projects/defect-scan-skill`

- [ ] **Step 3: Verify the symlink resolves to the skill**

Run: `ls -l ~/.claude/skills/defect-scan && head -3 ~/.claude/skills/defect-scan/SKILL.md`
Expected: symlink shown; SKILL.md front matter prints (`name: defect-scan`).

- [ ] **Step 4: Smoke-test the deterministic CLI end to end**

Run: `~/.claude/skills/defect-scan/lib/detect.sh stacks tests/fixtures/python`
Expected: prints `python`.

- [ ] **Step 5: Run the full test suite one final time**

Run: `bats tests/detect.bats`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(defect-scan): README + global install"
```

- [ ] **Step 7: Manual verification**

Open a new Claude Code session and run `/defect-scan --help`, then work through
`tests/scenarios.md`. The skill is done when scenarios 1, 2, 4, 5, and 6 behave as
written.

---

## Self-review

**Spec coverage check** (each spec section → task):
- Scope & invocation (adaptive, flags) → Task 4 (scope), Task 7 (flags in SKILL.md). ✓
- Architecture 4 stages → Task 7 SKILL.md; plumbing in Tasks 2–4. ✓
- Components (file layout) → File-structure section + Tasks 5–7. ✓
- Five baseline categories → Task 5 (`baseline-categories.md`), specialized in Task 6. ✓
- Profile specializations (React/TS, Python) + toolchains → Task 6. ✓
- Project-local-first tool resolution (the spec-review refinement) → Task 3. ✓
- Confidence tiers (High/Medium/Low + adversarial verification) → Task 5 (`report-format.md`), Task 7 (Stage 3). ✓
- Output / report-format / honest-about-coverage header → Task 5, Task 7 Stage 4. ✓
- Error handling (no stack, tool missing, tool crash, --fix no-op, dirty-tree refusal) → Task 7 (Stages 2 & 4), Task 8 scenario 4–5. ✓
- Testing (the spec's plain-English cases) → Tasks 2–4 (detection/resolution/scope), Task 8 (planted bugs, missing-tool, --fix, refutation, generic). ✓
- Naming-family / Markdown-not-code decisions → reflected in file structure (profiles are `.md`). ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N" — every code and test step has complete content. ✓

**Type/contract consistency:** `detect.sh` subcommands (`stacks <dir>`, `tool <name> [cwd]`, `scope [target] [--full] [cwd]`) are defined identically in the File-structure contract, implemented in Tasks 2–4, and called with those exact signatures in Task 7's SKILL.md and Task 9's smoke test. Profile section names (`## Detection`, `## Toolchain`, `## Reasoning checklist`, `## Auto-fix-safe`) match between Task 6 content and the Task 6 structure test. Confidence tier names (High/Medium/Low) match across Tasks 5, 7, 8. ✓

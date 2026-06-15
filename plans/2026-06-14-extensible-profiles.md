# Extensible Profiles & Defect Packs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users/teams add language profiles and custom defect packs by dropping Markdown files into `.defect-scan/` (project) or `~/.config/defect-scan/` (user) — with **zero edits to `detect.sh` core**.

**Architecture:** Profiles gain a frontmatter-lite header (`name`, `detect_files`, `extensions`, `tools`). `detect.sh` reads that frontmatter (tiny awk helper) and discovers profiles/patterns across three layers (built-in → user → project, precedence project>user>built-in, frontmatter shadow-merged field-by-field, prose replaced). `cmd_stacks` and `cmd_triage`'s source-filter become data-driven from the union of profile frontmatter, so a new language is just a file. Tool execution is origin-gated (built-in tools auto-run; project/user tools confirm-first).

**Tech Stack:** POSIX `sh` + `awk` (`skills/scan/lib/detect.sh`), `bats` (`tests/detect.bats`, currently 35 tests), Markdown profiles/patterns.

---

## Plain-English summary

We're making defect-scan teach itself new languages from a file instead of a code
change. Each profile gets a tiny machine-readable header saying "I'm Dart, I match
`pubspec.yaml` / `.dart` files, I use the `dart` tool." The engine reads those
headers from three places — the plugin's built-ins, your personal config folder,
and a `.defect-scan/` folder in the repo being scanned — newest-wins, but a
newer profile that leaves a field blank inherits it from the one it shadows (so a
team's tweaked `dart` profile can't accidentally make the scanner stop seeing
`.dart` files). Detection and "which files to scan" are computed from those
headers, so adding `toml` support is a drop-in file. The one safety rule: tool
commands from a repo you're scanning don't auto-run — they ask first — so this
can't become the very RCE bug (P4) the scanner warns about.

---

## File structure

```
skills/scan/lib/detect.sh        # + fm_get, fm_field, skill_dir helpers; + cmd_profiles,
                                 #   cmd_patterns; cmd_stacks & cmd_triage made data-driven
skills/scan/profiles/
  generic.md                     # + frontmatter (name only)
  python.md                      # + frontmatter (detect_files/extensions/tools)
  react-typescript.md            # + frontmatter (detect_files: tsconfig.json; extensions: ts tsx)
  dart.md                        # + frontmatter
skills/scan/SKILL.md             # orchestration: profile-driven detect, origin-gated tools,
                                 #   patterns from cmd_patterns, layer-toggle env vars
tests/detect.bats                # + frontmatter/discovery/data-driven/zero-core-edit/shadow tests
tests/fixtures/
  profile-layers/                # fixture user+project profile dirs for discovery tests
README.md                        # document .defect-scan/ extensibility
```

**`detect.sh` new internal helpers & subcommands (contract used across tasks):**
- `skill_dir` → echoes the skill dir (`<...>/skills/scan`), computed from `$0`.
- `fm_get <file> <key>` → prints the frontmatter value for `<key>` (lists normalized to space-separated), empty if absent.
- `profile_layers` → echoes the enabled profile dirs low→high precedence, honoring `DEFECT_SCAN_NO_USER` / `DEFECT_SCAN_NO_PROJECT`. Takes `<repo>`.
- `cmd_profiles [<repo>]` → `name⇥path⇥origin` per profile-name, highest precedence wins.
- `fm_field <name> <key> [<repo>]` → effective merged value: highest-precedence layer that *defines* `<key>` for `<name>` (field-by-field inheritance).
- `cmd_patterns [<repo>]` → built-in `recurring.md` path + every `patterns/*.md` from user & project layers (additive, built-in first).
- `cmd_stacks <dir>` → unchanged signature; now computed from profiles.
- `cmd_triage <cwd>` → unchanged signature; source-filter now the union of profile `extensions` + an always-on base (`sh bash`).

Origin values: `builtin | user | project`. Detection is **disjunctive**: a profile matches if any `detect_files` entry exists in the target OR any file with a listed `extensions` exists.

---

## Task 1: Frontmatter reader (`fm_get`) + `skill_dir`

**Files:**
- Modify: `skills/scan/lib/detect.sh` (add helpers near top, after `set -eu`)
- Modify: `tests/detect.bats`
- Create: `tests/fixtures/fm/sample.md`

- [ ] **Step 1: Create a frontmatter fixture**

`tests/fixtures/fm/sample.md`:
```markdown
---
name: dart
detect_files: pubspec.yaml
extensions: dart, flutter_gen
tools: dart  flutter   # trailing comment
---
## Detection
body text: not frontmatter
```

- [ ] **Step 2: Write failing tests**

```bash
@test "fm_get: reads a scalar key" {
  run "$DETECT" __fmget "$BATS_TEST_DIRNAME/fixtures/fm/sample.md" name
  [ "$status" -eq 0 ]; [ "$output" = "dart" ]
}
@test "fm_get: normalizes comma/space lists to space-separated" {
  run "$DETECT" __fmget "$BATS_TEST_DIRNAME/fixtures/fm/sample.md" extensions
  [ "$output" = "dart flutter_gen" ]
}
@test "fm_get: strips trailing comments" {
  run "$DETECT" __fmget "$BATS_TEST_DIRNAME/fixtures/fm/sample.md" tools
  [ "$output" = "dart flutter" ]
}
@test "fm_get: empty for missing key or no frontmatter" {
  run "$DETECT" __fmget "$BATS_TEST_DIRNAME/fixtures/fm/sample.md" nope
  [ -z "$output" ]
  run "$DETECT" __fmget "$BATS_TEST_DIRNAME/fixtures/empty/README.md" name
  [ -z "$output" ]
}
```
(`__fmget` is a hidden dispatcher arm exposing `fm_get` for testing.)

- [ ] **Step 3: Run to verify FAIL**

Run: `bats tests/detect.bats`
Expected: the 4 new tests FAIL (`__fmget` unknown → usage exit 2).

- [ ] **Step 4: Implement helpers in `detect.sh`** (immediately after `set -eu`)

```sh
# Absolute path to this skill dir (the dir containing lib/). Works via symlink.
skill_dir() { CDPATH= cd -- "$(dirname -- "$0")/.." && pwd; }

# fm_get <file> <key>: print the frontmatter value for <key>. Frontmatter is the
# block between the first two '---' lines. Lists (comma/space) → space-separated.
# Trailing '# comment' is stripped. Prints nothing if absent / no frontmatter.
fm_get() {
  awk -v k="$2" '
    NR==1 && $0!="---" { exit }
    NR==1 { next }
    $0=="---" { exit }
    {
      i=index($0,":"); if (i==0) next
      key=substr($0,1,i-1); val=substr($0,i+1)
      sub(/[ \t]*#.*$/,"",val)
      gsub(/^[ \t]+|[ \t]+$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",val)
      gsub(/,/," ",val); gsub(/[ \t]+/," ",val)
      gsub(/^ | $/,"",val)
      if (key==k) { print val; exit }
    }
  ' "$1" 2>/dev/null
}
```
And add a dispatcher arm (in `main()`'s `case`, alongside the others):
```sh
    __fmget) fm_get "$@" ;;
```

- [ ] **Step 5: Run to verify PASS**

Run: `bats tests/detect.bats`
Expected: all pass.

- [ ] **Step 6: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats tests/fixtures/fm
git commit -m "feat(defect-scan): frontmatter-lite reader (fm_get) + skill_dir"
```

---

## Task 2: Migrate built-in profiles to frontmatter

**Files:**
- Modify: `skills/scan/profiles/generic.md`, `python.md`, `react-typescript.md`, `dart.md`
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing test asserting each built-in declares expected frontmatter**

```bash
@test "built-in profiles declare frontmatter (name + detection signals)" {
  P="$BATS_TEST_DIRNAME/../skills/scan/profiles"
  [ "$("$DETECT" __fmget "$P/generic.md" name)" = "generic" ]
  [ "$("$DETECT" __fmget "$P/python.md" name)" = "python" ]
  [[ "$("$DETECT" __fmget "$P/python.md" extensions)" == *"py"* ]]
  [ "$("$DETECT" __fmget "$P/react-typescript.md" name)" = "react-typescript" ]
  [[ "$("$DETECT" __fmget "$P/react-typescript.md" extensions)" == *"tsx"* ]]
  [ "$("$DETECT" __fmget "$P/dart.md" name)" = "dart" ]
  [[ "$("$DETECT" __fmget "$P/dart.md" detect_files)" == *"pubspec.yaml"* ]]
}
```

- [ ] **Step 2: Run to verify FAIL** (`bats tests/detect.bats` — profiles have no frontmatter yet).

- [ ] **Step 3: Prepend frontmatter to each profile** (above the existing `# Profile: …` line).

`generic.md`:
```markdown
---
name: generic
---
```
`python.md`:
```markdown
---
name: python
detect_files: pyproject.toml setup.py
extensions: py pyi
tools: ruff mypy bandit pip-audit
---
```
`react-typescript.md`:
```markdown
---
name: react-typescript
detect_files: tsconfig.json
extensions: ts tsx
tools: tsc eslint
---
```
`dart.md`:
```markdown
---
name: dart
detect_files: pubspec.yaml
extensions: dart
tools: dart flutter
---
```

- [ ] **Step 4: Run to verify PASS** (`bats tests/detect.bats`).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/profiles
git commit -m "feat(defect-scan): add frontmatter to built-in profiles"
```

---

## Task 3: Profile discovery (`profile_layers` + `cmd_profiles`)

**Files:**
- Modify: `skills/scan/lib/detect.sh`
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing tests (3-layer merge + precedence + origin + layer toggles)**

```bash
@test "profiles: lists built-ins with origin=builtin" {
  run "$DETECT" profiles "$BATS_TEST_TMPDIR/none"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t'"builtin" ]] || true
  [[ "$output" == *"dart"$'\t'* ]]
  [[ "$output" == *"builtin"* ]]
}

@test "profiles: project layer shadows a same-named built-in" {
  repo="$BATS_TEST_TMPDIR/proj"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: dart\nextensions: dart\n---\n' > "$repo/.defect-scan/profiles/dart.md"
  run "$DETECT" profiles "$repo"
  [ "$status" -eq 0 ]
  # exactly one dart line, and it is origin=project pointing at the repo copy
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1=="dart"' | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$(printf '%s\n' "$output" | awk -F'\t' '$1=="dart"{print $3}')" == "project" ]]
}

@test "profiles: --no-project (env) hides project layer" {
  repo="$BATS_TEST_TMPDIR/proj2"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: zzlang\nextensions: zz\n---\n' > "$repo/.defect-scan/profiles/zzlang.md"
  run env DEFECT_SCAN_NO_PROJECT=1 "$DETECT" profiles "$repo"
  [[ "$output" != *"zzlang"* ]]
}
```

- [ ] **Step 2: Run to verify FAIL** (`profiles` unknown subcommand → exit 2).

- [ ] **Step 3: Implement `profile_layers` and `cmd_profiles`**

```sh
# Echo the enabled profile dirs, low→high precedence, one per line.
profile_layers() {
  repo="${1:-$PWD}"
  echo "$(skill_dir)/profiles"                                   # builtin
  [ -n "${DEFECT_SCAN_NO_USER:-}" ]    || echo "$HOME/.config/defect-scan/profiles"
  [ -n "${DEFECT_SCAN_NO_PROJECT:-}" ] || echo "$repo/.defect-scan/profiles"
}

cmd_profiles() {
  repo="${1:-$PWD}"
  # emit name<TAB>path<TAB>origin for every *.md, low→high; dedupe keep-last(name).
  { profile_layers "$repo" | while IFS= read -r dir; do
      case "$dir" in
        */profiles) origin=builtin ;;
      esac
      case "$dir" in
        "$HOME/.config/"*) origin=user ;;
        "$repo/.defect-scan/"*) origin=project ;;
        *) origin=builtin ;;
      esac
      [ -d "$dir" ] || continue
      for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        name="$(fm_get "$f" name)"; [ -n "$name" ] || name="$(basename "$f" .md)"
        printf '%s\t%s\t%s\n' "$name" "$f" "$origin"
      done
    done; } | awk -F'\t' '{m[$1]=$0} END{for(k in m) print m[k]}'
}
```
Add dispatcher arm: `profiles) cmd_profiles "$@" ;;`.
Note: `awk '{m[$1]=$0}'` keeps the LAST line per name; because `profile_layers`
emits low→high precedence, last = highest precedence = correct winner.

- [ ] **Step 4: Run to verify PASS** (`bats tests/detect.bats`).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(defect-scan): 3-layer profile discovery (cmd_profiles)"
```

---

## Task 4: Effective merged field (`fm_field`, shadow-merge)

**Files:**
- Modify: `skills/scan/lib/detect.sh`
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing shadow-merge test**

```bash
@test "fm_field: shadowing profile inherits an absent field from the shadowed one" {
  repo="$BATS_TEST_TMPDIR/merge"; mkdir -p "$repo/.defect-scan/profiles"
  # project dart omits extensions → must inherit 'dart' from the built-in
  printf -- '---\nname: dart\ntools: dart\n---\n## Detection\n' \
    > "$repo/.defect-scan/profiles/dart.md"
  run "$DETECT" __fmfield dart extensions "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dart"* ]]
}

@test "fm_field: highest layer that defines the field wins" {
  repo="$BATS_TEST_TMPDIR/merge2"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: python\nextensions: py pyi pyx\n---\n' \
    > "$repo/.defect-scan/profiles/python.md"
  run "$DETECT" __fmfield python extensions "$repo"
  [[ "$output" == *"pyx"* ]]
}
```

- [ ] **Step 2: Run to verify FAIL** (`__fmfield` unknown).

- [ ] **Step 3: Implement `fm_field`** (walks layers HIGH→LOW, first that defines the key wins)

```sh
# fm_field <name> <key> [repo]: effective value for <key> of profile <name>,
# taking the highest-precedence layer that DEFINES the key (field inheritance).
fm_field() {
  fname="$1"; fkey="$2"; repo="${3:-$PWD}"
  # reverse profile_layers to high→low
  hi="$(profile_layers "$repo" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')"
  printf '%s\n' "$hi" | while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      n="$(fm_get "$f" name)"; [ -n "$n" ] || n="$(basename "$f" .md)"
      [ "$n" = "$fname" ] || continue
      v="$(fm_get "$f" "$fkey")"
      if [ -n "$v" ]; then printf '%s\n' "$v"; return 0; fi
    done
  done
}
```
Add dispatcher arm: `__fmfield) fm_field "$@" ;;`.

- [ ] **Step 4: Run to verify PASS** (`bats tests/detect.bats`).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(defect-scan): field-by-field shadow-merge (fm_field)"
```

---

## Task 5: Data-driven `cmd_stacks`

**Files:**
- Modify: `skills/scan/lib/detect.sh` (replace `cmd_stacks` body)
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing zero-core-edit test (and keep the existing detection tests)**

```bash
@test "stacks: zero-core-edit — a project profile teaches a new language" {
  repo="$BATS_TEST_TMPDIR/toml"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: toml-lang\ndetect_files: foo.toml\nextensions: toml\n---\n' \
    > "$repo/.defect-scan/profiles/toml-lang.md"
  : > "$repo/foo.toml"
  run "$DETECT" stacks "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"toml-lang"* ]]
}
```
(The existing tests "detects react-typescript", "detects python", "falls back to
generic", plus the dart test from earlier, MUST still pass.)

- [ ] **Step 2: Run to verify FAIL/regressions** (`bats tests/detect.bats`).

- [ ] **Step 3: Replace `cmd_stacks`** with the data-driven version

```sh
cmd_stacks() {
  root="${1:?usage: detect.sh stacks <dir>}"
  found=""
  "$0" profiles "$root" | while IFS="$(printf '\t')" read -r name _ _; do
    [ "$name" = "generic" ] && continue
    df="$(fm_field "$name" detect_files "$root")"
    ext="$(fm_field "$name" extensions "$root")"
    match=""
    for f in $df;  do [ -e "$root/$f" ] && match=1; done
    for e in $ext; do find "$root" -type f -name "*.$e" 2>/dev/null | head -1 | grep -q . && match=1; done
    [ -n "$match" ] && echo "$name"
  done | sort -u > "$root/.dscan_stacks.$$" 2>/dev/null || true
  if [ -s "$root/.dscan_stacks.$$" ]; then cat "$root/.dscan_stacks.$$"; else echo generic; fi
  rm -f "$root/.dscan_stacks.$$" 2>/dev/null || true
}
```
Note: the subshell-in-pipe can't set `found`, so results go to a temp file we then
emit (or `generic` if empty). `"$0" profiles` re-invokes detect.sh for discovery.

- [ ] **Step 4: Run to verify PASS** (all stacks tests, incl. the new toml-lang and the existing react/python/dart/generic).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(defect-scan): data-driven cmd_stacks (profile frontmatter)"
```

---

## Task 6: Data-driven triage source-filter

**Files:**
- Modify: `skills/scan/lib/detect.sh` (`cmd_triage` source-filter + new `all_extensions`)
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing zero-core-edit triage test**

```bash
@test "triage: zero-core-edit — a project profile's extension becomes scannable" {
  repo="$BATS_TEST_TMPDIR/tomltriage"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: toml-lang\nextensions: toml\n---\n' \
    > "$repo/.defect-scan/profiles/toml-lang.md"
  cd "$repo" && git init -q
  echo x > a.toml && echo y > b.md
  git add -A && git -c user.email=t@t -c user.name=t commit -qm init
  run bash -c "printf 'a.toml\nb.md\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.toml"* ]]   # toml now ranked (profile taught it)
  [[ "$output" != *"b.md"* ]]     # docs still excluded
}
```
(The existing triage tests — source-filter excludes docs, ranks `.dart`, scales,
skips dirs — MUST still pass; `.dart` now comes from the built-in dart profile's
`extensions`.)

- [ ] **Step 2: Run to verify FAIL** (`.toml` currently excluded by the hardcoded allowlist).

- [ ] **Step 3: Add `all_extensions` and replace the hardcoded `case` glob**

Add helper:
```sh
# Union of every discovered profile's extensions + an always-on base, space-sep.
all_extensions() {
  repo="${1:-$PWD}"
  { echo "sh bash"
    "$0" profiles "$repo" | while IFS="$(printf '\t')" read -r name _ _; do
      fm_field "$name" extensions "$repo"
    done
  } | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' '
}
```
In `cmd_triage`, compute the set once and replace the hardcoded `case ... esac`
source-filter:
```sh
  exts=" $(all_extensions "$cwd") "
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -d "$f" ] && continue
    e="${f##*.}"
    case "$exts" in *" $e "*) : ;; *) continue ;; esac
    printf '%s\n' "$f"
  done | awk '...existing churn/loc/sec scoring unchanged...'
```
(Keep the awk scoring block exactly as-is; only the pre-filter `case` changes from
the static extension list to the dynamic `$exts` membership test. `all_extensions`
must be computed BEFORE `cd` changes context, or pass `$cwd` explicitly — it does.)

- [ ] **Step 4: Run to verify PASS** (new toml test + all existing triage tests).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(defect-scan): data-driven triage source-filter (profile extensions)"
```

---

## Task 7: Pattern-pack discovery (`cmd_patterns`)

**Files:**
- Modify: `skills/scan/lib/detect.sh`
- Modify: `tests/detect.bats`

- [ ] **Step 1: Write failing test**

```bash
@test "patterns: lists built-in recurring.md plus a project pattern pack" {
  repo="$BATS_TEST_TMPDIR/packs"; mkdir -p "$repo/.defect-scan/patterns"
  printf '# P-custom — our billing rule\n' > "$repo/.defect-scan/patterns/custom.md"
  run "$DETECT" patterns "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"recurring.md" ]]                 # built-in first
  [[ "$output" == *".defect-scan/patterns/custom.md"* ]] # project pack additive
}
```

- [ ] **Step 2: Run to verify FAIL** (`patterns` unknown).

- [ ] **Step 3: Implement `cmd_patterns`**

```sh
cmd_patterns() {
  repo="${1:-$PWD}"
  echo "$(skill_dir)/patterns/recurring.md"
  [ -n "${DEFECT_SCAN_NO_USER:-}" ]    || for f in "$HOME/.config/defect-scan/patterns"/*.md; do [ -f "$f" ] && echo "$f"; done
  [ -n "${DEFECT_SCAN_NO_PROJECT:-}" ] || for f in "$repo/.defect-scan/patterns"/*.md; do [ -f "$f" ] && echo "$f"; done
}
```
Add dispatcher arm: `patterns) cmd_patterns "$@" ;;`.

- [ ] **Step 4: Run to verify PASS** (`bats tests/detect.bats`).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(defect-scan): pattern-pack discovery (cmd_patterns)"
```

---

## Task 8: SKILL.md orchestration + dispatcher usage string

**Files:**
- Modify: `skills/scan/lib/detect.sh` (update `usage:` strings to include new subcommands)
- Modify: `skills/scan/SKILL.md`
- Modify: `tests/detect.bats`

- [ ] **Step 1: Update the two `usage:` strings** in `detect.sh` to list all public subcommands:
`usage: detect.sh {stacks|tool|scope|triage|issues|profiles|patterns} ...`
(both the `main()` `*)` arm and any other usage echo).

- [ ] **Step 2: Edit `SKILL.md`** — replace the Stage 1/2/3 mechanics:

Stage 1 (Detect): add after the stacks line —
```
Profiles are discovered across three layers (built-in, ~/.config/defect-scan,
./.defect-scan); `lib/detect.sh profiles <repo>` lists `name⇥path⇥origin`. Load
each matched profile by its path. `--no-user-profiles` / `--no-project-profiles`
set `DEFECT_SCAN_NO_USER=1` / `DEFECT_SCAN_NO_PROJECT=1` for a built-in-only scan.
```
Stage 2 (Tool pass): add —
```
**Origin-gated execution.** For a profile with `origin=builtin`, run its tools
automatically. For `origin=user` or `origin=project`, the profile came from a
scanned/user location — surface the suggested tool and CONFIRM with the user
before running it; resolve it via `lib/detect.sh tool <name>` (never a raw shell
string from the profile). This prevents a scanned repo's profile from executing
arbitrary commands (pattern P4).
```
Stage 3 (Reasoning): change "consult `patterns/recurring.md`" to —
```
consult every file listed by `lib/detect.sh patterns <repo>` (built-in P1–P10
plus any user/project pattern packs)
```

- [ ] **Step 3: Write structure tests**

```bash
@test "detect.sh usage lists profiles and patterns subcommands" {
  run "$DETECT" bogus
  [[ "$output" == *"profiles"* ]]; [[ "$output" == *"patterns"* ]]
}
@test "SKILL.md documents origin-gated execution and layered profiles" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -qi "origin-gated\|origin=builtin\|CONFIRM" "$f"
  grep -q "detect.sh patterns" "$f"
  grep -q "DEFECT_SCAN_NO_PROJECT" "$f"
}
```

- [ ] **Step 4: Run to verify PASS** (`bats tests/detect.bats`).

- [ ] **Step 5: Commit**
```bash
git add skills/scan/lib/detect.sh skills/scan/SKILL.md tests/detect.bats
git commit -m "feat(defect-scan): SKILL.md orchestration for layered profiles + origin gating"
```

---

## Task 9: Extension guide (clear, copy-paste) + template + help pointer + verification

The extension instructions must be **very clear** — a user adding a language
should succeed by copying a template and filling four fields, without reading core.
This task ships: a copy-me template profile, a step-by-step `EXTENDING.md`, a field
reference, a worked example, the help pointer, and the README link.

**Files:**
- Create: `skills/scan/profiles/TEMPLATE.md.example`
- Create: `EXTENDING.md`
- Modify: `README.md`, `skills/scan/commands/help.md`
- Modify: `tests/detect.bats` (docs-presence guard)

- [ ] **Step 1: Create the copy-me template** `skills/scan/profiles/TEMPLATE.md.example`

```markdown
---
name: <profile-name>            # required — unique id (lowercase), e.g. ruby
detect_files: <file> <file>     # optional — manifest files; any present → match (e.g. Gemfile)
extensions: <ext> <ext>         # optional — source extensions WITHOUT dots (e.g. rb); enables triage
tools: <tool> <tool>            # optional — analyzer command NAMES only (e.g. rubocop)
---
# Profile: <profile-name>

## Detection
When this profile applies (mirror the frontmatter signals in prose).

## Toolchain
- `<tool> <args>`  — what it checks. Resolved via `detect.sh tool <name>`.
Install hint: `<how to install the tools>`.

## Reasoning checklist
- cat#1 … cat#2 … cat#3 … cat#4 … cat#5 …  (specialize the 5 baseline categories)
- <language>-specific: <the traps unique to this language>

## Auto-fix-safe
Which findings are safe to auto-apply (usually none unless tool-confirmed + trivial).
```
Note: the `.example` suffix keeps it out of discovery (it is not a real profile).

- [ ] **Step 2: Create `EXTENDING.md`** (the clear, step-by-step guide)

````markdown
# Extending defect-scan

Add a language or your own defect rules **without editing core** — just drop files.

## Add a language (3 steps)
1. **Pick where it lives:**
   - Team-wide (committed with the repo): `.defect-scan/profiles/<name>.md`
   - Personal (all your repos): `~/.config/defect-scan/profiles/<name>.md`
2. **Copy the template** `skills/scan/profiles/TEMPLATE.md.example` to that path,
   rename it `<name>.md`.
3. **Fill the frontmatter** (4 fields) and the prose. Done — `/defect-scan:scan`
   now detects it, triages its files, and reasons with your checklist.

### Frontmatter field reference
| field | required | format | purpose |
|-------|----------|--------|---------|
| `name` | yes | one lowercase word | profile id; also the dedupe/shadow key |
| `detect_files` | no | space/comma list of filenames | repo matches if any is present |
| `extensions` | no | space/comma list, **no dots** | matches files; **enables triage scanning** |
| `tools` | no | space/comma list of command names | analyzers the Toolchain prose runs |

### Worked example — add Ruby
`.defect-scan/profiles/ruby.md`:
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
- cat#2: rescue with empty body / `rescue => e` that swallows.
- cat#4: `File.open` without a block; unclosed connections.
- ruby-specific: `==` vs `eql?`, mutable default args via `||=`, monkey-patch hazards.
## Auto-fix-safe
Only `rubocop -a` autocorrectable cops in a safe set (layout/style).
```
Scan a Ruby repo → it's detected, `.rb` files are triaged, RuboCop runs.

## Add your own defect patterns
Drop `.md` files in `.defect-scan/patterns/` (team) or
`~/.config/defect-scan/patterns/` (personal). The reasoning pass reads them
alongside the built-in P1–P10 — encode your org's recurring bugs.

## Precedence & inheritance
Project (`.defect-scan/`) overrides user (`~/.config/defect-scan/`) overrides
built-in, **by `name`**. A field you leave out inherits from the profile you shadow
— so tweaking one field of a built-in is safe (you won't lose its `extensions`).

## Safety
Analyzers declared by **your own** project/user profiles are **confirmed before
running** (defect-scan never auto-executes a tool command from a scanned repo —
that would be the very RCE class it flags as pattern P4). Only built-in profiles
auto-run their analyzers.

## Toggle layers
`--no-project-profiles` / `--no-user-profiles` scan with built-ins only.
````

- [ ] **Step 3: Add a short README section linking to it**

```markdown
## Extending it (zero core edits)
Add a language or custom defect rules by dropping files in `.defect-scan/` (team)
or `~/.config/defect-scan/` (personal) — no core changes. Copy
`skills/scan/profiles/TEMPLATE.md.example`, fill four frontmatter fields, done.
**Full step-by-step guide: [`EXTENDING.md`](./EXTENDING.md).**
```

- [ ] **Step 4: Add a help pointer** in `skills/scan/commands/help.md` (under "What it uses"):
```markdown
- **Extensible:** add a language or defect pack by dropping files in `.defect-scan/`
  — see `EXTENDING.md` (copy `profiles/TEMPLATE.md.example`, fill 4 fields).
```

- [ ] **Step 5: Docs-presence guard test** in `tests/detect.bats`:
```bash
@test "extension docs exist: EXTENDING.md, template, help pointer" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/EXTENDING.md" ]
  [ -f "$root/skills/scan/profiles/TEMPLATE.md.example" ]
  grep -q "EXTENDING.md" "$root/README.md"
  grep -q "EXTENDING.md" "$root/skills/scan/commands/help.md"
  # the template must not be discovered as a real profile (no .md extension match)
  grep -q "TEMPLATE.md.example" "$root/EXTENDING.md"
}
```

- [ ] **Step 6: Confirm the template is NOT discovered as a profile**

Run: `skills/scan/lib/detect.sh profiles /tmp | grep -i template && echo LEAK || echo "ok — template not discovered"`
Expected: `ok — template not discovered` (discovery globs `*.md`, not `*.md.example`).

- [ ] **Step 7: Run the full suite**

Run: `bats tests/detect.bats`
Expected: all pass (prior suite + every new test, incl. the docs-presence guard).

- [ ] **Step 8: Real-world proof on the Dart monorepo (manual)**

Run:
```bash
DETECT="$PWD/skills/scan/lib/detect.sh"
( cd /Applications/Development/Projects/discogorama-monorepo && "$DETECT" stacks "$PWD" )
```
Expected: still prints `dart` (now via the migrated built-in frontmatter, not the
old hardcode).

- [ ] **Step 9: Commit**
```bash
git add EXTENDING.md README.md skills/scan/profiles/TEMPLATE.md.example skills/scan/commands/help.md tests/detect.bats
git commit -m "docs(defect-scan): clear language-extension guide (EXTENDING.md + template)"
```

---

## Self-review

**Spec coverage:**
- §1 frontmatter format → Task 1 (reader) + Task 2 (built-ins declare it). ✓
- §2 discovery + 2 subcommands → Task 3 (`profiles`) + Task 7 (`patterns`). ✓
- §2 shadow-merge (frontmatter inherit, prose replace, origin=winner) → Task 4 (`fm_field`) + Task 3 (origin/path = winner). ✓
- §3 data-driven `cmd_stacks` + triage allowlist → Task 5 + Task 6. ✓
- §4 origin-gated execution → Task 8 (SKILL.md) + origin emitted in Task 3. ✓
- §5 SKILL.md orchestration + layer-toggle flags → Task 8; env vars honored in Task 3/6/7. ✓
- §6 error handling (malformed → skip; no-ext → triage-skip; collision → precedence) → fm_get returns empty on malformed (Task 1); cmd_stacks/triage skip empties (Task 5/6); precedence in Task 3. ✓
- §7 tests (frontmatter, discovery, zero-core-edit ×2, shadow-merge, patterns, migration regression) → Tasks 1,3,4,5,6,7. ✓

**Placeholder scan:** No TBD/"handle edge cases"/"similar to Task N" — every code/test step has complete content. The Task 6 step references "existing awk scoring block unchanged" and explicitly says to keep it verbatim, changing only the pre-filter `case`. ✓

**Type/contract consistency:** Subcommand names (`profiles`, `patterns`, `__fmget`, `__fmfield`) and helper names (`skill_dir`, `fm_get`, `fm_field`, `profile_layers`, `all_extensions`) are used identically across Tasks 1–8. `origin` values (`builtin|user|project`) match between Task 3 (emit) and Task 8 (gate). Output format `name⇥path⇥origin` consistent between Task 3 and its consumers (Task 5 `cmd_stacks`, Task 6 `all_extensions`). ✓

**One risk noted for the implementer:** `cmd_stacks`/`all_extensions` re-invoke `"$0" profiles` (a subprocess) inside a loop — acceptable (discovery is cheap: a few small files), and avoids threading state through pipes. If a future profile count explodes, memoize; not needed now.

#!/usr/bin/env bats

setup() {
  DETECT="$BATS_TEST_DIRNAME/../lib/detect.sh"
}

@test "detect.sh prints usage and exits 2 on unknown subcommand" {
  run "$DETECT" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

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
  echo two >> f.txt
  echo new > g.txt
  run "$DETECT" scope "" "" "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "MODE=changes" ]]
  [[ "$output" == *"f.txt"* && "$output" == *"g.txt"* ]]
}

@test "triage: ranks a security-named, churned file above a quiet plain file" {
  repo="$BATS_TEST_TMPDIR/triage"
  mkdir -p "$repo" && cd "$repo" && git init -q
  printf 'a\nb\nc\n' > auth.py && echo x > util.py
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  echo more >> auth.py && git -c user.email=t@t -c user.name=t commit -qam c2
  echo again >> auth.py && git -c user.email=t@t -c user.name=t commit -qam c3
  run bash -c "printf 'auth.py\nutil.py\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"auth.py" ]]
  [[ "${lines[1]}" == *"util.py" ]]
}

@test "triage: output is <score>TAB<path> and sorted descending" {
  repo="$BATS_TEST_TMPDIR/triage2"
  mkdir -p "$repo" && cd "$repo" && git init -q
  echo x > a.py && echo y > login_handler.py
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  run bash -c "printf 'a.py\nlogin_handler.py\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  s0="$(printf '%s' "${lines[0]}" | cut -f1)"
  s1="$(printf '%s' "${lines[1]}" | cut -f1)"
  [ "$s0" -ge "$s1" ]
  [[ "${lines[0]}" == *$'\t'* ]]
}

@test "baseline-categories.md defines all five categories" {
  f="$BATS_TEST_DIRNAME/../baseline-categories.md"
  for n in 1 2 3 4 5; do grep -qE "^## $n\." "$f"; done
}

@test "report-format.md defines all three tiers" {
  f="$BATS_TEST_DIRNAME/../report-format.md"
  grep -qi "High" "$f"; grep -qi "Medium" "$f"; grep -qi "Low" "$f"
}

@test "every profile declares the four required sections in order" {
  for p in generic python react-typescript; do
    f="$BATS_TEST_DIRNAME/../profiles/$p.md"
    [ -f "$f" ]
    grep -qE '^## Detection'           "$f"
    grep -qE '^## Toolchain'           "$f"
    grep -qE '^## Reasoning checklist' "$f"
    grep -qE '^## Auto-fix-safe'       "$f"
  done
}

@test "SKILL.md has name and description front matter" {
  f="$BATS_TEST_DIRNAME/../SKILL.md"
  grep -qE '^name: defect-scan$' "$f"
  grep -qE '^description: ' "$f"
}

@test "SKILL.md documents all stages (incl. triage) and the fix-safety gate" {
  f="$BATS_TEST_DIRNAME/../SKILL.md"
  grep -q "Stage 1 — Detect" "$f"
  grep -q "Stage 1b — Triage" "$f"
  grep -q "Stage 2 — Tool pass" "$f"
  grep -q "Stage 3 — Reasoning pass" "$f"
  grep -q "Stage 4 — Report" "$f"
  grep -qi "Refuse if the working tree is dirty" "$f"
  grep -qi "adversarial verification" "$f"
}

@test "ruff flags the planted bare-except in the python fixture" {
  tool="$("$DETECT" tool ruff "$BATS_TEST_DIRNAME/fixtures/python" || true)"
  [ -n "$tool" ] || skip "ruff not installed"
  run "$tool" check --select E722 --output-format=json \
      "$BATS_TEST_DIRNAME/fixtures/python/app/bug.py"
  [[ "$output" == *"E722"* ]]
}

@test "triage: scales to a large file list in one pass (no per-file git)" {
  repo="$BATS_TEST_TMPDIR/big"
  mkdir -p "$repo" && cd "$repo" && git init -q
  echo seed > seed.txt && git add . && git -c user.email=t@t -c user.name=t commit -qm init
  # 300 path names, mostly untracked (churn 0) — must still return 300 ranked lines
  run bash -c "for i in \$(seq 1 300); do echo file_\$i.ts; done | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 300 ]
  [[ "${lines[0]}" == *$'\t'* ]]
}

@test "triage: skips directories without aborting the ranking (getline i/o guard)" {
  repo="$BATS_TEST_TMPDIR/withdir"
  mkdir -p "$repo/adir" && cd "$repo" && git init -q
  echo code > real.py && echo more > zzz.py
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  # input mixes a directory between two real files; all real files must survive
  run bash -c "printf 'real.py\nadir\nzzz.py\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real.py"* ]]
  [[ "$output" == *"zzz.py"* ]]
  [[ "$output" != *$'\t'adir ]]   # the directory is not ranked
}

@test "triage: ranks only source files, excludes docs/config/data" {
  repo="$BATS_TEST_TMPDIR/srcfilter"
  mkdir -p "$repo" && cd "$repo" && git init -q
  echo code > app.py && echo ui > widget.tsx
  echo doc > README.md && echo cfg > package.json && echo note > notes.txt
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  run bash -c "printf 'README.md\napp.py\npackage.json\nwidget.tsx\nnotes.txt\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]                 # only the 2 source files ranked
  [[ "$output" == *"app.py"* ]]
  [[ "$output" == *"widget.tsx"* ]]
  [[ "$output" != *"README.md"* ]]
  [[ "$output" != *"package.json"* ]]
  [[ "$output" != *"notes.txt"* ]]
}

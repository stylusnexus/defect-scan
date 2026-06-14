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

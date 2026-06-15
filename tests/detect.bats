#!/usr/bin/env bats

setup() {
  DETECT="$BATS_TEST_DIRNAME/../skills/scan/lib/detect.sh"
}

@test "detect.sh prints usage and exits 2 on unknown subcommand" {
  run "$DETECT" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "preflight: passes when core tools are present (lists usage)" {
  run "$DETECT" preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "preflight: fails with a clear message when a core tool is missing" {
  # Simulate an unsupported environment: a PATH with none of the core tools.
  # Invoke sh by absolute path so `env` can still find the shell; only the in-script
  # `command -v <tool>` lookups fail (empty PATH).
  empty="$BATS_TEST_TMPDIR/emptybin"; mkdir -p "$empty"
  run env PATH="$empty" /bin/sh "$DETECT" preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING core tools"* ]]
  [[ "$output" == *"WSL or Git-Bash"* ]]
}

@test "usage lists the preflight subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"preflight"* ]]
}

@test "eval: a clean run (all expected bugs, no FPs) scores precision 1, recall 1" {
  corpus="$BATS_TEST_DIRNAME/eval/python/seen"
  f="$BATS_TEST_TMPDIR/good"
  {
    echo "bug_bare_except.py:5:cat#2"
    echo "bug_resource_leak.py:2:cat#4"
    echo "bug_mutable_default.py:1:cat#5"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
  [[ "$output" == *"fp=0"* ]]
}

@test "eval: a finding on a clean fixture is a false positive (precision drops)" {
  corpus="$BATS_TEST_DIRNAME/eval/python/seen"
  f="$BATS_TEST_TMPDIR/noisy"
  {
    echo "bug_bare_except.py:5:cat#2"
    echo "bug_resource_leak.py:2:cat#4"
    echo "bug_mutable_default.py:1:cat#5"
    echo "clean_near_miss_except.py:5:cat#2"   # the tripwire: FP on a clean near-miss
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fp=1"* ]]
  [[ "$output" != *"precision=1.00"* ]]        # noise must NOT score as perfect
}

@test "eval: a missed expected bug is a false negative (recall drops)" {
  corpus="$BATS_TEST_DIRNAME/eval/python/seen"
  f="$BATS_TEST_TMPDIR/missed"
  {
    echo "bug_bare_except.py:5:cat#2"
    echo "bug_resource_leak.py:2:cat#4"
  } > "$f"                                       # omits the mutable-default bug
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fn=1"* ]]
  [[ "$output" != *"recall=1.00"* ]]
}

@test "eval: corpus has buggy + clean fixtures incl. a near-miss (FP tripwire)" {
  d="$BATS_TEST_DIRNAME/eval/python/seen"
  [ -s "$d/bug_bare_except.py.expected" ]        # buggy: non-empty sidecar
  [ -f "$d/clean_contextmanager.py.expected" ] && [ ! -s "$d/clean_contextmanager.py.expected" ]  # clean: empty
  [ -f "$d/clean_near_miss_except.py" ]          # near-miss present
}

@test "eval: react-typescript corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/react-typescript/seen"
  [ -s "$corpus/bug_floating_promise.ts.expected" ]                 # buggy: non-empty
  [ -f "$corpus/clean_validated_json.ts.expected" ] && [ ! -s "$corpus/clean_validated_json.ts.expected" ]  # near-miss clean: empty
  f="$BATS_TEST_TMPDIR/rts"
  {
    echo "bug_floating_promise.ts:6:cat#2"
    echo "bug_index_key.tsx:5:cat#5"
    echo "bug_unvalidated_json.ts:4:cat#1"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "eval: counts a final finding that has no trailing newline (no silent drop)" {
  corpus="$BATS_TEST_DIRNAME/eval/python/seen"
  f="$BATS_TEST_TMPDIR/nonl"
  # Two findings, NO trailing newline on the last line.
  printf 'bug_bare_except.py:5:cat#2\nbug_resource_leak.py:2:cat#4' > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tp=2"* ]]        # both counted, last line not dropped
}

@test "eval: errors clearly on a missing corpus dir or findings file" {
  run "$DETECT" eval "/no/such/corpus" "/no/such/findings"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "usage lists the eval subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"eval"* ]]
}

@test "codex-verify: requires a prompt file" {
  run "$DETECT" codex-verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "codex-verify: returns the second model's verdict (read-only, via stub)" {
  export DEFECT_SCAN_CODEX="$BATS_TEST_DIRNAME/fixtures/codex-stub/codex"
  pf="$BATS_TEST_TMPDIR/prompt"; printf 'Refute this finding. real or not?\n' > "$pf"
  run "$DETECT" codex-verify "$pf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT:"* ]]
}

@test "codex-verify: degrades cleanly (exit 3) when codex is unavailable" {
  export DEFECT_SCAN_CODEX="/nonexistent/codex-xyz"
  pf="$BATS_TEST_TMPDIR/prompt2"; echo "x" > "$pf"
  run "$DETECT" codex-verify "$pf"
  [ "$status" -eq 3 ]
  [[ "$output" == *"codex not available"* ]]
}

@test "codex-verify: errors (exit 2) when the prompt file is missing" {
  export DEFECT_SCAN_CODEX="$BATS_TEST_DIRNAME/fixtures/codex-stub/codex"
  run "$DETECT" codex-verify "/no/such/prompt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "usage lists the codex-verify subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"codex-verify"* ]]
}

@test "windows fallback: PowerShell shim exists and delegates to the shared engine" {
  f="$BATS_TEST_DIRNAME/../windows/defect-scan.ps1"
  [ -f "$f" ]
  grep -q "detect.sh" "$f"          # delegates to the one engine, no reimplementation
  grep -qi "bash" "$f"              # locates a POSIX shell
  [ -f "$BATS_TEST_DIRNAME/../windows/README.md" ]
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

@test "scope: normal --no-ff feature merge surfaces the merged files (HEAD~1 net effect)" {
  repo="$BATS_TEST_TMPDIR/mergehead"
  mkdir -p "$repo" && cd "$repo"
  git init -qb main
  echo base > base.txt && git add . && git -c user.email=t@t -c user.name=t commit -qm init
  git checkout -qb feat
  echo feature > feature.py && git add . && git -c user.email=t@t -c user.name=t commit -qm feat
  git checkout -q main
  git -c user.email=t@t -c user.name=t merge --no-ff -qm "merge feat" feat
  # Working tree is clean; HEAD is the merge commit.
  run "$DETECT" scope "" "" "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "MODE=changes" ]]
  [[ "$output" == *"feature.py"* ]]
}

@test "scope: no-op back-merge (empty HEAD~1 diff) falls back to the last non-merge commit" {
  repo="$BATS_TEST_TMPDIR/noopmerge"
  mkdir -p "$repo" && cd "$repo"
  git init -qb main
  D1="2020-01-01T00:00:00"; D2="2020-01-02T00:00:00"
  GIT_AUTHOR_DATE="$D1" GIT_COMMITTER_DATE="$D1" \
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  echo base > base.txt && git add .
  GIT_AUTHOR_DATE="$D1" GIT_COMMITTER_DATE="$D1" \
    git -c user.email=t@t -c user.name=t commit -qm init
  git checkout -qb feat
  echo feature > feature.py && git add .
  GIT_AUTHOR_DATE="$D2" GIT_COMMITTER_DATE="$D2" \
    git -c user.email=t@t -c user.name=t commit -qm feat   # newest non-merge commit
  git checkout -q main
  # `-s ours` records the merge but KEEPS main's tree → HEAD~1 (first-parent) diff is empty.
  GIT_AUTHOR_DATE="$D2" GIT_COMMITTER_DATE="$D2" \
    git -c user.email=t@t -c user.name=t merge -s ours --no-ff -qm "no-op back-merge" feat
  run "$DETECT" scope "" "" "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "MODE=changes" ]]
  [[ "$output" == *"feature.py"* ]]   # resolved via last non-merge commit, not the empty HEAD~1 diff
}

@test "scope: never dead-ends silently on a clean tree (diagnostic to stderr)" {
  repo="$BATS_TEST_TMPDIR/cleanquiet"
  mkdir -p "$repo" && cd "$repo" && git init -q
  # Empty commit so HEAD exists but introduces no files and has no resolvable diff.
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m empty
  run "$DETECT" scope "" "" "$repo"   # bats merges stderr into $output
  [ "$status" -eq 0 ]
  [[ "$output" == *"defect-scan:"* ]]
  [[ "$output" == *"--full"* ]]
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
  f="$BATS_TEST_DIRNAME/../skills/scan/baseline-categories.md"
  for n in 1 2 3 4 5; do grep -qE "^## $n\." "$f"; done
}

@test "report-format.md defines all three tiers" {
  f="$BATS_TEST_DIRNAME/../skills/scan/report-format.md"
  grep -qi "High" "$f"; grep -qi "Medium" "$f"; grep -qi "Low" "$f"
}

@test "every profile declares the four required sections in order" {
  for p in generic python react-typescript dart; do
    f="$BATS_TEST_DIRNAME/../skills/scan/profiles/$p.md"
    [ -f "$f" ]
    grep -qE '^## Detection'           "$f"
    grep -qE '^## Toolchain'           "$f"
    grep -qE '^## Reasoning checklist' "$f"
    grep -qE '^## Auto-fix-safe'       "$f"
  done
}

@test "SKILL.md has name and description front matter" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -qE '^name: defect-scan$' "$f"
  grep -qE '^description: ' "$f"
}

@test "SKILL.md documents all stages (incl. triage) and the fix-safety gate" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -q "Stage 1 — Detect" "$f"
  grep -q "Stage 1b — Triage" "$f"
  grep -q "Stage 2 — Tool pass" "$f"
  grep -q "Stage 3 — Reasoning pass" "$f"
  grep -q "Stage 4 — Report" "$f"
  grep -qi "Refuse if the working tree is dirty" "$f"
  grep -qi "adversarial verification" "$f"
}

@test "codex port: entrypoint drives the shared pipeline (delegates to SKILL.md, runs detect.sh)" {
  f="$BATS_TEST_DIRNAME/../codex/defect-scan.md"
  [ -f "$f" ]
  grep -q "DEFECT_SCAN_HOME" "$f"          # locates the shared install
  grep -q "detect.sh" "$f"                 # reuses the shared plumbing
  grep -q "SKILL.md" "$f"                  # canonical spec is the source of truth
  grep -qi "origin-gate" "$f"              # preserves the P4 safety invariant
  grep -qi "report-only" "$f"              # preserves the report-only default
  [ -f "$BATS_TEST_DIRNAME/../codex/README.md" ]   # install/usage doc
  [ -f "$BATS_TEST_DIRNAME/../AGENTS.md" ]          # Codex contributor guide
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

@test "patterns/recurring.md defines the battle-tested patterns P1-P10" {
  f="$BATS_TEST_DIRNAME/../skills/scan/patterns/recurring.md"
  [ -f "$f" ]
  for p in P1 P2 P3 P4 P5 P6 P7 P8 P9 P10; do grep -qE "^## $p" "$f"; done
}

@test "SKILL.md reasoning pass consults patterns/recurring.md" {
  grep -q "patterns/recurring.md" "$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
}

@test "issues: requires at least one keyword" {
  run "$DETECT" issues
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "issues: formats gh results as '#num<TAB>state<TAB>title'" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  run "$DETECT" issues credit refund
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "#5421"$'\t'"OPEN"$'\t'* ]]
  [[ "${lines[1]}" == "#1274"$'\t'"CLOSED"$'\t'* ]]
}

@test "issues: degrades cleanly (exit 3, skip message, no issue rows) when gh unavailable" {
  export DEFECT_SCAN_GH="/nonexistent/gh-binary-xyz"
  run "$DETECT" issues credit          # bats merges stderr into $output
  [ "$status" -eq 3 ]
  [[ "$output" == *"gh not available"* ]]
  [[ "$output" != *"#"* ]]             # no issue rows emitted to stdout
}

@test "issues-create: requires a title and a body file" {
  run "$DETECT" issues-create "only a title"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "issues-create: errors (exit 2) when the body file is missing" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  run "$DETECT" issues-create "a title" "/nonexistent/body.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"body file not found"* ]]
}

@test "issues-create: files an issue and prints the new URL, passing title + labels through" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  export GH_STUB_LOG="$BATS_TEST_TMPDIR/ghlog"
  body="$BATS_TEST_TMPDIR/body.md"; printf '## Defect\nsome details\n' > "$body"
  run "$DETECT" issues-create "[High] auth.py:42 · cat#3 SQL injection" "$body" "defect-scan,bug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/example/repo/issues/9999"* ]]   # URL for back-reference
  log="$(cat "$GH_STUB_LOG")"
  [[ "$log" == *"--label defect-scan,bug"* ]]                          # labels passed through
  [[ "$log" == *"--title [High] auth.py:42 · cat#3 SQL injection"* ]]  # title passed through
  [[ "$log" == *"--body-file"* ]]                                      # body passed via file
}

@test "issues-create: degrades cleanly (exit 3, no URL) when gh unavailable" {
  export DEFECT_SCAN_GH="/nonexistent/gh-binary-xyz"
  body="$BATS_TEST_TMPDIR/body2.md"; echo x > "$body"
  run "$DETECT" issues-create "a title" "$body"
  [ "$status" -eq 3 ]
  [[ "$output" == *"gh not available"* ]]
  [[ "$output" != *"http"* ]]          # nothing filed
}

@test "issues-ensure-label: best-effort create succeeds with the stub" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  run "$DETECT" issues-ensure-label defect-scan
  [ "$status" -eq 0 ]
}

@test "issues-ensure-label: exit 3 when gh unavailable (caller treats as best-effort)" {
  export DEFECT_SCAN_GH="/nonexistent/gh-binary-xyz"
  run "$DETECT" issues-ensure-label defect-scan
  [ "$status" -eq 3 ]
}

@test "issues-create: degrades cleanly with no-op set -- when no labels are given" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  export GH_STUB_LOG="$BATS_TEST_TMPDIR/ghlog-nolabel"
  body="$BATS_TEST_TMPDIR/body3.md"; echo x > "$body"
  run "$DETECT" issues-create "no-label title" "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"issues/9999"* ]]
  [[ "$(cat "$GH_STUB_LOG")" != *"--label"* ]]   # no --label flag emitted
}

@test "issues-create: carries a kind+priority label pair through (e.g. defect-scan,P1)" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  export GH_STUB_LOG="$BATS_TEST_TMPDIR/ghlog-prio"
  body="$BATS_TEST_TMPDIR/bodyp.md"; echo x > "$body"
  run "$DETECT" issues-create "[High] a finding" "$body" "defect-scan,P1"
  [ "$status" -eq 0 ]
  [[ "$(cat "$GH_STUB_LOG")" == *"--label defect-scan,P1"* ]]
}

@test "issues-ensure-label: creates a priority label (P0) best-effort" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  run "$DETECT" issues-ensure-label P0 b60205 "Highest priority"
  [ "$status" -eq 0 ]
}

@test "labels: lists existing repo label names" {
  export DEFECT_SCAN_GH="$BATS_TEST_DIRNAME/fixtures/gh-stub/gh"
  run "$DETECT" labels
  [ "$status" -eq 0 ]
  [[ "$output" == *"bug"* ]]
  [[ "$output" == *"defect"* ]]      # a defect-related label the SKILL can propose
}

@test "labels: degrades cleanly (exit 3) when gh unavailable" {
  export DEFECT_SCAN_GH="/nonexistent/gh-binary-xyz"
  run "$DETECT" labels
  [ "$status" -eq 3 ]
  [[ "$output" == *"gh not available"* ]]
}

@test "detect.sh usage lists the issue-filing subcommands" {
  run "$DETECT" bogus
  [[ "$output" == *"issues-create"* ]]
  [[ "$output" == *"issues-ensure-label"* ]]
  [[ "$output" == *"labels"* ]]
}

@test "SKILL.md documents depth cap and correlation stage" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -q -- "--depth N" "$f"
  grep -q "Stage 4a — Correlate" "$f"
  grep -q "detect.sh issues" "$f"
  grep -q -- "--no-correlate" "$f"
}

@test "plugin manifest exists with required fields and skill is under skills/scan" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/.claude-plugin/plugin.json" ]
  jq -e '.name and .description and .version' "$root/.claude-plugin/plugin.json" >/dev/null
  [ -f "$root/skills/scan/SKILL.md" ]
  [ -x "$root/skills/scan/lib/detect.sh" ]
}

@test "hook: no-op (exit 0, silent) when DEFECT_SCAN_HOOK is unset" {
  run env -u DEFECT_SCAN_HOOK sh "$BATS_TEST_DIRNAME/../hooks/pre-commit-scan.sh" <<< '{"tool_input":{"command":"git commit -m x"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: opted-in but non-commit command → exit 0, silent" {
  run env DEFECT_SCAN_HOOK=1 sh "$BATS_TEST_DIRNAME/../hooks/pre-commit-scan.sh" <<< '{"tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook: opted-in commit advisory is non-blocking (exit 0) and mentions defect-scan" {
  repo="$BATS_TEST_TMPDIR/hookrepo"
  mkdir -p "$repo" && cd "$repo" && git init -q
  printf 'import os\nx=1\n' > a.py && git add . && git -c user.email=t@t -c user.name=t commit -qm init
  echo "y=2" >> a.py   # uncommitted change so scope=changes is non-empty
  run env DEFECT_SCAN_HOOK=1 CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.." \
      sh "$BATS_TEST_DIRNAME/../hooks/pre-commit-scan.sh" <<< '{"tool_input":{"command":"git commit -m y"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"defect-scan:"* ]]
}

@test "help command and hooks manifest exist; profiles wire optional analyzers" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/commands/help.md" ]
  jq -e '.hooks.PreToolUse' "$root/hooks/hooks.json" >/dev/null
  grep -q "semgrep" "$root/skills/scan/SKILL.md"
  grep -q "bandit"  "$root/skills/scan/profiles/python.md"
}

@test "setup-optional-tools helper exists, is executable, and parses" {
  s="$BATS_TEST_DIRNAME/../scripts/setup-optional-tools.sh"
  [ -x "$s" ]
  sh -n "$s"
  grep -q "semgrep" "$s"; grep -q "gitleaks" "$s"
}

@test "stacks: detects dart from pubspec.yaml" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/dart"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dart"* ]]
}

@test "triage: ranks .dart files (source-filter includes dart)" {
  repo="$BATS_TEST_TMPDIR/dartrepo"
  mkdir -p "$repo" && cd "$repo" && git init -q
  printf 'void main(){}\n' > main.dart && echo readme > README.md
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  run bash -c "printf 'main.dart\nREADME.md\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"main.dart"* ]]
  [[ "$output" != *"README.md"* ]]
}

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

@test "profiles: lists built-ins with origin=builtin" {
  run "$DETECT" profiles "$BATS_TEST_TMPDIR/none"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dart"$'\t'* ]]
  [[ "$output" == *"builtin"* ]]
}

@test "profiles: project layer shadows a same-named built-in" {
  repo="$BATS_TEST_TMPDIR/proj"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: dart\nextensions: dart\n---\n' > "$repo/.defect-scan/profiles/dart.md"
  run "$DETECT" profiles "$repo"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1=="dart"' | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$(printf '%s\n' "$output" | awk -F'\t' '$1=="dart"{print $3}')" == "project" ]]
}

@test "profiles: --no-project (env) hides project layer" {
  repo="$BATS_TEST_TMPDIR/proj2"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: zzlang\nextensions: zz\n---\n' > "$repo/.defect-scan/profiles/zzlang.md"
  run env DEFECT_SCAN_NO_PROJECT=1 "$DETECT" profiles "$repo"
  [[ "$output" != *"zzlang"* ]]
}

@test "fm_field: shadowing profile inherits an absent field from the shadowed one" {
  repo="$BATS_TEST_TMPDIR/merge"; mkdir -p "$repo/.defect-scan/profiles"
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

@test "stacks: detects a profile with extensions-only (no detect_files)" {
  repo="$BATS_TEST_TMPDIR/extonly"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: zz-lang\nextensions: zz\n---\n' > "$repo/.defect-scan/profiles/zz-lang.md"
  : > "$repo/thing.zz"
  run "$DETECT" stacks "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"zz-lang"* ]]
}

@test "stacks: zero-core-edit — a project profile teaches a new language" {
  repo="$BATS_TEST_TMPDIR/toml"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: toml-lang\ndetect_files: foo.toml\nextensions: toml\n---\n' \
    > "$repo/.defect-scan/profiles/toml-lang.md"
  : > "$repo/foo.toml"
  run "$DETECT" stacks "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"toml-lang"* ]]
}

@test "triage: zero-core-edit — a project profile's extension becomes scannable" {
  repo="$BATS_TEST_TMPDIR/tomltriage"; mkdir -p "$repo/.defect-scan/profiles"
  printf -- '---\nname: toml-lang\nextensions: toml\n---\n' \
    > "$repo/.defect-scan/profiles/toml-lang.md"
  cd "$repo" && git init -q
  echo x > a.toml && echo y > b.md
  git add -A && git -c user.email=t@t -c user.name=t commit -qm init
  run bash -c "printf 'a.toml\nb.md\n' | '$DETECT' triage '$repo'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"a.toml"* ]]
  [[ "$output" != *"b.md"* ]]
}

@test "patterns: lists built-in recurring.md plus a project pattern pack" {
  repo="$BATS_TEST_TMPDIR/packs"; mkdir -p "$repo/.defect-scan/patterns"
  printf '# P-custom — our billing rule\n' > "$repo/.defect-scan/patterns/custom.md"
  run "$DETECT" patterns "$repo"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"recurring.md" ]]
  [[ "$output" == *".defect-scan/patterns/custom.md"* ]]
}

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

@test "extension docs exist: EXTENDING.md, template, help pointer" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/EXTENDING.md" ]
  [ -f "$root/skills/scan/profiles/TEMPLATE.md.example" ]
  grep -q "EXTENDING.md" "$root/README.md"
  grep -q "EXTENDING.md" "$root/commands/help.md"
  grep -q "TEMPLATE.md.example" "$root/EXTENDING.md"
}

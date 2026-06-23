#!/usr/bin/env bats

setup() {
  DETECT="$BATS_TEST_DIRNAME/../skills/scan/lib/detect.sh"
  export DEFECT_SCAN_EVAL_BACKOFF=0   # #104: no real sleeps between eval-run retries in tests
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

_mk_grader_corpus() {  # $1=dir : one buggy fixture (line 4, cat#2) + one clean
  mkdir -p "$1"
  printf 'x\n' > "$1/bug.ext"; printf '4:cat#2\n' > "$1/bug.ext.expected"
  printf 'x\n' > "$1/clean.ext"; : > "$1/clean.ext.expected"
}

@test "grader: off-by-one line is a true positive (tolerance)" {
  d="$BATS_TEST_TMPDIR/g"; _mk_grader_corpus "$d"
  printf 'bug.ext:3:cat#2\n' > "$BATS_TEST_TMPDIR/f"      # expected 4, reported 3
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tp=1"* ]] && [[ "$output" == *"fp=0"* ]] && [[ "$output" == *"fn=0"* ]]
}

@test "grader: off-by-three line is FP+FN (beyond tolerance)" {
  d="$BATS_TEST_TMPDIR/g"; _mk_grader_corpus "$d"
  printf 'bug.ext:7:cat#2\n' > "$BATS_TEST_TMPDIR/f"      # |7-4|=3 > 2
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [[ "$output" == *"tp=0"* ]] && [[ "$output" == *"fp=1"* ]] && [[ "$output" == *"fn=1"* ]]
}

@test "grader: a spray near one expected scores ONE tp + rest fp (precision-first)" {
  d="$BATS_TEST_TMPDIR/g"; _mk_grader_corpus "$d"
  printf 'bug.ext:3:cat#2\nbug.ext:5:cat#2\n' > "$BATS_TEST_TMPDIR/f"   # both within ±2 of 4
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [[ "$output" == *"tp=1"* ]] && [[ "$output" == *"fp=1"* ]] && [[ "$output" == *"fn=0"* ]]
}

@test "grader: wrong category within tolerance does NOT match" {
  d="$BATS_TEST_TMPDIR/g"; _mk_grader_corpus "$d"
  printf 'bug.ext:4:cat#3\n' > "$BATS_TEST_TMPDIR/f"      # right line, wrong category
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [[ "$output" == *"tp=0"* ]] && [[ "$output" == *"fp=1"* ]] && [[ "$output" == *"fn=1"* ]]
}

@test "grader: any finding on a clean fixture is an FP (tripwire intact)" {
  d="$BATS_TEST_TMPDIR/g"; _mk_grader_corpus "$d"
  printf 'clean.ext:2:cat#2\n' > "$BATS_TEST_TMPDIR/f"
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [[ "$output" == *"fp=1"* ]]
}

@test "grader: exact-duplicate findings do not double-count" {
  d="$BATS_TEST_TMPDIR/g"; _mk_grader_corpus "$d"
  printf 'bug.ext:4:cat#2\nbug.ext:4:cat#2\n' > "$BATS_TEST_TMPDIR/f"
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [[ "$output" == *"tp=1"* ]] && [[ "$output" == *"fp=0"* ]]
}

@test "grader: two same-category defects far apart both match their nearest" {
  d="$BATS_TEST_TMPDIR/g2"; mkdir -p "$d"
  printf 'x\n' > "$d/two.ext"; printf '10:cat#2\n50:cat#2\n' > "$d/two.ext.expected"
  printf 'two.ext:11:cat#2\ntwo.ext:49:cat#2\n' > "$BATS_TEST_TMPDIR/f"
  run "$DETECT" eval "$d" "$BATS_TEST_TMPDIR/f"
  [[ "$output" == *"tp=2"* ]] && [[ "$output" == *"fp=0"* ]] && [[ "$output" == *"fn=0"* ]]
}

@test "eval grader: matches directory-fixture findings by case-relative path" {
  dir="$BATS_TEST_TMPDIR/sc/seen"; mkdir -p "$dir/case1/pkg"
  printf 'pkg/a.js:3:cat#6\n' > "$dir/case1.expected"
  printf 'case1/pkg/a.js:3:cat#6\n' > "$BATS_TEST_TMPDIR/findings.txt"
  run "$DETECT" eval "$dir" "$BATS_TEST_TMPDIR/findings.txt"
  [[ "$output" == *"tp=1"* ]]; [[ "$output" == *"fp=0"* ]]; [[ "$output" == *"fn=0"* ]]
}

@test "eval grader: directory-fixture clean case flags a false positive" {
  dir="$BATS_TEST_TMPDIR/sc2/seen"; mkdir -p "$dir/clean1/pkg"
  : > "$dir/clean1.expected"   # empty = clean
  printf 'clean1/pkg/a.js:9:cat#6\n' > "$BATS_TEST_TMPDIR/f2.txt"
  run "$DETECT" eval "$dir" "$BATS_TEST_TMPDIR/f2.txt"
  [[ "$output" == *"fp=1"* ]]
}

@test "eval-run: a directory finding with a leading ./ still matches (case-prefix normalizes)" {
  c="$BATS_TEST_TMPDIR/dotc"; mkdir -p "$c/sc/seen/case1/scripts"
  printf 'x\n' > "$c/sc/seen/case1/scripts/setup.js"
  printf 'scripts/setup.js:1:cat#6\n' > "$c/sc/seen/case1.expected"
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=dirok DEFECT_SCAN_STUB_FINDING="./scripts/setup.js:1:cat#6" \
    run "$DETECT" eval-run sc --as react-typescript --runs 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"mean_recall=1.00"* ]]
}

@test "eval grader: single-file basename matching still works (backward compat)" {
  dir="$BATS_TEST_TMPDIR/sf/seen"; mkdir -p "$dir"
  printf '5:cat#3\n' > "$dir/Foo.java.expected"
  printf '/tmp/whatever/Foo.java:5:cat#3\n' > "$BATS_TEST_TMPDIR/f3.txt"
  run "$DETECT" eval "$dir" "$BATS_TEST_TMPDIR/f3.txt"
  [[ "$output" == *"tp=1"* ]]; [[ "$output" == *"fp=0"* ]]; [[ "$output" == *"fn=0"* ]]
}

@test "usage lists the eval subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"eval"* ]]
}

@test "extract_eval_block: one valid block returns its lines (exit 0)" {
  run sh -c 'printf "noise\n<<<EVAL\na.py:4:cat#2\nb.py:5:cat#3\nEVAL>>>\nmore\n" | "$0" __evalblock' "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.py:4:cat#2"* ]] && [[ "$output" == *"b.py:5:cat#3"* ]]
}

@test "extract_eval_block: present-but-empty block is OK (exit 0, no output)" {
  run sh -c 'printf "<<<EVAL\nEVAL>>>\n" | "$0" __evalblock' "$DETECT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract_eval_block: MISSING block is a protocol error (exit 4)" {
  run sh -c 'printf "just a report, no block\n" | "$0" __evalblock' "$DETECT"
  [ "$status" -eq 4 ]
}

@test "extract_eval_block: duplicate blocks are a protocol error (exit 4)" {
  run sh -c 'printf "<<<EVAL\nEVAL>>>\n<<<EVAL\nEVAL>>>\n" | "$0" __evalblock' "$DETECT"
  [ "$status" -eq 4 ]
}

@test "extract_eval_block: malformed line is a protocol error (exit 4)" {
  run sh -c 'printf "<<<EVAL\nnot-valid\nEVAL>>>\n" | "$0" __evalblock' "$DETECT"
  [ "$status" -eq 4 ]
}

@test "eval-categories: baseline cats unioned with corpus-specific labels" {
  run "$DETECT" eval-categories rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#1"* ]] && [[ "$output" == *"cat#5"* ]]
  [[ "$output" == *"panic"* ]]            # rust corpus uses a language-specific label
}

@test "eval-categories: yaml has coerce, shell has quoting" {
  run "$DETECT" eval-categories yaml
  [[ "$output" == *"coerce"* ]]
  run "$DETECT" eval-categories shell
  [[ "$output" == *"quoting"* ]]
}

@test "eval-categories: honors DEFECT_SCAN_EVAL_CORPUS override" {
  mkdir -p "$BATS_TEST_TMPDIR/c/foo/seen"
  printf '3:widget\n' > "$BATS_TEST_TMPDIR/c/foo/seen/bug_x.ext.expected"
  DEFECT_SCAN_EVAL_CORPUS="$BATS_TEST_TMPDIR/c" run "$DETECT" eval-categories foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"widget"* ]] && [[ "$output" == *"cat#3"* ]]
}

@test "usage lists the eval-legend subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"eval-legend"* ]]
}

@test "eval-legend: injects cat# BODIES, not just titles (#105)" {
  run "$DETECT" eval-legend rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#1 = Null"* ]]                 # title
  [[ "$output" == *"dereferences"* ]]                 # body word — absent from the old title-only legend
  [[ "$output" == *"cat#6 = Supply-chain"* ]]
}

@test "eval-legend: rust panic label is defined and disambiguated from cat#1 (#105)" {
  run "$DETECT" eval-legend rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"panic = "* ]]
  # the exact gap that caused the 0.67/0.67 drift: indexing belongs to cat#1, not panic
  [[ "$output" == *"NOT panic-prone indexing"* ]]
}

@test "eval-legend: shell quoting and yaml coerce labels are defined (#105)" {
  run "$DETECT" eval-legend shell
  [[ "$output" == *"quoting = "* ]]
  run "$DETECT" eval-legend yaml
  [[ "$output" == *"coerce = "* ]]
}

@test "eval-legend: a language with no custom labels emits only cat# defs (#105)" {
  run "$DETECT" eval-legend csharp
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#3 = Injection"* ]]
  [[ "$output" != *" = "*"panic"* ]]   # no stray language-specific label
}

@test "eval-legend: a profile cat#N scope extension merges into the baseline cat# (#109)" {
  run "$DETECT" eval-legend react-typescript
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#5 = Concurrency hazards:"* ]]   # baseline body still present
  [[ "$output" == *"lang-specific:"* ]]                 # extension marker
  [[ "$output" == *"index-as-key"* ]]                   # the React specialization the eval model missed
  # the extension rides ON cat#5, not emitted as a stray second cat#5 entry
  [ "$(printf '%s' "$output" | tr ';' '\n' | grep -c 'cat#5 = ')" -eq 1 ]
}

@test "react-typescript profile declares a cat#5 scope extension in ## Eval labels (#109)" {
  f="$BATS_TEST_DIRNAME/../skills/scan/profiles/react-typescript.md"
  grep -qE '^## Eval labels' "$f"
  grep -qE '^cat#5:' "$f"
}

@test "eval-legend: works from a skill path containing spaces (#109 regression guard)" {
  # An unquoted profile-arg substitution word-split a spaced install path → empty legend.
  spaced="$BATS_TEST_TMPDIR/space dir/skills"
  mkdir -p "$spaced"
  cp -R "$BATS_TEST_DIRNAME/../skills/scan" "$spaced/scan"
  run "$spaced/scan/lib/detect.sh" eval-legend react-typescript
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#1 = Null"* ]]      # baseline cat# legend present (was empty pre-fix)
  [[ "$output" == *"index-as-key"* ]]      # the cat#5 profile extension still merges
}

@test "rust/shell/yaml profiles declare an ## Eval labels section (#105 source)" {
  for p in rust shell yaml; do
    grep -qE '^## Eval labels' "$BATS_TEST_DIRNAME/../skills/scan/profiles/$p.md"
  done
}

@test "both runners build the legend via detect.sh eval-legend, not a title-only awk (#105)" {
  for rn in claude codex; do
    f="$BATS_TEST_DIRNAME/../tests/eval/runners/$rn.sh"
    grep -q 'eval-legend' "$f"
    ! grep -q 'cat#%s = %s; ' "$f"   # the old title-only awk must be gone
  done
}

_mk_eval_corpus() {  # $1 = root, $2 = lang
  mkdir -p "$1/$2/seen"
  printf 'x\n' > "$1/$2/seen/bug_one.ext"
  printf '1:cat#2\n' > "$1/$2/seen/bug_one.ext.expected"   # matches the stub's default finding
  printf 'x\n' > "$1/$2/seen/clean_ok.ext"
  : > "$1/$2/seen/clean_ok.ext.expected"   # empty sidecar => clean
}

@test "eval-run: exit 3 when DEFECT_SCAN_EVAL_RUNNER is unset" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" run env -u DEFECT_SCAN_EVAL_RUNNER "$DETECT" eval-run foo
  [ "$status" -eq 3 ]
}

@test "eval-run: a clean run over the corpus scores precision/recall 1.00" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=perfect \
    run "$DETECT" eval-run foo --runs 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"mean_precision=1.00"* ]]
  [[ "$output" == *"mean_recall=1.00"* ]]
  [[ "$output" == *"clean_fp_runs=0"* ]]
}

@test "eval-run: a finding on the clean fixture shows up as clean-FP rate" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=ok DEFECT_SCAN_STUB_FINDING="4:cat#2" \
    run "$DETECT" eval-run foo --runs 2
  [[ "$output" == *"clean_fp_runs=2"* ]]
}

@test "eval-run: a missing block marks the run partial (not a silent pass)" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=missing \
    run "$DETECT" eval-run foo --runs 1
  [[ "$output" == *"partial"* ]] || [[ "$output" == *"inconclusive"* ]]
}

_mk_baseline() {  # $1=path $2=pfloor $3=rfloor $4=pbase $5=rbase $6=noise
  printf 'precision_floor=%s\nrecall_floor=%s\nprecision_baseline=%s\nrecall_baseline=%s\nnoise_band=%s\noverfit_band=0.10\n' \
    "$2" "$3" "$4" "$5" "$6" > "$1"
}

@test "eval-run: an all-inconclusive run fails (partial is never a green pass)" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  _mk_baseline "$c/foo/baseline.seen.txt" 0.80 0.50 0.80 0.50 0.10
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=missing \
    run "$DETECT" eval-run foo --runs 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "eval-run --update-baseline refuses on a partial run" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=missing \
    run "$DETECT" eval-run foo --runs 1 --update-baseline
  [ "$status" -ne 0 ]
  [ ! -f "$c/foo/baseline.seen.txt" ]      # nothing written from a broken run
}

@test "eval-run: a flaky fixture run recovers via retry, not PARTIAL (#104)" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  cnt="$BATS_TEST_TMPDIR/flakycount"
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=flaky DEFECT_SCAN_STUB_FLAKY_COUNTER="$cnt" DEFECT_SCAN_STUB_FLAKY_FAILS=1 \
  DEFECT_SCAN_EVAL_RETRIES=2 \
    run "$DETECT" eval-run foo --runs 1
  [[ "$output" != *"PARTIAL"* ]]                       # recovered, never inconclusive
  [[ "$output" == *"retries="* ]]                      # stability surfaced in the summary
  [[ "$output" == *"recovered via retry"* ]]           # #104 recovery message (only on real recovery)
}

@test "eval-run: retries reported; exhaustion still fails as PARTIAL (#104)" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=missing DEFECT_SCAN_EVAL_RETRIES=2 \
    run "$DETECT" eval-run foo --runs 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"retries="* ]]
  [[ "$output" == *"PARTIAL"* ]]
  [[ "$output" == *"exhausting retries"* ]]
  [[ "$output" != *"recovered"* ]]   # must NOT claim recovery on an exhausted run (honest log)
}

@test "eval_gate: PASS when precision >= floor and recall ok" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run "$DETECT" __evalgate "$b" 0.95 0.80 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "eval_gate: FAIL when mean precision below floor" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run "$DETECT" __evalgate "$b" 0.80 0.80 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "eval_gate: FAIL on erosion (precision below baseline - noise_band)" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.50 0.50 0.94 0.75 0.05
  run "$DETECT" __evalgate "$b" 0.85 0.80 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "eval_gate: FLAG (exit 0) when clean-FP runs > 0" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run "$DETECT" __evalgate "$b" 0.95 0.80 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"FLAG"* ]]
}

@test "eval_gate: WARN (exit 0) when recall below floor" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run "$DETECT" __evalgate "$b" 0.95 0.60 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "eval-run --update-baseline writes the baseline file" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=perfect \
    run "$DETECT" eval-run foo --runs 2 --update-baseline
  [ "$status" -eq 0 ]
  [ -f "$c/foo/baseline.seen.txt" ]
  grep -q "precision_baseline=1.00" "$c/foo/baseline.seen.txt"
}

_mk_eval_dir_corpus() {  # $1 = root, $2 = lang — one DIRECTORY fixture case1/ + sidecar
  mkdir -p "$1/$2/seen/case1/pkg"
  printf 'x\n' > "$1/$2/seen/case1/pkg/a.js"
  printf 'pkg/a.js:1:cat#2\n' > "$1/$2/seen/case1.expected"   # case-relative key
}

@test "eval-run: directory fixture scores a relative-path finding as a TP (case-prefix)" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_dir_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=dirok DEFECT_SCAN_STUB_FINDING="pkg/a.js:1:cat#2" \
    run "$DETECT" eval-run foo --as react-typescript --runs 1
  [ "$status" -eq 0 ]
  # the case-prefix made the grader match: recall reflects a hit, not a miss
  [[ "$output" == *"mean_precision=1.00"* ]]
  [[ "$output" == *"mean_recall=1.00"* ]]
}

@test "eval-run --as forwards the scan profile to the runner as arg 3" {
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  arglog="$BATS_TEST_TMPDIR/arg3.log"
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=perfect DEFECT_SCAN_STUB_ARG3LOG="$arglog" \
    run "$DETECT" eval-run foo --as react-typescript --runs 1
  [ "$status" -eq 0 ]
  grep -qx "react-typescript" "$arglog"
}

@test "eval-run --split all FLAGs overfitting when seen >> held-out" {
  c="$BATS_TEST_TMPDIR/c"
  mkdir -p "$c/foo/seen" "$c/foo/held-out"
  for sp in seen held-out; do
    printf 'x\n' > "$c/foo/$sp/bug_one.ext"; printf '4:cat#2\n' > "$c/foo/$sp/bug_one.ext.expected"
  done
  _mk_baseline "$c/foo/baseline.seen.txt"     0.50 0.30 0.50 0.30 0.10
  _mk_baseline "$c/foo/baseline.held-out.txt" 0.50 0.30 0.50 0.30 0.10
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=splitaware DEFECT_SCAN_STUB_FINDING="4:cat#2" \
    run "$DETECT" eval-run foo --split all --runs 2
  [[ "$output" == *"overfit"* ]] || [[ "$output" == *"FLAG"* ]]
}

@test "eval-gaps: flags a category with expected defects but zero detected" {
  c="$BATS_TEST_TMPDIR/c"; mkdir -p "$c/foo/seen"
  printf 'x\n' > "$c/foo/seen/bug_a.ext"; printf '3:cat#3\n' > "$c/foo/seen/bug_a.ext.expected"
  printf 'x\n' > "$c/foo/seen/bug_b.ext"; printf '4:cat#4\n' > "$c/foo/seen/bug_b.ext.expected"
  cat > "$c/foo/.last-run.seen.txt" <<'EOF'
runs=3
mean_precision=1.00
stddev_precision=0.00
mean_recall=0.50
stddev_recall=0.00
clean_fp_runs=0
@findings
bug_a.ext:3:cat#3
EOF
  DEFECT_SCAN_EVAL_CORPUS="$c" run "$DETECT" eval-gaps foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#4"* ]]
  [[ "$output" == *"0 detected"* ]] || [[ "$output" == *"GAP"* ]]
}

@test "eval_clean_fp matches basenames exactly (no regex-dot false positive)" {
  c="$BATS_TEST_TMPDIR/c"; mkdir -p "$c/foo/seen"
  # Buggy fixture (contains literal marker BUG) -> detected under bugonly mode,
  # emitting finding line "xBUGy:1:cat#2".
  printf 'x\n' > "$c/foo/seen/xBUGy"; printf '1:cat#2\n' > "$c/foo/seen/xBUGy.expected"
  # CLEAN fixture (empty .expected). Its basename AS A REGEX ("x.UGy") matches the
  # detected line "xBUGy:..." — but as a literal it does not, and bugonly does not
  # detect it (no literal BUG). The buggy regex must therefore NOT register a clean-FP.
  printf 'x\n' > "$c/foo/seen/x.UGy"; : > "$c/foo/seen/x.UGy.expected"
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=bugonly DEFECT_SCAN_STUB_FINDING="1:cat#2" \
    run "$DETECT" eval-run foo --runs 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean_fp_runs=0"* ]]
}

@test "eval-gaps category match is exact (no regex-dot cross-match)" {
  c="$BATS_TEST_TMPDIR/c"; mkdir -p "$c/foo/seen"
  printf 'x\n' > "$c/foo/seen/bug_a.ext"; printf '3:a.c\n' > "$c/foo/seen/bug_a.ext.expected"  # category literally "a.c"
  cat > "$c/foo/.last-run.seen.txt" <<'EOF'
runs=1
mean_precision=1.00
stddev_precision=0.00
mean_recall=0.00
stddev_recall=0.00
clean_fp_runs=0
@findings
bug_a.ext:3:axc
EOF
  # detected category is "axc", expected is "a.c" — these must NOT match (regex-dot would)
  DEFECT_SCAN_EVAL_CORPUS="$c" run "$DETECT" eval-gaps foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"GAP: a.c"* ]] || [[ "$output" == *"a.c — 1 expected, 0 detected"* ]]
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
  for p in generic python react-typescript dart ruby go csharp java yaml rust kotlin swift php shell objc; do
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

@test "SKILL.md verifies security-class tool findings (no blanket auto-High)" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -qi "security-class" "$f"
  grep -qi "FP-filter" "$f"
  grep -qi "downgrade to Medium" "$f"
  grep -qi "never drop\|not.*drop" "$f"   # recall guarantee: downgrade-only, never drop
  # the old unconditional invariant must be gone
  ! grep -q "Tool-confirmed findings are \*\*High\*\* by definition" "$f"
}

@test "codex driver mirrors security-class tool-finding verification (incl. never-drop)" {
  f="$BATS_TEST_DIRNAME/../codex/defect-scan.md"
  grep -qi "security-class" "$f"
  grep -qi "FP-filter" "$f"
  grep -qi "downgrade to Medium" "$f"
  grep -qi "never drop" "$f"               # lock the recall guarantee in both drivers
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

@test "gitleaks baseline config exists and allowlists node_modules + the supabase-demo JWT" {
  f="$BATS_TEST_DIRNAME/../skills/scan/gitleaks-baseline.toml"
  [ -f "$f" ]
  grep -q "node_modules" "$f"                       # path allowlist
  grep -q "eyJpc3MiOiJzdXBhYmFzZS1kZW1v" "$f"       # supabase-demo JWT issuer-prefix allowlist
}

@test "SKILL.md gitleaks guidance uses git-mode + triage (not the noisy --no-git)" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -q "gitleaks git" "$f"
  grep -q "gitleaks-baseline.toml" "$f"
  ! grep -q "gitleaks detect --no-git" "$f"         # the old firehose invocation is gone
  grep -qi "committed" "$f"
}

@test "gitleaks: baseline suppresses demo keys + node_modules but keeps a real committed secret" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed"
  base="$BATS_TEST_DIRNAME/../skills/scan/gitleaks-baseline.toml"
  repo="$BATS_TEST_TMPDIR/glrepo"; mkdir -p "$repo/node_modules/p" "$repo/.github/workflows"; cd "$repo"
  git init -q
  # Assembled from fragments so the contiguous AWS-key token isn't in this committed
  # file (GitHub push-protection + our own CI secrets scan would otherwise reject it);
  # gitleaks sees the full value in the throwaway repo at runtime.
  ak="AKIA""Z7Q2A9B8C7D6E5F4"
  printf 'aws_key = "%s"\n' "$ak" > real.tf                                          # real secret (flagged)
  printf 'aws_key = "%s"\n' "$ak" > node_modules/p/leak.js                           # same secret, path-allowlisted
  printf 'KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24ifQ.x\n' \
    > .github/workflows/ci.yml                                                        # demo JWT (allowlisted)
  git add -A && git -c user.email=t@t -c user.name=t commit -qm init
  gitleaks git -c "$base" --no-banner --report-format json --report-path out.json . >/dev/null 2>&1 || true
  # exactly one finding, and it's the real secret — not the demo key or node_modules
  [ "$(jq 'length' out.json)" -eq 1 ]
  [ "$(jq -r '.[0].File' out.json)" = "real.tf" ]
}

@test "gitleaks: baseline does NOT over-suppress — a real secret under examples/ still fires" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed"
  base="$BATS_TEST_DIRNAME/../skills/scan/gitleaks-baseline.toml"
  repo="$BATS_TEST_TMPDIR/glrepo2"; mkdir -p "$repo/examples/demo"; cd "$repo"
  git init -q
  # A real, unambiguous Stripe-format secret committed under examples/ — must still be
  # flagged (examples/ is a known leak vector; the baseline must not blanket-allowlist
  # it). Assembled from fragments so the literal token isn't in this committed file
  # (GitHub push-protection would otherwise reject this test); gitleaks sees the full
  # value in the throwaway repo at runtime.
  sk="sk_""live_""4eC39HqLyjWDarjtT1zdp7dcABCDEFGH"
  printf 'STRIPE_SECRET=%s\n' "$sk" > examples/demo/.env
  git add -A && git -c user.email=t@t -c user.name=t commit -qm init
  gitleaks git -c "$base" --no-banner --report-format json --report-path out.json . >/dev/null 2>&1 || true
  [ "$(jq 'length' out.json)" -ge 1 ]
  [[ "$(jq -r '.[].File' out.json)" == *"examples/demo/.env"* ]]
}

@test "codex plugin manifest: display name is 'Defect Scan', name is the slug, version in sync" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/.codex-plugin/plugin.json" ]
  [ "$(jq -r '.name' "$root/.codex-plugin/plugin.json")" = "defect-scan" ]           # install/invocation slug unchanged
  [ "$(jq -r '.interface.displayName' "$root/.codex-plugin/plugin.json")" = "Defect Scan" ]  # human display name
  # version must match the claude manifest — release-please bumps both; this guards the drift
  cv="$(jq -r '.version' "$root/.codex-plugin/plugin.json")"
  clv="$(jq -r '.version' "$root/.claude-plugin/plugin.json")"
  [ "$cv" = "$clv" ]
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

@test "stacks: detects ruby from Gemfile" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/ruby"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ruby"* ]]
}

@test "eval: dart corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/dart/seen"
  [ -s "$corpus/bug_context_async.dart.expected" ]
  [ -f "$corpus/clean_mounted_check.dart.expected" ] && [ ! -s "$corpus/clean_mounted_check.dart.expected" ]
  f="$BATS_TEST_TMPDIR/dart"
  {
    echo "bug_context_async.dart:4:cat#5"
    echo "bug_undisposed_controller.dart:3:cat#4"
    echo "bug_empty_catch.dart:3:cat#2"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "eval: ruby corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/ruby/seen"
  [ -s "$corpus/bug_bare_rescue.rb.expected" ]
  [ -f "$corpus/clean_rescue_reraise.rb.expected" ] && [ ! -s "$corpus/clean_rescue_reraise.rb.expected" ]
  f="$BATS_TEST_TMPDIR/rb"
  {
    echo "bug_bare_rescue.rb:3:cat#2"
    echo "bug_sql_injection.rb:3:cat#3"
    echo "bug_resource_leak.rb:2:cat#4"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "stacks: detects go from go.mod" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/go"
  [ "$status" -eq 0 ]
  [[ "$output" == *"go"* ]]
}

@test "eval: go corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/go/seen"
  [ -s "$corpus/bug_unchecked_error.go.expected" ]
  [ -f "$corpus/clean_deferred_close.go.expected" ] && [ ! -s "$corpus/clean_deferred_close.go.expected" ]
  f="$BATS_TEST_TMPDIR/go"
  {
    echo "bug_unchecked_error.go:6:cat#2"
    echo "bug_nil_map_write.go:5:cat#1"
    echo "bug_resource_leak.go:6:cat#4"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "stacks: detects csharp from a .csproj" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/csharp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"csharp"* ]]
}

@test "eval: csharp corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/csharp/seen"
  [ -s "$corpus/bug_empty_catch.cs.expected" ]
  [ -f "$corpus/clean_logged_rethrow.cs.expected" ] && [ ! -s "$corpus/clean_logged_rethrow.cs.expected" ]
  f="$BATS_TEST_TMPDIR/cs"
  {
    echo "bug_empty_catch.cs:4:cat#2"
    echo "bug_sql_injection.cs:4:cat#3"
    echo "bug_undisposed.cs:3:cat#4"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "stacks: detects java from pom.xml" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/java"
  [ "$status" -eq 0 ]
  [[ "$output" == *"java"* ]]
}

@test "eval: java corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/java/seen"
  [ -s "$corpus/BugEmptyCatch.java.expected" ]
  [ -f "$corpus/CleanLoggedRethrow.java.expected" ] && [ ! -s "$corpus/CleanLoggedRethrow.java.expected" ]
  f="$BATS_TEST_TMPDIR/java"
  {
    echo "BugEmptyCatch.java:4:cat#2"
    echo "BugSqlInjection.java:5:cat#3"
    echo "BugResourceLeak.java:4:cat#4"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "stacks: detects yaml extension-only (empty detect_files)" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"yaml"* ]]
}

@test "eval: yaml corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/yaml/seen"
  [ -s "$corpus/bug_actions_injection.yml.expected" ]
  [ -f "$corpus/clean_quoted_no.yml.expected" ] && [ ! -s "$corpus/clean_quoted_no.yml.expected" ]
  f="$BATS_TEST_TMPDIR/yml"
  {
    echo "bug_actions_injection.yml:7:cat#3"
    echo "bug_norway.yml:3:coerce"
    echo "bug_duplicate_keys.yml:4:cat#2"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "stacks: detects rust from Cargo.toml" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/rust"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rust"* ]]
}

@test "stacks: detects kotlin from a .kt file" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/kotlin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kotlin"* ]]
}

@test "stacks: detects swift from Package.swift" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/swift"
  [ "$status" -eq 0 ]
  [[ "$output" == *"swift"* ]]
}

@test "stacks: detects objc from Podfile" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/objc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"objc"* ]]
}

@test "stacks: detects php from composer.json" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/php"
  [ "$status" -eq 0 ]
  [[ "$output" == *"php"* ]]
}

@test "stacks: detects shell extension-only (empty detect_files)" {
  run "$DETECT" stacks "$BATS_TEST_DIRNAME/fixtures/shell"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shell"* ]]
}

@test "eval: shell corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/shell/seen"
  [ -s "$corpus/bug_unquoted.sh.expected" ]
  [ -f "$corpus/clean_cd_guard.sh.expected" ] && [ ! -s "$corpus/clean_cd_guard.sh.expected" ]
  f="$BATS_TEST_TMPDIR/sh"
  {
    echo "bug_unquoted.sh:3:quoting"
    echo "bug_cd_unchecked.sh:3:cat#2"
    echo "bug_eval.sh:3:cat#3"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "shellcheck flags the planted unquoted-var (SC2086) in the shell fixture" {
  tool="$("$DETECT" tool shellcheck "$BATS_TEST_DIRNAME/fixtures/shell" || true)"
  [ -n "$tool" ] || skip "shellcheck not installed"
  run "$tool" -f gcc "$BATS_TEST_DIRNAME/eval/shell/seen/bug_unquoted.sh"
  [[ "$output" == *"SC2086"* ]]
}

@test "eval: php corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/php/seen"
  [ -s "$corpus/bug_sql_injection.php.expected" ]
  [ -f "$corpus/clean_isset_guard.php.expected" ] && [ ! -s "$corpus/clean_isset_guard.php.expected" ]
  f="$BATS_TEST_TMPDIR/php"
  {
    echo "bug_sql_injection.php:3:cat#3"
    echo "bug_suppressed_error.php:3:cat#2"
    echo "bug_undefined_key.php:3:cat#1"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "eval: kotlin corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/kotlin/seen"
  [ -s "$corpus/bug_double_bang.kt.expected" ]
  [ -f "$corpus/clean_logged_rethrow.kt.expected" ] && [ ! -s "$corpus/clean_logged_rethrow.kt.expected" ]
  f="$BATS_TEST_TMPDIR/kt"
  {
    echo "bug_double_bang.kt:2:cat#1"
    echo "bug_swallowed.kt:4:cat#2"
    echo "bug_global_scope.kt:3:cat#5"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "eval: swift corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/swift/seen"
  [ -s "$corpus/bug_force_unwrap.swift.expected" ]
  [ -f "$corpus/clean_weak_self.swift.expected" ] && [ ! -s "$corpus/clean_weak_self.swift.expected" ]
  f="$BATS_TEST_TMPDIR/sw"
  {
    echo "bug_force_unwrap.swift:2:cat#1"
    echo "bug_try_bang.swift:3:cat#1"
    echo "bug_retain_cycle.swift:4:cat#4"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "eval: objc corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/objc/seen"
  [ -s "$corpus/bug_format_string.m.expected" ]
  [ -f "$corpus/clean_weak_self.m.expected" ] && [ ! -s "$corpus/clean_weak_self.m.expected" ]
  f="$BATS_TEST_TMPDIR/oc"
  {
    echo "bug_index_oob.m:4:cat#1"
    echo "bug_swallowed_error.m:5:cat#2"
    echo "bug_format_string.m:4:cat#3"
    echo "bug_retain_cycle.m:10:cat#4"
    echo "bug_data_race.m:12:cat#5"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
}

@test "eval: rust corpus scores a clean run 1.0 and has a near-miss" {
  corpus="$BATS_TEST_DIRNAME/eval/rust/seen"
  [ -s "$corpus/bug_unwrap.rs.expected" ]
  [ -f "$corpus/clean_get_index.rs.expected" ] && [ ! -s "$corpus/clean_get_index.rs.expected" ]
  f="$BATS_TEST_TMPDIR/rs"
  {
    echo "bug_unwrap.rs:3:panic"
    echo "bug_sql_injection.rs:2:cat#3"
    echo "bug_indexing.rs:2:cat#1"
  } > "$f"
  run "$DETECT" eval "$corpus" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precision=1.00"* ]]
  [[ "$output" == *"recall=1.00"* ]]
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
  [ "$("$DETECT" __fmget "$P/ruby.md" name)" = "ruby" ]
  [[ "$("$DETECT" __fmget "$P/ruby.md" extensions)" == *"rb"* ]]
  [[ "$("$DETECT" __fmget "$P/ruby.md" detect_files)" == *"Gemfile"* ]]
  [ "$("$DETECT" __fmget "$P/go.md" name)" = "go" ]
  [[ "$("$DETECT" __fmget "$P/go.md" extensions)" == *"go"* ]]
  [[ "$("$DETECT" __fmget "$P/go.md" detect_files)" == *"go.mod"* ]]
  [ "$("$DETECT" __fmget "$P/csharp.md" name)" = "csharp" ]
  [[ "$("$DETECT" __fmget "$P/csharp.md" extensions)" == *"cs"* ]]
  [[ "$("$DETECT" __fmget "$P/csharp.md" detect_files)" == *"global.json"* ]]
  [ "$("$DETECT" __fmget "$P/java.md" name)" = "java" ]
  [[ "$("$DETECT" __fmget "$P/java.md" extensions)" == *"java"* ]]
  [[ "$("$DETECT" __fmget "$P/java.md" detect_files)" == *"pom.xml"* ]]
  [ "$("$DETECT" __fmget "$P/yaml.md" name)" = "yaml" ]
  [[ "$("$DETECT" __fmget "$P/yaml.md" extensions)" == *"yaml"* ]]   # detect_files intentionally empty
  [ "$("$DETECT" __fmget "$P/rust.md" name)" = "rust" ]
  [[ "$("$DETECT" __fmget "$P/rust.md" extensions)" == *"rs"* ]]
  [[ "$("$DETECT" __fmget "$P/rust.md" detect_files)" == *"Cargo.toml"* ]]
  [ "$("$DETECT" __fmget "$P/kotlin.md" name)" = "kotlin" ]
  [[ "$("$DETECT" __fmget "$P/kotlin.md" extensions)" == *"kt"* ]]
  [ "$("$DETECT" __fmget "$P/swift.md" name)" = "swift" ]
  [[ "$("$DETECT" __fmget "$P/swift.md" extensions)" == *"swift"* ]]
  [[ "$("$DETECT" __fmget "$P/swift.md" detect_files)" == *"Package.swift"* ]]
  [ "$("$DETECT" __fmget "$P/php.md" name)" = "php" ]
  [[ "$("$DETECT" __fmget "$P/php.md" extensions)" == *"php"* ]]
  [[ "$("$DETECT" __fmget "$P/php.md" detect_files)" == *"composer.json"* ]]
  [ "$("$DETECT" __fmget "$P/shell.md" name)" = "shell" ]
  [[ "$("$DETECT" __fmget "$P/shell.md" extensions)" == *"sh"* ]]   # detect_files intentionally empty
  [ "$("$DETECT" __fmget "$P/objc.md" name)" = "objc" ]
  [[ "$("$DETECT" __fmget "$P/objc.md" extensions)" == *"mm"* ]]
  [[ "$("$DETECT" __fmget "$P/objc.md" detect_files)" == *"Podfile"* ]]
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

@test "eval-mode contract exists and both drivers reference it" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/skills/scan/eval-mode.md" ]
  grep -q "<<<EVAL" "$root/skills/scan/eval-mode.md"
  grep -q "EVAL>>>" "$root/skills/scan/eval-mode.md"
  grep -q "eval-mode" "$root/skills/scan/SKILL.md"
  grep -q "eval-mode" "$root/codex/defect-scan.md"
}

@test "runners exist, are read-only, force --lang, and never write" {
  root="$BATS_TEST_DIRNAME/.."
  for rn in claude codex; do
    f="$root/tests/eval/runners/$rn.sh"
    [ -x "$f" ]
    sh -n "$f"
    grep -q -- "--lang" "$f"
  done
  grep -q -- "--sandbox read-only" "$root/tests/eval/runners/codex.sh"
  grep -Eq -- "--(permission-mode|allowedTools|disallowedTools)" "$root/tests/eval/runners/claude.sh"
  # the eval block contract must be INLINE in each runner (not a file reference the
  # scanned temp dir can't see)
  grep -q "<<<EVAL" "$root/tests/eval/runners/claude.sh"
  grep -q "<<<EVAL" "$root/tests/eval/runners/codex.sh"
  ! grep -q "Follow eval-mode.md" "$root/tests/eval/runners/claude.sh"
  ! grep -q "Follow eval-mode.md" "$root/tests/eval/runners/codex.sh"
  # each runner must inject the language's valid label set (eval-categories) so the
  # model emits grader-matchable labels instead of synonyms (panic vs unwrap-panic)
  grep -q "eval-categories" "$root/tests/eval/runners/claude.sh"
  grep -q "eval-categories" "$root/tests/eval/runners/codex.sh"
}

@test "runners accept a scan-profile 3rd arg defaulting to the corpus arg" {
  for rn in claude codex; do
    f="$BATS_TEST_DIRNAME/../tests/eval/runners/$rn.sh"
    grep -Eq '\$\{3:-"?\$?lang"?\}|scan_profile=' "$f"
  done
}

@test "runners handle a directory fixture (copy dir + relative paths)" {
  for rn in claude codex; do
    f="$BATS_TEST_DIRNAME/../tests/eval/runners/$rn.sh"
    grep -Eq '\[ -d "\$fixture" \]|\[ -d "\$1" \]' "$f"   # branches on directory fixture
    grep -q "relative" "$f"                                # instructs relative paths
  done
}

@test "scripts/eval-run wrapper forwards to detect.sh eval-run" {
  root="$BATS_TEST_DIRNAME/.."
  [ -x "$root/scripts/eval-run" ]
  sh -n "$root/scripts/eval-run"
  c="$BATS_TEST_TMPDIR/c"; _mk_eval_corpus "$c" foo
  DEFECT_SCAN_EVAL_CORPUS="$c" \
  DEFECT_SCAN_EVAL_RUNNER="$BATS_TEST_DIRNAME/fixtures/eval-runner-stub" \
  DEFECT_SCAN_STUB_MODE=perfect \
    run "$root/scripts/eval-run" foo --runs 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"mean_precision=1.00"* ]]
}

@test "scripts/eval-run exits 3 when no runner is set and none is installed" {
  # only meaningful where neither model CLI exists (e.g. CI); the wrapper auto-selects otherwise
  command -v claude >/dev/null 2>&1 && skip "claude present (wrapper auto-selects)"
  command -v codex  >/dev/null 2>&1 && skip "codex present (wrapper auto-selects)"
  root="$BATS_TEST_DIRNAME/.."
  run env -u DEFECT_SCAN_EVAL_RUNNER "$root/scripts/eval-run" foo
  [ "$status" -eq 3 ]
}

@test "eval-categories includes cat#6 (supply-chain)" {
  run "$DETECT" eval-categories python
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#6"* ]]
}

@test "baseline-categories.md defines cat#6 supply-chain (High)" {
  f="$BATS_TEST_DIRNAME/../skills/scan/baseline-categories.md"
  grep -qi "^## 6\. Supply-chain" "$f"
  grep -qi "default severity: High" "$f"
}

@test "runner legend picks up cat#6 from baseline-categories headers" {
  f="$BATS_TEST_DIRNAME/../skills/scan/baseline-categories.md"
  legend="$(awk '/^## [0-9]+\./ { n=$2; sub(/\./,"",n); t=$0; sub(/^## [0-9]+\. /,"",t); sub(/  .*/,"",t); printf "cat#%s=%s;", n, t }' "$f")"
  [[ "$legend" == *"cat#6=Supply-chain"* ]]
}

@test "detect.sh usage lists the manifest subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"manifest"* ]]
}

@test "manifest: surfaces lifecycle scripts and dependency names" {
  repo="$BATS_TEST_TMPDIR/npm1"; mkdir -p "$repo"
  cat > "$repo/package.json" <<'JSON'
{ "name": "x", "scripts": { "postinstall": "node scripts/setup.js" },
  "dependencies": { "left-pad": "1.0.0" }, "devDependencies": { "typescript": "5.0.0" } }
JSON
  run "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIFECYCLE"* ]]
  [[ "$output" == *"postinstall"* ]]
  [[ "$output" == *"node scripts/setup.js"* ]]
  [[ "$output" == *"DEPENDENCIES"* ]]
  [[ "$output" == *"left-pad"* ]]
  [[ "$output" == *"typescript"* ]]
}

@test "manifest: no package.json is a clean no-op (exit 0, no output)" {
  repo="$BATS_TEST_TMPDIR/empty"; mkdir -p "$repo"
  run "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "manifest fallback (no jq): extracts deps from compact JSON" {
  repo="$BATS_TEST_TMPDIR/compact"; mkdir -p "$repo"
  printf '%s\n' '{ "scripts": { "postinstall": "node x.js" }, "dependencies": { "left-pad": "1.0.0" }, "devDependencies": { "typescript": "5.0.0" }, "optionalDependencies": { "fsevents": "2.0.0" } }' > "$repo/package.json"
  run env DEFECT_SCAN_NO_JQ=1 "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIFECYCLE"* ]]
  [[ "$output" == *"postinstall"* ]]
  [[ "$output" == *"node x.js"* ]]
  [[ "$output" == *"DEPENDENCIES"* ]]
  [[ "$output" == *"left-pad"* ]]
  [[ "$output" == *"typescript"* ]]
  [[ "$output" == *"fsevents"* ]]
  # must NOT surface script names or version strings as if they were packages
  [[ "$output" != *"DEPENDENCIES ==="*"postinstall"* ]]
  [[ "$output" != *"1.0.0"* ]]
}

@test "manifest fallback (no jq): extracts deps from multi-line JSON" {
  repo="$BATS_TEST_TMPDIR/multiline"; mkdir -p "$repo"
  cat > "$repo/package.json" <<'JSON'
{
  "name": "x",
  "scripts": {
    "postinstall": "node x.js"
  },
  "dependencies": {
    "left-pad": "1.0.0"
  },
  "devDependencies": {
    "typescript": "5.0.0"
  },
  "optionalDependencies": {
    "fsevents": "2.0.0"
  }
}
JSON
  run env DEFECT_SCAN_NO_JQ=1 "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIFECYCLE"* ]]
  [[ "$output" == *"postinstall"* ]]
  [[ "$output" == *"DEPENDENCIES"* ]]
  [[ "$output" == *"left-pad"* ]]
  [[ "$output" == *"typescript"* ]]
  [[ "$output" == *"fsevents"* ]]
}

@test "manifest: malformed package.json degrades to exit 0 (jq and no-jq)" {
  repo="$BATS_TEST_TMPDIR/mal"; mkdir -p "$repo"
  printf 'BROKEN{{ not json\n' > "$repo/package.json"
  run "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  run env DEFECT_SCAN_NO_JQ=1 "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
}

@test "detect.sh usage lists the semgrep-trace subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"semgrep-trace"* ]]
}

@test "semgrep-trace: renders source→sink path with intermediate vars" {
  fix="$BATS_TEST_DIRNAME/fixtures/semgrep/trace-sample.json"
  run bash -c "'$DETECT' semgrep-trace < '$fix'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FINDING py.tainted-os-system @ app/vuln.py:6 [ERROR]"* ]]
  [[ "$output" == *"SOURCE: app/vuln.py:3"* ]]
  [[ "$output" == *"~> greeting @ app/vuln.py:4"* ]]
  [[ "$output" == *"~> cmd @ app/vuln.py:5"* ]]
  [[ "$output" == *"SINK:   app/vuln.py:6"* ]]
}

@test "semgrep-trace: a null dataflow_trace degrades to an honest (none) note, not silence" {
  fix="$BATS_TEST_DIRNAME/fixtures/semgrep/trace-sample.json"
  run bash -c "'$DETECT' semgrep-trace < '$fix'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FINDING js.no-trace-rule"* ]]
  [[ "$output" == *"TRACE: (none"* ]]
}

@test "semgrep-trace: no jq is INCONCLUSIVE (never silent, exit 0)" {
  fix="$BATS_TEST_DIRNAME/fixtures/semgrep/trace-sample.json"
  run bash -c "DEFECT_SCAN_NO_JQ=1 '$DETECT' semgrep-trace < '$fix'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INCONCLUSIVE"* ]]
}

@test "semgrep-trace: empty stdin is a clean no-op (exit 0, no output)" {
  run bash -c "printf '' | '$DETECT' semgrep-trace"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "semgrep-trace: garbage JSON degrades to INCONCLUSIVE, not a crash" {
  run bash -c "printf 'not json{' | '$DETECT' semgrep-trace"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INCONCLUSIVE"* ]]
}

@test "semgrep-trace: caps output volume via DEFECT_SCAN_SEMGREP_TRACE_MAX" {
  many="$BATS_TEST_TMPDIR/many.json"
  # 5 trace-less findings; cap at 2 → only 2 FINDING headers survive
  printf '{"results":[' > "$many"
  for i in 1 2 3 4 5; do
    [ "$i" -gt 1 ] && printf ',' >> "$many"
    printf '{"check_id":"r%s","path":"f%s.py","start":{"line":%s},"extra":{"message":"m","severity":"ERROR","dataflow_trace":null}}' "$i" "$i" "$i" >> "$many"
  done
  printf ']}' >> "$many"
  run bash -c "DEFECT_SCAN_SEMGREP_TRACE_MAX=2 '$DETECT' semgrep-trace < '$many'"
  [ "$status" -eq 0 ]
  count=$(printf '%s\n' "$output" | grep -c '=== FINDING')
  [ "$count" -eq 2 ]
}

@test "manifest: exits 0 when it emits a (non-truncated) SCRIPT section" {
  repo="$BATS_TEST_TMPDIR/scexit"; mkdir -p "$repo/scripts"
  printf '{ "scripts": { "postinstall": "node scripts/setup.js" } }\n' > "$repo/package.json"
  printf 'require("https").get(process.env.NPM_TOKEN)\n' > "$repo/scripts/setup.js"
  run "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCRIPT: scripts/setup.js"* ]]
}

@test "manifest: resolves a referenced repo-local install script" {
  repo="$BATS_TEST_TMPDIR/npm2"; mkdir -p "$repo/scripts"
  printf '{ "scripts": { "postinstall": "node scripts/setup.js" } }\n' > "$repo/package.json"
  printf 'require("https").get(process.env.NPM_TOKEN)\n' > "$repo/scripts/setup.js"
  run "$DETECT" manifest "$repo"
  [[ "$output" == *"SCRIPT: scripts/setup.js"* ]]
  [[ "$output" == *"process.env.NPM_TOKEN"* ]]
}

@test "manifest: refuses unsafe script references (abs / traversal / node_modules)" {
  repo="$BATS_TEST_TMPDIR/npm3"; mkdir -p "$repo"
  printf '{ "scripts": { "postinstall": "node /etc/evil.js && node ../x.js && node node_modules/y.js" } }\n' > "$repo/package.json"
  run "$DETECT" manifest "$repo"
  [[ "$output" != *"SCRIPT: /etc/evil.js"* ]]
  [[ "$output" != *"SCRIPT: ../x.js"* ]]
  [[ "$output" != *"SCRIPT: node_modules"* ]]
}

@test "manifest: truncates an oversized resolved script" {
  repo="$BATS_TEST_TMPDIR/npm4"; mkdir -p "$repo/scripts"
  printf '{ "scripts": { "postinstall": "node scripts/big.js" } }\n' > "$repo/package.json"
  i=0; while [ "$i" -lt 300 ]; do echo "line$i"; i=$((i+1)); done > "$repo/scripts/big.js"
  run "$DETECT" manifest "$repo"
  [[ "$output" == *"SCRIPT: scripts/big.js"* ]]
  [[ "$output" == *"truncated"* ]]
}

@test "supply-chain-config: reads project-layer internal scopes" {
  repo="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$repo/.defect-scan"
  printf '# ours\ninternal_scope=@acme\ninternal_registry=https://npm.acme.internal\n' > "$repo/.defect-scan/supply-chain.conf"
  run "$DETECT" supply-chain-config "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"internal_scope=@acme"* ]]
  [[ "$output" == *"internal_registry=https://npm.acme.internal"* ]]
}

@test "supply-chain-config: absent files are a clean no-op" {
  repo="$BATS_TEST_TMPDIR/nocfg"; mkdir -p "$repo"
  run "$DETECT" supply-chain-config "$repo"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "supply-chain-config: unknown directive warns on stderr, valid lines still emitted" {
  repo="$BATS_TEST_TMPDIR/cfg2"; mkdir -p "$repo/.defect-scan"
  printf 'internal_scope=@ok\nbogus_key=whatever\n' > "$repo/.defect-scan/supply-chain.conf"
  run sh -c '"$0" supply-chain-config "$1" 2>/dev/null' "$DETECT" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"internal_scope=@ok"* ]]
  [[ "$output" != *"bogus_key"* ]]   # invalid key not in stdout (it goes to stderr)
}

@test "supply-chain-config: DEFECT_SCAN_NO_PROJECT hides the project layer" {
  repo="$BATS_TEST_TMPDIR/cfg3"; mkdir -p "$repo/.defect-scan"
  printf 'internal_scope=@hidden\n' > "$repo/.defect-scan/supply-chain.conf"
  run env DEFECT_SCAN_NO_PROJECT=1 "$DETECT" supply-chain-config "$repo"
  [ "$status" -eq 0 ]; [[ "$output" != *"@hidden"* ]]
}

@test "patterns: lists built-in supply-chain.md alongside recurring.md" {
  run "$DETECT" patterns "$BATS_TEST_TMPDIR"
  [[ "${lines[0]}" == *"recurring.md" ]]
  [[ "$output" == *"patterns/supply-chain.md"* ]]
}

@test "supply-chain.md defines P11-P14 mapped to cat#6" {
  f="$BATS_TEST_DIRNAME/../skills/scan/patterns/supply-chain.md"
  for p in P11 P12 P13 P14; do grep -q "$p" "$f"; done
  grep -qi "cat#6" "$f"
}

@test "SKILL.md wires the manifest hook and cat#6" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -q "detect.sh manifest" "$f"
  grep -qi "cat#6\|supply-chain" "$f"
}

@test "report-format documents cat#6" {
  grep -qi "cat#6\|supply-chain" "$BATS_TEST_DIRNAME/../skills/scan/report-format.md"
}

@test "Codex driver mirrors the manifest hook + cat#6" {
  f="$BATS_TEST_DIRNAME/../codex/defect-scan.md"
  grep -q "detect.sh manifest" "$f"
  grep -qi "cat#6\|supply-chain" "$f"
}

@test "supply-chain corpus has labeled buggy + empty clean cases" {
  d="$BATS_TEST_DIRNAME/../tests/eval/supply-chain/seen"
  [ -d "$d" ]
  grep -rq "cat#6" "$d"/*.expected
  found_empty=0; for e in "$d"/*.expected; do [ -s "$e" ] || found_empty=1; done; [ "$found_empty" -eq 1 ]
}

@test "supply-chain corpus: each sidecar has a sibling directory and valid labels" {
  d="$BATS_TEST_DIRNAME/../tests/eval/supply-chain/seen"
  for e in "$d"/*.expected; do
    base="$(basename "$e" .expected)"
    [ -d "$d/$base" ]   # sibling mini-repo dir exists
    while IFS= read -r ln || [ -n "$ln" ]; do
      [ -n "$ln" ] || continue
      echo "$ln" | grep -Eq '^[^:]+:[0-9]+:cat#6$'   # relpath:line:cat#6
    done < "$e"
  done
}

@test "docs reflect cat#6 and multi-file fixtures" {
  root="$BATS_TEST_DIRNAME/.."
  grep -qi "six\|cat#6\|supply-chain" "$root/README.md"
  ! grep -q "9 battle-tested patterns" "$root/commands/help.md"
  grep -qi "multi-file\|fixture repo\|directory fixture" "$root/tests/eval/README.md"
}

# Eval Loop-Closing Harness & Completeness Critic — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the eval loop for #15 — actually run a defect scan over the labeled corpus, score it against a committed per-split baseline, and add a model-free completeness critic — without ever putting a model inside `detect.sh`.

**Architecture:** Three new model-free `detect.sh` subcommands (`eval-categories`, `eval-run`, `eval-gaps`) plus two internal helpers (`eval_corpus_root`, `extract_eval_block`). The only model-bearing parts are swappable runner scripts under `tests/eval/runners/` (outside `lib/`), selected via `DEFECT_SCAN_EVAL_RUNNER`. `eval-run` invokes the runner per source fixture, accumulates findings into one file per run, and scores the whole split once per run with the existing `cmd_eval` (which keys by basename across a corpus dir). Everything is proven offline with a stub runner — no model in CI.

**Tech Stack:** POSIX `sh` + `awk` (`skills/scan/lib/detect.sh`), `bats` (`tests/detect.bats`), Markdown (eval-mode prompt snippet, docs), GitHub Actions (`workflow_dispatch`).

---

## Plain-English summary

Today defect-scan can *grade* a list of findings against a set of known-buggy and
known-clean example files, but nothing actually runs the scanner to produce that list
— the tests hand the grader a fake answer sheet. This plan builds the missing piece: a
maintainer-run harness that takes a real scan, runs it over each example file a few
times (the AI is non-deterministic, so we average several runs), collects what it
found, and scores it. If a change to the defect "knowledge" makes the scanner noisier
(more false alarms), the harness catches it against a saved baseline and goes red.

Two safety rules from Phase 1 are preserved exactly. First, the engine (`detect.sh`)
never calls a model — the AI call lives only in small swappable "runner" scripts kept
outside the engine, so the grader stays deterministic and fully testable with a fake
runner. Second, the AI never writes its own answer key: a "completeness critic" can
point out coverage gaps and even draft example *code*, but a human writes the
correctness labels and merges them through a reviewed pull request. We also harden the
runners (read-only AI permissions) and make the harness a manual, approval-gated CI job
so a secret-bearing run can never execute attacker-modified scripts.

Java's example set is already complete and stays untouched; Java is simply the first
language to get a second "held-out" example set, which lets us prove the
overfitting check end-to-end.

---

## File structure

```
skills/scan/lib/detect.sh                  # + eval_corpus_root, extract_eval_block helpers;
                                           #   + cmd_eval_categories, cmd_eval_run, cmd_eval_gaps;
                                           #   + dispatch entries; + preflight note for runner
skills/scan/eval-mode.md                   # NEW shared eval-mode prompt snippet (the <<<EVAL>>> contract)
skills/scan/SKILL.md                       # + reference to eval-mode.md (Stage 4 / eval addendum)
codex/defect-scan.md                       # + reference to eval-mode.md (same contract, both harnesses)
tests/eval/runners/claude.sh               # NEW model runner (read-only Claude)
tests/eval/runners/codex.sh                # NEW model runner (read-only Codex sandbox)
tests/eval/<lang>/baseline.seen.txt        # NEW per-language seen baseline
tests/eval/java/baseline.held-out.txt      # NEW (pilot) held-out baseline
tests/eval/java/held-out/                  # NEW (pilot) held-out fixtures + .expected
tests/eval/_proposals/.gitkeep             # NEW staging dir the grader ignores
tests/eval/README.md                       # + eval-run / runners / baselines / registry / _proposals docs
tests/fixtures/eval-runner-stub            # NEW deterministic stub runner for offline tests
tests/detect.bats                          # + harness/categories/gaps/sentinel tests; corpus-list update
.gitignore                                 # + tests/eval/*/.last-run.*
.github/workflows/eval-run.yml             # NEW manual, approval-gated harness job
CONTRIBUTING.md, README.md                 # + escaped-bug→fixture workflow + caveat
```

### Contracts used across tasks (define once, referenced everywhere)

Internal helpers (lowercase; not in the dispatch table):
- `eval_corpus_root` → echoes the corpus root: `${DEFECT_SCAN_EVAL_CORPUS:-<repo>/tests/eval}`,
  where `<repo>` is `$(skill_dir)/../..`. Tests override `DEFECT_SCAN_EVAL_CORPUS`.
- `extract_eval_block` → reads runner output on **stdin**; writes validated
  `<path>:<line>:<category>` lines to **stdout** (possibly empty). Exit `0` = exactly
  one well-formed block (empty allowed); exit `4` = **protocol error** (zero blocks,
  >1 block, or any malformed line). This is the missing≠empty distinction.

Subcommands (model-free; added to `main()` dispatch):
- `eval-categories <lang>` → prints the valid label set, one per line, sorted:
  `cat#1`..`cat#5` ∪ every label appearing in `<corpus>/<lang>/*/*.expected`.
- `eval-run <lang> [--runs N] [--split seen|held-out|all] [--update-baseline]` →
  per split: N runs × (per-fixture runner → accumulate → score split once via
  `cmd_eval`); aggregate mean±stddev; clean-fixture-FP rate; write `.last-run` artifact;
  gate vs `baseline.<split>.txt`. Exit `3` if `DEFECT_SCAN_EVAL_RUNNER` unset; exit
  nonzero on **FAIL**; `0` on PASS/WARN/FLAG (printed distinctly). `--update-baseline`
  writes current means into the baseline file (for a human to commit) and does not gate.
- `eval-gaps <lang> [--split seen|held-out]` → reads the `.last-run.<split>.txt`
  artifact + `eval-categories` and prints per-category coverage gaps. No writes.

Artifact `tests/eval/<lang>/.last-run.<split>.txt` (flat, no jq):
```
runs=5
mean_precision=0.94
stddev_precision=0.03
mean_recall=0.75
stddev_recall=0.06
clean_fp_runs=1
@findings
BugEmptyCatch.java:4:cat#2
BugSqlInjection.java:5:cat#3
```
(`@findings` holds the **last** run's accumulated findings; lines after it are the
sentinel-validated `basename:line:category` set.)

Baseline `tests/eval/<lang>/baseline.<split>.txt` (flat key=value):
```
precision_floor=0.90
recall_floor=0.70
precision_baseline=0.94
recall_baseline=0.75
noise_band=0.05
overfit_band=0.10
```

Gate (per split, on aggregated means):
- **FAIL** if `mean_precision < precision_floor` OR `mean_precision < precision_baseline - noise_band`.
- **FLAG** if `clean_fp_runs > 0`; or (under `--split all`) if `seen_mean_precision - heldout_mean_precision > overfit_band`.
- **WARN** if `mean_recall < recall_floor`.
- else **PASS**. Exit nonzero only on FAIL.

---

## Phase 0 — Scaffolding (staging dir, gitignore, stub runner)

**Exit criteria:** `_proposals/` staging dir exists and is grader-ignored; `.last-run.*`
is gitignored; a deterministic stub runner exists for later offline tests; suite still green.

### Task 0.1: Staging dir + gitignore

**Files:**
- Create: `tests/eval/_proposals/.gitkeep`
- Modify: `.gitignore`

- [ ] **Step 1: Create the staging dir**

```bash
mkdir -p tests/eval/_proposals
printf '# Staging area for completeness-critic fixture DRAFTS.\n# eval-run and cmd_eval IGNORE this dir. Humans author .expected here, then move\n# the fixture into <lang>/seen or <lang>/held-out via a CODEOWNERS-reviewed PR.\n' > tests/eval/_proposals/.gitkeep
```

- [ ] **Step 2: Ignore the run artifact**

Add to `.gitignore` (create the file if absent):

```
# defect-scan eval harness: transient per-run record (not ground truth)
tests/eval/*/.last-run.*
```

- [ ] **Step 3: Commit**

```bash
git add tests/eval/_proposals/.gitkeep .gitignore
git commit -m "chore(eval): staging dir + gitignore run artifact (#15)"
```

### Task 0.2: Deterministic stub runner

The stub emits canned runner output (including the `<<<EVAL>>>` block) driven by an
env var, so bats can simulate every case offline. It takes the same args as a real
runner (`<fixture-path> <lang>`) and ignores them except for echoing the basename.

**Files:**
- Create: `tests/fixtures/eval-runner-stub`

- [ ] **Step 1: Write the stub**

```sh
#!/usr/bin/env sh
# Deterministic stub runner for the eval harness tests (no model).
# Usage: eval-runner-stub <fixture-path> <lang>
# Behavior is driven by DEFECT_SCAN_STUB_MODE so a test can simulate each case:
#   ok        -> emit a correct block keyed by the fixture basename + DEFECT_SCAN_STUB_FINDING
#   empty     -> emit a present-but-empty block (legit "no findings"; correct for clean)
#   missing   -> emit NO block (protocol error)
#   dup       -> emit two blocks (protocol error)
#   malformed -> emit a block with a bad line (protocol error)
# DEFECT_SCAN_STUB_FINDING = "<line>:<category>" appended after the basename (mode=ok).
set -eu
fixture="${1:?stub: need fixture path}"
base="$(basename "$fixture")"
mode="${DEFECT_SCAN_STUB_MODE:-ok}"
finding="${DEFECT_SCAN_STUB_FINDING:-1:cat#2}"
echo "stub scan report for $base"        # stand-in for the human report
case "$mode" in
  ok)        printf '<<<EVAL\n%s:%s\nEVAL>>>\n' "$base" "$finding" ;;
  empty)     printf '<<<EVAL\nEVAL>>>\n' ;;
  missing)   : ;;                          # no block at all
  dup)       printf '<<<EVAL\n%s:%s\nEVAL>>>\n<<<EVAL\nEVAL>>>\n' "$base" "$finding" ;;
  malformed) printf '<<<EVAL\nnot-a-valid-line\nEVAL>>>\n' ;;
  *)         echo "stub: unknown mode $mode" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Make it executable + syntax-check**

```bash
chmod +x tests/fixtures/eval-runner-stub
sh -n tests/fixtures/eval-runner-stub && echo OK
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add tests/fixtures/eval-runner-stub
git commit -m "test(eval): deterministic stub runner for offline harness tests (#15)"
```

---

## Phase 1 — `eval-categories` (the category registry)

**Exit criteria:** `detect.sh eval-categories <lang>` prints `cat#1..5` ∪ the language's
corpus labels (sorted, deduped); bats proves rust includes `panic`, yaml `coerce`,
shell `quoting`.

### Task 1.1: `eval_corpus_root` helper + `eval-categories`

**Files:**
- Modify: `skills/scan/lib/detect.sh` (add helper + `cmd_eval_categories`; add dispatch)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/detect.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/detect.bats -f "eval-categories"`
Expected: FAIL (`eval-categories` not in dispatch → usage/error).

- [ ] **Step 3: Implement the helper + subcommand**

Add near the other helpers in `detect.sh` (after `skill_dir`):

```sh
# eval_corpus_root: where the labeled eval corpus lives. Defaults to the repo's
# tests/eval (resolved from this script's location), overridable for tests.
eval_corpus_root() {
  printf '%s\n' "${DEFECT_SCAN_EVAL_CORPUS:-$(skill_dir)/../../tests/eval}"
}
```

Add with the other `cmd_*` functions:

```sh
# eval-categories <lang>: the authoritative valid-label set for a language —
# baseline cat#1..5 UNION every label present in that language's corpus .expected
# files. Model-FREE (pure set union over existing artifacts). Used by eval-mode (tell
# the model which labels to emit) and eval-gaps (per-category coverage denominator).
cmd_eval_categories() {
  lang="${1:?usage: detect.sh eval-categories <lang>}"
  root="$(eval_corpus_root)"
  [ -d "$root/$lang" ] || { echo "eval-categories: no corpus for '$lang' under $root" >&2; return 2; }
  {
    printf 'cat#1\ncat#2\ncat#3\ncat#4\ncat#5\n'
    # labels are the part after "<line>:" in each non-empty, non-comment .expected line
    find "$root/$lang" -name '*.expected' -type f 2>/dev/null | while IFS= read -r f; do
      while IFS= read -r ln || [ -n "$ln" ]; do
        [ -n "$ln" ] || continue
        case "$ln" in \#*) continue ;; esac
        printf '%s\n' "${ln#*:}"
      done < "$f"
    done
  } | sort -u
}
```

Add to `main()` dispatch (next to `eval)`):

```sh
    eval-categories) cmd_eval_categories "$@" ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/detect.bats -f "eval-categories"`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(eval): eval-categories registry (baseline + corpus labels) (#15)"
```

---

## Phase 2 — `extract_eval_block` (strict sentinel parsing)

**Exit criteria:** Helper accepts exactly one well-formed block (empty allowed),
returns exit 4 on missing/duplicate/malformed; bats proves missing≠empty.

### Task 2.1: Sentinel extraction helper

**Files:**
- Modify: `skills/scan/lib/detect.sh` (add `extract_eval_block`; add a hidden dispatch
  `__evalblock` so bats can exercise it directly, mirroring `__fmget`/`__fmfield`)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing tests**

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/detect.bats -f "extract_eval_block"`
Expected: FAIL (`__evalblock` not dispatched).

- [ ] **Step 3: Implement the helper**

```sh
# extract_eval_block: read runner output on stdin; emit the validated findings of the
# single <<<EVAL ... EVAL>>> block to stdout (possibly empty). Exit 4 = PROTOCOL ERROR:
# zero blocks, more than one block, or any malformed line. The missing(=4) vs
# empty(=0, no output) distinction is load-bearing — a missing block on a clean fixture
# must NOT score as a perfect run.
extract_eval_block() {
  in="$(cat)"
  nstart=$(printf '%s\n' "$in" | grep -c '^<<<EVAL$' 2>/dev/null || true)
  nend=$(printf '%s\n' "$in" | grep -c '^EVAL>>>$' 2>/dev/null || true)
  [ "$nstart" = "1" ] && [ "$nend" = "1" ] || return 4
  body=$(printf '%s\n' "$in" | sed -n '/^<<<EVAL$/,/^EVAL>>>$/p' | sed '1d;$d')
  # every non-empty body line must be <path>:<line>:<category>
  bad=$(printf '%s\n' "$body" | grep -vE '^$|^[^:]+:[0-9]+:[^:]+$' | grep -c . 2>/dev/null || true)
  [ "$bad" = "0" ] || return 4
  # print non-empty lines only (empty block => no output)
  printf '%s\n' "$body" | grep -v '^$' || true
}
```

Add to `main()` dispatch (with the other hidden `__` helpers):

```sh
    __evalblock) extract_eval_block ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/detect.bats -f "extract_eval_block"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(eval): strict sentinel-block extraction (missing != empty) (#15)"
```

---

## Phase 3 — `eval-run` core (loop, accumulate, score, aggregate)

**Exit criteria:** With the stub runner, `eval-run <lang> --runs N` scans per fixture,
accumulates, scores the split once per run via `cmd_eval`, prints mean±stddev and the
clean-FP rate; exits 3 when the runner is unset; a missing block marks the run partial.

### Task 3.1: `eval-run` aggregation over a stubbed corpus

**Files:**
- Modify: `skills/scan/lib/detect.sh` (add `cmd_eval_run`; dispatch)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing tests**

Helper fixture corpus built inline (one bug + one clean):

```bash
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
  # stub emits the correct finding for the bug fixture (mode ok, 4:cat#2) and the
  # clean fixture gets the same canned finding too -> would be an FP, so use a
  # per-basename stub: see DEFECT_SCAN_STUB_FINDING handling below.
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
  # every fixture (incl. clean) emits 4:cat#2 -> clean fixture has an FP in both runs
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
```

Add a `perfect` mode to the stub (`tests/fixtures/eval-runner-stub`): emit the bug's
expected finding for `bug_*` basenames and an **empty** block for `clean_*` basenames,
so a "perfect" scanner scores 1.00 with no clean FP. Update the stub `case`:

```sh
  perfect)
    case "$base" in
      clean_*|Clean*) printf '<<<EVAL\nEVAL>>>\n' ;;
      *)              printf '<<<EVAL\n%s:%s\nEVAL>>>\n' "$base" "$finding" ;;
    esac ;;
```
(For the `perfect` test, the bug fixture's `.expected` is `4:cat#2`, matching the
default `DEFECT_SCAN_STUB_FINDING`.)

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/detect.bats -f "eval-run"`
Expected: FAIL (`eval-run` not dispatched).

- [ ] **Step 3: Implement `cmd_eval_run` (Phase-3 scope: aggregate + report, no gate yet)**

```sh
# eval-run <lang> [--runs N] [--split seen|held-out|all] [--update-baseline]
# Model-FREE orchestrator. Per split: N runs, each run scans every SOURCE fixture via
# the swappable $DEFECT_SCAN_EVAL_RUNNER (per-fixture), accumulates findings into one
# file, and scores the whole split ONCE with cmd_eval. Aggregates mean/stddev and the
# clean-fixture FP rate, writes the .last-run artifact, then gates (Phase 4).
cmd_eval_run() {
  lang=""; runs=5; split="seen"; update=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --runs) runs="${2:?}"; shift 2 ;;
      --split) split="${2:?}"; shift 2 ;;
      --update-baseline) update=1; shift ;;
      -*) echo "eval-run: unknown flag $1" >&2; return 2 ;;
      *) [ -z "$lang" ] && lang="$1" || { echo "eval-run: unexpected arg $1" >&2; return 2; }; shift ;;
    esac
  done
  [ -n "$lang" ] || { echo "usage: detect.sh eval-run <lang> [--runs N] [--split seen|held-out|all]" >&2; return 2; }
  runner="${DEFECT_SCAN_EVAL_RUNNER:-}"
  [ -n "$runner" ] || { echo "eval-run: set DEFECT_SCAN_EVAL_RUNNER to a runner script (tests/eval/runners/*.sh)" >&2; return 3; }
  root="$(eval_corpus_root)"
  case "$split" in all) splits="seen held-out" ;; *) splits="$split" ;; esac

  overall_rc=0
  for sp in $splits; do
    dir="$root/$lang/$sp"
    if [ ! -d "$dir" ]; then
      [ "$split" = all ] && { echo "eval-run: $lang/$sp absent — skipping"; continue; }
      echo "eval-run: corpus split not found: $dir" >&2; return 2
    fi
    # collect per-run precision/recall and clean-FP flags
    pvals=""; rvals=""; clean_fp_runs=0; partial=0
    last_findings=""
    r=1
    while [ "$r" -le "$runs" ]; do
      findings="$(mktemp 2>/dev/null || echo "/tmp/ds-er-$$.$r")"
      for src in "$dir"/*; do
        case "$src" in *.expected) continue ;; esac
        [ -f "$src" ] || continue
        out="$("$runner" "$src" "$lang" 2>/dev/null)" || { partial=1; continue; }
        block="$(printf '%s' "$out" | extract_eval_block)" || { partial=1; continue; }
        [ -n "$block" ] && printf '%s\n' "$block" >> "$findings"
      done
      # score the whole split once for this run
      m="$(cmd_eval "$dir" "$findings")"   # "precision=.. recall=.. tp=.. fp=.. fn=.."
      p="$(printf '%s\n' "$m" | sed -n 's/.*precision=\([0-9.]*\).*/\1/p')"
      rr="$(printf '%s\n' "$m" | sed -n 's/.*recall=\([0-9.]*\).*/\1/p')"
      pvals="$pvals $p"; rvals="$rvals $rr"
      # clean-fixture FP: any clean fixture (empty .expected) present in findings?
      if eval_clean_fp "$dir" "$findings"; then clean_fp_runs=$((clean_fp_runs+1)); fi
      last_findings="$(cat "$findings")"
      rm -f "$findings"
      r=$((r+1))
    done

    # aggregate
    mp="$(_eval_mean $pvals)"; sp_p="$(_eval_stddev $pvals)"
    mr="$(_eval_mean $rvals)"; sp_r="$(_eval_stddev $rvals)"

    # write artifact
    art="$root/$lang/.last-run.$sp.txt"
    {
      printf 'runs=%s\nmean_precision=%s\nstddev_precision=%s\nmean_recall=%s\nstddev_recall=%s\nclean_fp_runs=%s\n' \
        "$runs" "$mp" "$sp_p" "$mr" "$sp_r" "$clean_fp_runs"
      printf '@findings\n%s\n' "$last_findings"
    } > "$art"

    # report
    echo "eval-run $lang/$sp: runs=$runs mean_precision=$mp(±$sp_p) mean_recall=$mr(±$sp_r) clean_fp_runs=$clean_fp_runs"
    [ "$partial" = 1 ] && echo "eval-run $lang/$sp: PARTIAL — at least one fixture run was inconclusive (missing/invalid block)"

    # gate (Phase 4 fills this in; default PASS here)
    if [ "$update" = 1 ]; then
      eval_update_baseline "$root/$lang/baseline.$sp.txt" "$mp" "$mr"
      echo "eval-run $lang/$sp: baseline updated (commit via CODEOWNERS PR)"
    else
      eval_gate "$root/$lang/baseline.$sp.txt" "$mp" "$mr" "$clean_fp_runs" || overall_rc=1
    fi
  done
  return "$overall_rc"
}

# eval_clean_fp <dir> <findings>: exit 0 if any CLEAN fixture (empty .expected) appears
# in the findings file (an FP), else exit 1.
eval_clean_fp() {
  d="$1"; f="$2"
  for exp in "$d"/*.expected; do
    [ -f "$exp" ] || continue
    [ -s "$exp" ] && continue                 # non-empty => buggy fixture, skip
    base="$(basename "$exp" .expected)"
    if grep -q "^$base:" "$f" 2>/dev/null || grep -q "/$base:" "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# _eval_mean / _eval_stddev: arithmetic mean and POPULATION stddev of space-separated
# decimals, printed to 2 dp. Empty input -> 0.00.
_eval_mean() { awk 'BEGIN{n=0;s=0; for(i=1;i<=ARGC-1;i++){s+=ARGV[i];n++}; printf "%.2f", n? s/n:0}' "$@"; }
_eval_stddev() {
  awk 'BEGIN{n=0;s=0; for(i=1;i<=ARGC-1;i++){a[++n]=ARGV[i];s+=ARGV[i]}
       if(!n){printf "0.00"; exit} m=s/n; v=0; for(i=1;i<=n;i++)v+=(a[i]-m)*(a[i]-m);
       printf "%.2f", sqrt(v/n)}' "$@"
}
```

> Note: `eval_gate` and `eval_update_baseline` are stubbed in Phase 4. For Phase 3,
> add temporary definitions so the suite runs: `eval_gate() { return 0; }` and
> `eval_update_baseline() { :; }`. Phase 4 replaces them.

Add to `main()` dispatch:

```sh
    eval-run) cmd_eval_run "$@" ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/detect.bats -f "eval-run"`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the whole suite + syntax check**

Run: `sh -n skills/scan/lib/detect.sh && bats tests/detect.bats`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add skills/scan/lib/detect.sh tests/detect.bats tests/fixtures/eval-runner-stub
git commit -m "feat(eval): eval-run orchestrator — per-fixture scan, per-split scoring, aggregation (#15)"
```

---

## Phase 4 — Baseline gate + `--update-baseline`

**Exit criteria:** `eval_gate` enforces precision floor + erosion + clean-FP FLAG +
recall WARN with correct exit codes; `--update-baseline` writes the baseline file;
bats proves PASS/WARN/FLAG/FAIL transitions; per-language `baseline.seen.txt` committed.

### Task 4.1: Gate + baseline writer

**Files:**
- Modify: `skills/scan/lib/detect.sh` (replace the Phase-3 stubs)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing tests**

```bash
_mk_baseline() {  # $1=path  $2=pfloor $3=rfloor $4=pbase $5=rbase $6=noise
  printf 'precision_floor=%s\nrecall_floor=%s\nprecision_baseline=%s\nrecall_baseline=%s\nnoise_band=%s\noverfit_band=0.10\n' \
    "$2" "$3" "$4" "$5" "$6" > "$1"
}

@test "eval_gate: PASS when precision >= floor and recall ok" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run sh -c '. "$0"; eval_gate "$1" 0.95 0.80 0' "$DETECT" "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "eval_gate: FAIL when mean precision below floor" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run sh -c '. "$0"; eval_gate "$1" 0.80 0.80 0' "$DETECT" "$b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "eval_gate: FAIL on erosion (precision below baseline - noise_band)" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.50 0.50 0.94 0.75 0.05
  run sh -c '. "$0"; eval_gate "$1" 0.85 0.80 0' "$DETECT" "$b"   # 0.85 < 0.94-0.05
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "eval_gate: FLAG (exit 0) when clean-FP runs > 0" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run sh -c '. "$0"; eval_gate "$1" 0.95 0.80 2' "$DETECT" "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FLAG"* ]]
}

@test "eval_gate: WARN (exit 0) when recall below floor" {
  b="$BATS_TEST_TMPDIR/b.txt"; _mk_baseline "$b" 0.90 0.70 0.94 0.75 0.05
  run sh -c '. "$0"; eval_gate "$1" 0.95 0.60 0' "$DETECT" "$b"
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
```

> The `. "$0"` sourcing works because `detect.sh`'s `main` is only invoked under a
> `[ "${0##*/}" = detect.sh ] ... ` guard at the bottom — **verify that guard exists**;
> if `main "$@"` is called unconditionally, wrap it: `case "${0##*/}" in detect.sh|*detect.sh) main "$@";; esac` so sourcing for tests doesn't run `main`. (Add this guard as Step 3a if missing.)

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/detect.bats -f "eval_gate|update-baseline"`
Expected: FAIL (gate is a stub returning 0; no FLAG/WARN/FAIL text).

- [ ] **Step 3: Implement gate + writer (replace Phase-3 stubs)**

```sh
# _bv <file> <key>: read a key=value baseline value (empty if absent).
_bv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# eval_gate <baseline-file> <mean_precision> <mean_recall> <clean_fp_runs>
# Precision-first. Prints one verdict line; exit nonzero ONLY on FAIL.
eval_gate() {
  bf="$1"; mp="$2"; mr="$3"; cfp="$4"
  pf="$(_bv "$bf" precision_floor)"; rf="$(_bv "$bf" recall_floor)"
  pb="$(_bv "$bf" precision_baseline)"; nb="$(_bv "$bf" noise_band)"
  [ -n "$pf" ] || pf=0; [ -n "$rf" ] || rf=0; [ -n "$pb" ] || pb=0; [ -n "$nb" ] || nb=0
  # FAIL: below absolute floor OR eroded below baseline-noise_band
  if awk -v p="$mp" -v f="$pf" -v b="$pb" -v n="$nb" 'BEGIN{exit !(p<f || p<(b-n))}'; then
    echo "eval-gate: FAIL — mean_precision=$mp (floor=$pf, baseline=$pb, noise_band=$nb)"
    return 1
  fi
  rc_msg="PASS"
  [ "${cfp:-0}" -gt 0 ] 2>/dev/null && rc_msg="FLAG (clean-fixture FP in $cfp run(s))"
  if awk -v r="$mr" -v f="$rf" 'BEGIN{exit !(r<f)}'; then
    rc_msg="$rc_msg; WARN (mean_recall=$mr < floor=$rf)"
  fi
  echo "eval-gate: $rc_msg — mean_precision=$mp mean_recall=$mr"
  return 0
}

# eval_update_baseline <baseline-file> <mean_precision> <mean_recall>
# Writes/refreshes the recorded baseline means, PRESERVING existing floors/bands.
eval_update_baseline() {
  bf="$1"; mp="$2"; mr="$3"
  pf="$(_bv "$bf" precision_floor)"; rf="$(_bv "$bf" recall_floor)"
  nb="$(_bv "$bf" noise_band)"; ob="$(_bv "$bf" overfit_band)"
  [ -n "$pf" ] || pf=0.90; [ -n "$rf" ] || rf=0.70; [ -n "$nb" ] || nb=0.05; [ -n "$ob" ] || ob=0.10
  printf 'precision_floor=%s\nrecall_floor=%s\nprecision_baseline=%s\nrecall_baseline=%s\nnoise_band=%s\noverfit_band=%s\n' \
    "$pf" "$rf" "$mp" "$mr" "$nb" "$ob" > "$bf"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/detect.bats -f "eval_gate|update-baseline"`
Expected: PASS (6 tests).

- [ ] **Step 5: Seed `baseline.seen.txt` for each language**

For each language under `tests/eval/`, generate a starting baseline from a real (or, in
absence of model creds, a hand-set conservative) baseline. Without model access, seed
conservative floors and leave the recorded baseline equal to the floor:

```bash
for d in tests/eval/*/; do
  lang="$(basename "$d")"; [ -d "$d/seen" ] || continue
  cat > "$d/baseline.seen.txt" <<'EOF'
precision_floor=0.80
recall_floor=0.50
precision_baseline=0.80
recall_baseline=0.50
noise_band=0.10
overfit_band=0.15
EOF
done
git add tests/eval/*/baseline.seen.txt
```
(Maintainers later run `eval-run <lang> --update-baseline` with a real runner and
commit the measured numbers via a CODEOWNERS PR — see Phase 6/8.)

- [ ] **Step 6: Commit**

```bash
git add skills/scan/lib/detect.sh tests/detect.bats tests/eval/*/baseline.seen.txt
git commit -m "feat(eval): precision-first baseline gate + --update-baseline (#15)"
```

---

## Phase 5 — `eval-gaps` (completeness critic, report half)

**Exit criteria:** `eval-gaps <lang>` reads the `.last-run` artifact + `eval-categories`
and prints, per category, expected vs detected counts (flagging zero-coverage and
weak-recall categories); model-free; bats proves it against a synthetic artifact.

### Task 5.1: `eval-gaps`

**Files:**
- Modify: `skills/scan/lib/detect.sh` (add `cmd_eval_gaps`; dispatch)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing test**

```bash
@test "eval-gaps: flags a category with expected defects but zero detected" {
  c="$BATS_TEST_TMPDIR/c"; mkdir -p "$c/foo/seen"
  printf 'x\n' > "$c/foo/seen/bug_a.ext"; printf '3:cat#3\n' > "$c/foo/seen/bug_a.ext.expected"
  printf 'x\n' > "$c/foo/seen/bug_b.ext"; printf '4:cat#4\n' > "$c/foo/seen/bug_b.ext.expected"
  # last-run found cat#3 but MISSED cat#4
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
  [[ "$output" == *"cat#4"* ]]            # the missed category is surfaced
  [[ "$output" == *"0 detected"* ]] || [[ "$output" == *"GAP"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/detect.bats -f "eval-gaps"`
Expected: FAIL (not dispatched).

- [ ] **Step 3: Implement `cmd_eval_gaps`**

```sh
# eval-gaps <lang> [--split seen|held-out]: model-FREE completeness critic (report
# half). Reads the .last-run artifact (last run's findings + recall) and reports, per
# category in the registry, how many defects the corpus EXPECTS vs how many the last
# run DETECTED. Surfaces zero-coverage and weak categories. No writes; no model.
cmd_eval_gaps() {
  lang=""; split="seen"
  while [ $# -gt 0 ]; do
    case "$1" in
      --split) split="${2:?}"; shift 2 ;;
      -*) echo "eval-gaps: unknown flag $1" >&2; return 2 ;;
      *) lang="$1"; shift ;;
    esac
  done
  [ -n "$lang" ] || { echo "usage: detect.sh eval-gaps <lang> [--split seen|held-out]" >&2; return 2; }
  root="$(eval_corpus_root)"; dir="$root/$lang/$split"
  art="$root/$lang/.last-run.$split.txt"
  [ -d "$dir" ] || { echo "eval-gaps: no corpus split: $dir" >&2; return 2; }
  [ -f "$art" ] || { echo "eval-gaps: no run artifact ($art) — run 'eval-run $lang --split $split' first" >&2; return 2; }

  # expected counts per category, from the corpus .expected files (ground truth)
  exp_counts="$(
    for e in "$dir"/*.expected; do
      [ -s "$e" ] || continue
      while IFS= read -r ln || [ -n "$ln" ]; do
        [ -n "$ln" ] || continue; case "$ln" in \#*) continue ;; esac
        printf '%s\n' "${ln#*:}"
      done < "$e"
    done | sort | uniq -c
  )"
  # detected categories from the artifact's @findings section
  det="$(sed -n '/^@findings$/,$p' "$art" | sed '1d')"

  echo "eval-gaps $lang/$split:"
  printf '%s\n' "$exp_counts" | while read -r cnt cat; do
    [ -n "$cat" ] || continue
    found="$(printf '%s\n' "$det" | grep -c ":$cat\$" 2>/dev/null || true)"
    if [ "${found:-0}" -eq 0 ]; then
      echo "  GAP: $cat — $cnt expected, 0 detected"
    elif [ "$found" -lt "$cnt" ]; then
      echo "  weak: $cat — $cnt expected, $found detected"
    else
      echo "  ok:   $cat — $cnt expected, $found detected"
    fi
  done
  # categories in the registry with NO corpus coverage at all
  cmd_eval_categories "$lang" | while IFS= read -r cat; do
    printf '%s\n' "$exp_counts" | grep -q " $cat\$" || echo "  uncovered: $cat — no corpus fixtures"
  done
}
```

Add to `main()` dispatch:

```sh
    eval-gaps) cmd_eval_gaps "$@" ;;
```

- [ ] **Step 4: Run to verify pass + whole suite**

Run: `bats tests/detect.bats -f "eval-gaps" && bats tests/detect.bats`
Expected: PASS; full suite green.

- [ ] **Step 5: Commit**

```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(eval): eval-gaps completeness critic (report half, model-free) (#15)"
```

---

## Phase 6 — Real runners + shared eval-mode prompt

**Exit criteria:** `eval-mode.md` defines the `<<<EVAL>>>` contract; both drivers
reference it; `claude.sh`/`codex.sh` exist, are read-only, `sh -n`-clean, and pass the
shellcheck the CI runs; a guard test asserts both runners are read-only and reference
`--lang`.

### Task 6.1: Shared eval-mode snippet + driver references

**Files:**
- Create: `skills/scan/eval-mode.md`
- Modify: `skills/scan/SKILL.md`, `codex/defect-scan.md`
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing test**

```bash
@test "eval-mode contract exists and both drivers reference it" {
  root="$BATS_TEST_DIRNAME/.."
  [ -f "$root/skills/scan/eval-mode.md" ]
  grep -q "<<<EVAL" "$root/skills/scan/eval-mode.md"
  grep -q "EVAL>>>" "$root/skills/scan/eval-mode.md"
  grep -q "eval-mode" "$root/skills/scan/SKILL.md"
  grep -q "eval-mode" "$root/codex/defect-scan.md"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/detect.bats -f "eval-mode contract"`
Expected: FAIL.

- [ ] **Step 3: Create `skills/scan/eval-mode.md`**

```markdown
# Eval mode (machine-readable findings block)

Eval mode is signaled by the eval harness (`detect.sh eval-run` via a runner). It does
**not** change the normal scan: produce the usual human report exactly as always, then
append **one** machine-readable block so the model-free grader (`detect.sh eval`) can
score the run.

Rules (strict — the harness rejects anything else):
- Emit **exactly one** block, after the report:

      <<<EVAL
      <path>:<line>:<category>
      <path>:<line>:<category>
      EVAL>>>

- One finding per line, `<path>:<line>:<category>`. `<path>` is the scanned file's name
  (basename is fine — the grader matches on basename). `<line>` is an integer.
- `<category>` MUST be one of the language's valid labels (run
  `detect.sh eval-categories <lang>`): the baseline `cat#1`..`cat#5` plus that
  language's specific labels. An off-vocabulary label scores as a mismatch.
- If the scan found nothing, emit an **empty but present** block (the two sentinel lines
  with nothing between). Do **not** omit the block — a missing block is a protocol error.
- Report only what you actually found; eval mode is not a hint to inflate or suppress.
```

- [ ] **Step 4: Reference it from both drivers**

In `skills/scan/SKILL.md`, add to the Stage 4 (Report) area:

```markdown
**Eval mode (harness only).** When invoked by the eval harness, additionally follow
`eval-mode.md` to append the machine-readable `<<<EVAL>>>` findings block. Normal scans
never emit it.
```

In `codex/defect-scan.md`, add the same pointer (same wording) so both harnesses share
the one contract.

- [ ] **Step 5: Run to verify pass**

Run: `bats tests/detect.bats -f "eval-mode contract"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/scan/eval-mode.md skills/scan/SKILL.md codex/defect-scan.md tests/detect.bats
git commit -m "feat(eval): shared eval-mode prompt contract referenced by both drivers (#15)"
```

### Task 6.2: Read-only runner scripts

**Files:**
- Create: `tests/eval/runners/claude.sh`, `tests/eval/runners/codex.sh`
- Modify: `.github/workflows/ci.yml` (add the two runners to the `sh -n` loop)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing test**

```bash
@test "runners exist, are read-only, force --lang, and never write" {
  root="$BATS_TEST_DIRNAME/.."
  for rn in claude codex; do
    f="$root/tests/eval/runners/$rn.sh"
    [ -x "$f" ]
    sh -n "$f"
    grep -q -- "--lang" "$f"
  done
  grep -q -- "--sandbox read-only" "$root/tests/eval/runners/codex.sh"
  # claude runner must restrict tools to read-only (no Edit/Write/Bash-write)
  grep -Eq -- "--(permission-mode|allowedTools|disallowedTools)" "$root/tests/eval/runners/claude.sh"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/detect.bats -f "runners exist"`
Expected: FAIL.

- [ ] **Step 3: Write `tests/eval/runners/codex.sh`**

```sh
#!/usr/bin/env sh
# Eval runner (Codex). Scans ONE source fixture read-only and prints the scan output
# (which must contain the eval-mode <<<EVAL>>> block). Never writes — mirrors
# cmd_codex_verify's sandbox. Usage: codex.sh <fixture-path> <lang>
set -eu
fixture="${1:?codex.sh: need fixture path}"; lang="${2:?codex.sh: need lang}"
cx="${DEFECT_SCAN_CODEX:-codex}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$fixture" "$work/"                       # SOURCE only — never the .expected sidecar
prompt="$(mktemp)"
{
  echo "Run /defect-scan:scan on the file in this directory with --lang $lang."
  echo "Follow eval-mode.md: after the normal report, append exactly one <<<EVAL>>> block."
} > "$prompt"
cd "$work"
"$cx" exec --sandbox read-only --skip-git-repo-check -o /dev/stdout - < "$prompt"
rm -f "$prompt"
```

- [ ] **Step 4: Write `tests/eval/runners/claude.sh`**

```sh
#!/usr/bin/env sh
# Eval runner (Claude Code, headless, READ-ONLY). Scans ONE source fixture and prints
# output containing the eval-mode <<<EVAL>>> block. Read-only tool policy: no file
# writes, no shell mutation. Usage: claude.sh <fixture-path> <lang>
set -eu
fixture="${1:?claude.sh: need fixture path}"; lang="${2:?claude.sh: need lang}"
cc="${DEFECT_SCAN_CLAUDE:-claude}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$fixture" "$work/"                        # SOURCE only — never the .expected sidecar
cd "$work"
# Read-only: deny mutating tools so a runner can never edit the repo under test.
"$cc" -p "/defect-scan:scan $(basename "$fixture") --lang $lang ; then follow eval-mode.md and append one <<<EVAL>>> block" \
  --permission-mode plan \
  --disallowedTools "Edit,Write,NotebookEdit"
```

> If the local `claude` flag names differ, adjust to the equivalent read-only flags;
> the test only requires one of `--permission-mode|--allowedTools|--disallowedTools`
> and forbids granting write tools. Keep `codex.sh` as the CI-default runner.

- [ ] **Step 5: Make executable, add to CI syntax loop**

```bash
chmod +x tests/eval/runners/claude.sh tests/eval/runners/codex.sh
```
In `.github/workflows/ci.yml`, add both runner paths and the stub to the `sh -n` file
list in the "Shell syntax check" step.

- [ ] **Step 6: Run to verify pass**

Run: `bats tests/detect.bats -f "runners exist"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add tests/eval/runners/ .github/workflows/ci.yml tests/detect.bats
git commit -m "feat(eval): read-only Claude + Codex eval runners (#15)"
```

---

## Phase 7 — Java held-out pilot + overfit gate

**Exit criteria:** `tests/eval/java/held-out/` has ≥2 bug + ≥1 clean fixture with
`.expected`; `baseline.held-out.txt` exists; `eval-run java --split all` reports seen
and held-out separately and FLAGs when the seen−held-out precision gap exceeds
`overfit_band`; bats proves the overfit FLAG with the stub.

### Task 7.1: Java held-out fixtures + baseline

**Files:**
- Create: `tests/eval/java/held-out/Bug*.java(+.expected)`, `Clean*.java(+.expected)`,
  `tests/eval/java/baseline.held-out.txt`

- [ ] **Step 1: Add held-out fixtures (distinct from seen, same defect classes)**

Mirror the `seen/` style with new, non-duplicate examples. Minimum set:

```bash
mkdir -p tests/eval/java/held-out
# Bug: unvalidated path traversal (cat#3-style injection family)
cat > tests/eval/java/held-out/BugPathTraversal.java <<'EOF'
import java.io.*;
class BugPathTraversal {
  File open(String name) {
    return new File("/data/" + name);   // user-controlled name -> traversal
  }
}
EOF
printf '4:cat#3\n' > tests/eval/java/held-out/BugPathTraversal.java.expected

# Bug: ignored InterruptedException (cat#2 swallowed-exception family)
cat > tests/eval/java/held-out/BugSwallowedInterrupt.java <<'EOF'
class BugSwallowedInterrupt {
  void wait500() {
    try { Thread.sleep(500); } catch (InterruptedException e) { }  // swallowed
  }
}
EOF
printf '3:cat#2\n' > tests/eval/java/held-out/BugSwallowedInterrupt.java.expected

# Clean near-miss: properly restores interrupt status
cat > tests/eval/java/held-out/CleanRestoresInterrupt.java <<'EOF'
class CleanRestoresInterrupt {
  void wait500() {
    try { Thread.sleep(500); }
    catch (InterruptedException e) { Thread.currentThread().interrupt(); }
  }
}
EOF
: > tests/eval/java/held-out/CleanRestoresInterrupt.java.expected
```

- [ ] **Step 2: Seed the held-out baseline**

```bash
cat > tests/eval/java/baseline.held-out.txt <<'EOF'
precision_floor=0.80
recall_floor=0.50
precision_baseline=0.80
recall_baseline=0.50
noise_band=0.10
overfit_band=0.15
EOF
```

- [ ] **Step 3: Verify the grader reads the held-out split**

```bash
printf 'BugPathTraversal.java:4:cat#3\nBugSwallowedInterrupt.java:3:cat#2\n' > /tmp/hf
skills/scan/lib/detect.sh eval tests/eval/java/held-out /tmp/hf
```
Expected: `precision=1.00 recall=1.00 ...`

- [ ] **Step 4: Commit**

```bash
git add tests/eval/java/held-out tests/eval/java/baseline.held-out.txt
git commit -m "test(eval): java held-out split pilot + baseline (#15)"
```

### Task 7.2: Overfit FLAG in `eval-run --split all`

**Files:**
- Modify: `skills/scan/lib/detect.sh` (compute seen−held-out gap when `split=all`)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing test**

The stub can score `seen` perfectly but make `held-out` worse via a per-split env. Add a
`splitaware` stub mode that emits the correct finding only when the fixture path
contains `seen` (so held-out scores 0 recall, widening the gap):

Stub addition (`tests/fixtures/eval-runner-stub`):
```sh
  splitaware)
    case "$fixture" in
      */seen/*) printf '<<<EVAL\n%s:%s\nEVAL>>>\n' "$base" "$finding" ;;
      *)        printf '<<<EVAL\nEVAL>>>\n' ;;   # held-out: find nothing
    esac ;;
```

Test:
```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/detect.bats -f "overfitting"`
Expected: FAIL (no overfit comparison yet).

- [ ] **Step 3: Implement the overfit check**

In `cmd_eval_run`, after the per-split loop, when `split=all`, compare recorded means
from the two artifacts and FLAG. Add before `return "$overall_rc"`:

```sh
  if [ "$split" = all ]; then
    sa="$root/$lang/.last-run.seen.txt"; ha="$root/$lang/.last-run.held-out.txt"
    if [ -f "$sa" ] && [ -f "$ha" ]; then
      smp="$(_bv "$sa" mean_precision)"; hmp="$(_bv "$ha" mean_precision)"
      smr="$(_bv "$sa" mean_recall)";    hmr="$(_bv "$ha" mean_recall)"
      ob="$(_bv "$root/$lang/baseline.seen.txt" overfit_band)"; [ -n "$ob" ] || ob=0.15
      # Overfit shows as a seen-vs-held-out gap in EITHER metric: a profile memorized to
      # the seen set drops held-out RECALL; one tuned to avoid seen FPs drops held-out
      # PRECISION. (Precision alone misses the recall case — zero held-out findings score
      # a vacuous precision=1.00.)
      if awk -v sp="$smp" -v hp="$hmp" -v sr="$smr" -v hr="$hmr" -v o="$ob" \
           'BEGIN{exit !((sp-hp)>o || (sr-hr)>o)}'; then
        echo "eval-run $lang: FLAG overfit — seen P=$smp R=$smr vs held-out P=$hmp R=$hmr (gap > overfit_band $ob)"
      fi
    fi
  fi
```
(`_bv` was added in Phase 4.)

- [ ] **Step 4: Run to verify pass + whole suite**

Run: `bats tests/detect.bats -f "overfitting" && bats tests/detect.bats`
Expected: PASS; full suite green.

- [ ] **Step 5: Commit**

```bash
git add skills/scan/lib/detect.sh tests/detect.bats tests/fixtures/eval-runner-stub
git commit -m "feat(eval): seen-vs-held-out overfit FLAG in eval-run --split all (#15)"
```

---

## Phase 8 — Manual CI job + docs + corpus-list update

**Exit criteria:** A `workflow_dispatch` job runs `eval-run` from a trusted ref behind
an approval-gated Environment with read-only token; CONTRIBUTING/README/tests-README
document the workflow + caveat + new subcommands; the bats profile/corpus-list
assertions account for the new files; full suite + `sh -n` green.

### Task 8.1: Approval-gated manual workflow

**Files:**
- Create: `.github/workflows/eval-run.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: eval-run (manual)

# Manual ONLY. Never on PR/push: it spends a model + is non-deterministic. Runs from a
# trusted ref behind an approval-gated Environment so secret model creds are never
# exposed to PR-modified runner scripts (spec §6 security).
on:
  workflow_dispatch:
    inputs:
      lang:   { description: "language profile (e.g. java)", required: true }
      runs:   { description: "runs per fixture", required: false, default: "5" }
      split:  { description: "seen | held-out | all", required: false, default: "seen" }

permissions:
  contents: read            # minimal token

jobs:
  eval:
    runs-on: ubuntu-latest
    environment: eval-run    # configure with required reviewers + the model secret
    steps:
      - uses: actions/checkout@v4    # checks out the dispatched (trusted) ref
      - name: Install bats + jq
        run: sudo apt-get update && sudo apt-get install -y bats jq
      - name: Install codex (eval runner)
        run: echo "Provision the codex CLI here (org-specific)."
      - name: Run the eval harness
        env:
          DEFECT_SCAN_EVAL_RUNNER: tests/eval/runners/codex.sh
          CODEX_API_KEY: ${{ secrets.CODEX_API_KEY }}
        run: |
          sh skills/scan/lib/detect.sh eval-run "${{ inputs.lang }}" \
            --runs "${{ inputs.runs }}" --split "${{ inputs.split }}"
```

- [ ] **Step 2: Lint + commit**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/eval-run.yml'))" && echo "yaml ok"
git add .github/workflows/eval-run.yml
git commit -m "ci(eval): manual approval-gated eval-run workflow (trusted ref, read-only) (#15)"
```

### Task 8.2: Docs — workflow, caveat, subcommands

**Files:**
- Modify: `tests/eval/README.md`, `CONTRIBUTING.md`, `README.md`

- [ ] **Step 1: `tests/eval/README.md`** — document `eval-run`/`eval-categories`/
  `eval-gaps`, the runner contract + `DEFECT_SCAN_EVAL_RUNNER`, baseline files,
  `.last-run` artifact, and `_proposals/` (drafts staged here; humans label + PR).

- [ ] **Step 2: `CONTRIBUTING.md`** — add the self-improvement loop:

```markdown
### Reporting a confirmed false positive or an escaped production bug
1. Add a minimal fixture under `tests/eval/<lang>/seen/` (a `Bug*`/`bug_*` source for a
   real defect, or a `Clean*`/`clean_*` near-miss for a false positive).
2. Author its `.expected` sidecar: `<line>:<category>` per defect; an **empty** file for
   a clean fixture. Categories come from `detect.sh eval-categories <lang>`.
3. (Optional) add/adjust the profile check that should catch it — net-new checks stay at
   **Medium** confidence (High is tool-confirmed only).
4. Open a PR. `tests/eval/` is CODEOWNERS-protected; a maintainer reviews the ground
   truth. The completeness critic may DRAFT fixtures into `tests/eval/_proposals/`, but
   a human always authors the `.expected` label and merges via PR.
```

- [ ] **Step 3: `README.md`** — one line under the eval/self-improvement mention:
  the loop-closing harness is maintainer-run (manual), and a green eval means
  "didn't get worse," not "better at the real job."

- [ ] **Step 4: Commit**

```bash
git add tests/eval/README.md CONTRIBUTING.md README.md
git commit -m "docs(eval): loop-closing harness workflow, caveat, subcommands (#15)"
```

### Task 8.3: Reconcile bats corpus/profile-list assertions

**Files:**
- Modify: `tests/detect.bats`

- [ ] **Step 1: Find list-based assertions that the new files could break**

Run: `bats tests/detect.bats` and inspect any failure that enumerates `tests/eval/*`
contents, profile counts, or "every profile has X" invariants. The new
`baseline.*.txt`, `held-out/`, `_proposals/`, and `.last-run.*` (gitignored) must not
trip directory-walk assertions.

- [ ] **Step 2: Update the assertions** to filter to fixtures (exclude `baseline.*`,
  `_proposals`, `README.md`) wherever a test globs a language dir. Example pattern:

```bash
# only count fixture source files, not baselines/readmes
ls tests/eval/java/seen/*.java | grep -vc expected
```

- [ ] **Step 3: Run the whole suite + syntax check**

Run: `sh -n skills/scan/lib/detect.sh && bats tests/detect.bats`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add tests/detect.bats
git commit -m "test(eval): reconcile corpus-list assertions with harness files (#15)"
```

---

## Final verification (before PR)

- [ ] `sh -n skills/scan/lib/detect.sh tests/eval/runners/*.sh tests/fixtures/eval-runner-stub` — all clean.
- [ ] `bats tests/detect.bats` — all green (existing + new).
- [ ] `skills/scan/lib/detect.sh eval-categories java` prints `cat#1..5` (no corpus-specific labels for java unless added).
- [ ] `DEFECT_SCAN_EVAL_RUNNER=tests/fixtures/eval-runner-stub DEFECT_SCAN_STUB_MODE=perfect skills/scan/lib/detect.sh eval-run java --runs 3` → PASS report, artifact written, gitignored.
- [ ] Confirm `git status` shows no `.last-run.*` tracked.
- [ ] Ship via `/review-merge-pipeline` (targets `dev`). Issue #15 closes on the next `/deploy` to `main`.

---

## Spec coverage map

| Spec § | Plan task |
|--------|-----------|
| §1 split-level scoring | Phase 3 (Task 3.1) |
| §2.1 eval-run + clean-by-empty-sidecar | Phase 3, Phase 4 |
| §2.2 runner contract (lang, temp cwd, source-only) | Phase 6 (Task 6.2) |
| §2.3 eval-mode addendum | Phase 6 (Task 6.1) |
| §2.4 per-split baselines | Phase 4 |
| §2.5 .last-run artifact (flat text) | Phase 3, Phase 5 |
| §2.6 eval-categories registry | Phase 1 |
| §3 strict sentinel (missing≠empty) | Phase 2 |
| §4 gate policy + overfit | Phase 4, Phase 7 |
| §5 completeness critic (gaps + _proposals) | Phase 0, Phase 5 |
| §6 CI + security (read-only, approval-gated) | Phase 6, Phase 8 |
| §7 stub-runner offline tests | Phases 0–7 |
| §8 java held-out pilot, held-out incremental | Phase 7 |
| §9 files touched | all phases |

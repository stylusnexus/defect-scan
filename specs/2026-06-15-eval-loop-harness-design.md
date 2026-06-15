# Eval Loop-Closing Harness & Completeness Critic — Design Spec

**Date:** 2026-06-15
**Issue:** stylusnexus/defect-scan#15 (Phase 2)
**Status:** Approved (brainstorming) → ready for implementation plan

---

## Plain-English summary

Phase 1 of #15 gave defect-scan a *ruler* — `detect.sh eval`, a model-free grader
that scores a list of findings against a labeled corpus (precision/recall) — plus
the corpus itself for 12 languages and a guarantee (CODEOWNERS + branch protection)
that nobody can quietly weaken the ruler in a PR.

The gap: **nothing actually runs the scanner against the corpus.** Today's tests
hand the grader a hand-written list of findings to prove the grader works. So we
measure the ruler, not the thing being measured. This phase closes that loop. We
add a *maintainer-run* harness that takes a real defect scan, runs it over each
corpus fixture (several times, because the reasoning pass is non-deterministic),
collects what it found, scores it, and compares against a committed baseline so a
profile change that makes the scan noisier gets caught.

Two hard rules carry over from Phase 1 and shape every decision here:
1. **The engine (`detect.sh`) never contains a model.** The model call lives only in
   small, swappable *runner* scripts. The orchestrator that walks the corpus and the
   grader that scores it stay deterministic and offline-testable.
2. **The model never authors its own ground truth.** A "completeness critic" may
   point at coverage gaps and even draft candidate fixture *code*, but a human writes
   the correctness labels (`.expected`) and merges them through a reviewed PR. That
   line is what keeps this from becoming the runtime-learning-store / prompt-injection
   risk (#15's rejected "Mechanism 2").

Honest caveat (unchanged from #15): an offline corpus measures the reasoning pass,
not real-repo value. A green eval means "didn't get worse," not "better at the real
job." Real signal still comes from the curated escaped-bug → fixture loop.

---

## Goals & non-goals

**Goals**
- Close the loop: actually run a scan over the corpus and score it, end to end.
- Keep `detect.sh` **model-free**; isolate every model call in swappable runners.
- Handle non-determinism: aggregate **mean±stddev over N runs**, default N=5.
- **Precision-first gating** against a committed, CODEOWNERS-gated baseline.
- A **completeness critic** that surfaces coverage gaps and optionally drafts
  candidate fixtures into a *staging* area the grader ignores — humans label + PR.
- The harness logic itself is **testable offline** (a stub runner; no model in CI).
- Fold in the corpus debts: fill `java/seen`, add `held-out/` splits, document the
  escaped-bug → fixture workflow.

**Non-goals (YAGNI for this phase)**
- Running the harness on every PR. It is manual-dispatch / local only.
- A model in the grader or orchestrator (ever — that is the whole point).
- Auto-merging model-proposed fixtures or `.expected` labels.
- A first-class `--format eval` output mode in the product (we use a sentinel block
  instead — see §3; a real format mode is a possible future, not now).
- Cross-language aggregate dashboards / historical trend storage.

---

## 1. Architecture & the model-free boundary

```
detect.sh eval-run <lang> [--runs N] [--split seen|held-out|all]   ← model-FREE orchestrator
  └─ for each fixture in tests/eval/<lang>/<split>/ × N runs:
       $DEFECT_SCAN_EVAL_RUNNER <fixture-path>                       ← swappable model call
         → stdout containing a <<<EVAL … EVAL>>> block
       └─ orchestrator extracts the block → per-run findings file
       └─ detect.sh eval <corpus> <findings>   (existing Phase-1 scorer)
  └─ aggregate precision/recall mean±stddev across runs; clean-fixture FP rate (X/N)
  └─ diff against tests/eval/<lang>/baseline.txt → PASS / FLAG / FAIL
```

The split that matters (carried from Phase 1): the **orchestrator and grader are
deterministic shell with no model**; the **runner is the only model-bearing part**
and lives *outside* `lib/`. This keeps the un-gameable, testable core intact and
makes the harness itself unit-testable with a stub runner.

Scanning is **per-fixture, not per-corpus-dir**: each fixture is a self-contained
mini-repo for one defect class, so scanning them individually mirrors a real targeted
scan and avoids cross-contamination between fixtures in one model context. Cost is
bounded (one language × ~6 fixtures × N runs); the harness scopes to one language per
invocation.

## 2. Components

### 2.1 `eval-run` orchestrator (new `detect.sh` subcommand, model-free)
- Resolves `tests/eval/<lang>/<split>/`; errors clearly if the lang/split is absent.
- For each fixture × N runs: invokes `$DEFECT_SCAN_EVAL_RUNNER <fixture-path>`,
  captures stdout, extracts the sentinel block (§3) into a findings file, runs
  `cmd_eval` on it, and records `precision recall tp fp fn`.
- Aggregates across runs into mean±stddev per metric; separately tracks the
  **clean-fixture FP rate** (in how many of the N runs did any `clean_*` fixture
  produce a finding).
- Loads `tests/eval/<lang>/baseline.txt` and applies the gate policy (§4), printing
  a human report and exiting non-zero on FAIL (so a maintainer / `workflow_dispatch`
  job surfaces red).
- If `DEFECT_SCAN_EVAL_RUNNER` is unset → exit 3 with an install/usage hint (same
  graceful-degradation convention as missing analyzers). It must never silently pass.

### 2.2 Runner scripts (`tests/eval/runners/{claude,codex}.sh`)
- Selected via `DEFECT_SCAN_EVAL_RUNNER` (an absolute path or one of these).
- Contract: take one argument (a target path), run the defect scan over it **headless**
  with eval-mode on, print raw model output (which must contain the sentinel block) to
  stdout. Exit non-zero on tool failure.
  - `claude.sh` → `claude -p '/defect-scan:scan <path>'` (+ eval-mode instruction).
  - `codex.sh`  → `codex exec --sandbox read-only --skip-git-repo-check` over the
    Codex driver (mirrors the existing `cmd_codex_verify` invocation).
- They live **outside `lib/`** by design: they hold the model call, so they are not
  part of the deterministic engine. They are maintainer-authored and in-repo
  (origin-trusted), so they are not subject to the scanned-repo origin gate.

### 2.3 Eval-mode prompt addendum (shared knowledge)
- A short instruction block, sourced from one shared snippet so both drivers stay in
  sync (the repo's "two harnesses, one brain" rule): *when eval mode is signaled, in
  addition to the normal report, emit findings between `<<<EVAL` and `EVAL>>>`, one
  per line as `<path>:<line>:<category>`, using the baseline category vocabulary.*
- The default human report is **unchanged**; eval mode only *adds* the block.

### 2.4 Baseline files (`tests/eval/<lang>/baseline.txt`)
- Keys: `precision_floor`, `recall_floor` (absolute floors); `precision_baseline`,
  `recall_baseline` (the recorded accepted means, to catch slow erosion that stays
  above the floor); `noise_band` (stddev/erosion tolerance).
- Plain `key=value` lines (parsed with the existing `fm_*`/awk style, no new dep).
- Under `/tests/eval/` → already CODEOWNERS-protected; the gate can only loosen via a
  reviewed PR.

## 3. Findings capture — the sentinel block

The product's normal output is a human report (`report-format.md`); the grader needs
clean `<path>:<line>:<category>` lines. Eval mode appends a delimited block:

```
…normal human report…

<<<EVAL
bug_bare_except.py:12:cat#4
bug_resource_leak.py:8:cat#2
EVAL>>>
```

The orchestrator extracts it deterministically (`sed -n '/<<<EVAL/,/EVAL>>>/p'`,
strip the sentinels). Rationale over the alternatives: it leaves the product surface
untouched, gives the grader an *exact* format instead of parsing prose, and needs no
new synchronized output mode across both drivers. If the block is missing or empty on
a buggy fixture, that run scores as all-misses (recall 0) for that fixture — a missing
block is a real signal (the scan produced nothing parseable), not an error to swallow.

## 4. Scoring & gate policy (precision-first)

Applied to the aggregated metrics:
- **Precision — hard gate.** Mean precision over N runs must be ≥ `precision_floor`
  **and** not below `(precision_baseline − noise_band)` (the erosion check). Violation
  → **FAIL**.
- **Clean-fixture FPs — tripwire, reported as a rate** (`FP on clean: 1/5 runs`).
  Any nonzero rate → at least **FLAG**, surfaced prominently; a clean-fixture FP is the
  canonical precision-first failure, so a flaky one must not hide inside an averaged
  pass.
- **Recall — soft.** Mean recall below `recall_floor` → **WARN**, not FAIL (a miss is
  cheaper than a false alarm, per #15's asymmetry).
- **Baseline only moves via a CODEOWNERS PR.** The harness never rewrites
  `baseline.txt`; tightening or loosening a floor is a reviewed human change, so the
  system cannot ratchet its own grader.
- **Seen vs held-out.** When `--split all`, score the two separately and report both;
  a seen-high / held-out-low gap beyond `noise_band` is the **overfitting** signal
  (reported as a FLAG).

## 5. Completeness critic (`eval-gaps`)

Two parts, with the safety line between them:

**(a) Gap report — model-free, safe.** `detect.sh eval-gaps <lang>` reports coverage
gaps from deterministic inputs only (it is a `detect.sh` subcommand, so it contains no
model): per-category recall from the most recent `eval-run` record, and corpus
categories compared against the categories named in the profile's `## Reasoning
checklist`. Output is advisory text ("python cat#2 recall weak"; "rust has no
`clean_*` near-miss for unsafe"). No writes.

**(b) Staged drafts — optional, human-labeled.** Separate from the `eval-gaps`
subcommand, a maintainer may invoke a drafting step (model-driven, via a runner — not
part of `detect.sh`) that writes candidate fixture **source** into
`tests/eval/_proposals/` — a staging directory the grader and `eval-run`
**explicitly ignore** (they only read `seen/` and `held-out/`). The model produces
*code*, never a `.expected` label. A human:
1. authors the `.expected` ground truth,
2. moves the fixture into `seen/` (or `held-out/`),
3. opens a PR (CODEOWNERS review required).

Net-new, self-proposed checks cap at **Medium** confidence (High stays
tool-confirmed-only). This is the concrete boundary that keeps the critic on the
human-gated write path and out of "Mechanism 2": scanned/model-authored content never
becomes graded ground truth without a human author and a reviewed merge.

## 6. CI posture

- **PR CI — unchanged.** The Phase-1 model-free scorer bats tests stay (they test the
  ruler: fast, free, deterministic). Plus the new harness-logic tests (§7), which are
  also model-free via the stub runner.
- **Loop-closing harness — manual only.** A `workflow_dispatch` job (model credentials
  as repo secrets) or local invocation. Never per-PR: model cost, non-determinism, and
  no model in standard CI. The job prints the report and goes red on FAIL.
- The README/CONTRIBUTING keep #15's honest caveat: green eval = "didn't get worse."

## 7. Testing

The harness must be trustworthy the same way the grader is — **provable without a
model**:
- **Stub runner** (`tests/fixtures/eval-runner-stub`): emits canned `<<<EVAL…EVAL>>>`
  output (parameterized so a test can simulate a clean-fixture FP, a miss, run-to-run
  variance). Point `DEFECT_SCAN_EVAL_RUNNER` at it. bats then proves, offline:
  - aggregation math + mean±stddev over N runs,
  - baseline PASS / FLAG / FAIL transitions,
  - clean-fixture FP-rate flagging (X/N),
  - seen-vs-held-out overfitting FLAG,
  - missing/empty sentinel block ⇒ recall-0 for that fixture (not a crash),
  - unset `DEFECT_SCAN_EVAL_RUNNER` ⇒ exit 3 (never silent pass).
- **`eval-gaps`** tested against the fixture corpus (deterministic gap report).
- Cross-platform (BSD/GNU) per repo convention; POSIX `sh`, no bashisms.

## 8. Corpus debts folded in

- **Fill `java/seen`**: 3 `bug_*` + 3 `clean_*` (incl. a near-miss clean) + `.expected`
  sidecars, matching the other languages' shape.
- **Add `held-out/` splits**: a small held-out set per language for the anti-overfitting
  gate (§4). Start with the higher-traffic languages; the harness tolerates a missing
  held-out split (scores `seen` only) so this can land incrementally.
- **Document the workflow** in `CONTRIBUTING.md`: confirmed-FP or escaped-prod-bug →
  add fixture + `.expected` + (optional) check → PR. This is the real self-improvement
  loop the offline eval supports.

## 9. Files touched (anticipated)

- `skills/scan/lib/detect.sh` — new `cmd_eval_run`, `cmd_eval_gaps`; dispatch entries.
- `tests/eval/runners/claude.sh`, `tests/eval/runners/codex.sh` — new.
- `tests/eval/<lang>/baseline.txt` — new per language.
- `tests/eval/java/seen/*` — new fixtures + `.expected`.
- `tests/eval/<lang>/held-out/*` — new (incremental).
- `tests/eval/_proposals/.gitkeep` — staging dir the grader ignores.
- shared eval-mode prompt snippet + references in `SKILL.md` and the Codex driver.
- `tests/fixtures/eval-runner-stub` — new.
- `tests/detect.bats` — new harness tests; update profile/corpus-list assertions.
- `CONTRIBUTING.md`, `README.md` — workflow + caveat.
- `tests/eval/README.md` — document `eval-run`, runners, baselines, `_proposals/`.

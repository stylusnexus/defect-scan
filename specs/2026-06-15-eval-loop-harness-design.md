# Eval Loop-Closing Harness & Completeness Critic — Design Spec

**Date:** 2026-06-15
**Issue:** stylusnexus/defect-scan#15 (Phase 2)
**Status:** Approved (brainstorming) → revised after Codex spec-review → ready for plan

---

## Plain-English summary

Phase 1 of #15 gave defect-scan a *ruler* — `detect.sh eval`, a model-free grader
that scores a list of findings against a labeled corpus (precision/recall) — plus
the corpus itself for 13 languages and CODEOWNERS coverage so the ruler can't be
quietly weakened in a PR.

The gap: **nothing actually runs the scanner against the corpus.** Today's tests
hand the grader a hand-written list of findings to prove the grader works. So we
measure the ruler, not the thing being measured. This phase closes that loop with a
*maintainer-run* harness that takes a real scan, runs it over each corpus fixture
(several times, because the reasoning pass is non-deterministic), collects what it
found, scores it, and compares against a committed baseline so a profile change that
makes the scan noisier gets caught.

Two hard rules carry over from Phase 1 and shape every decision:
1. **The engine (`detect.sh`) never contains a model.** The model call lives only in
   small, swappable *runner* scripts. The orchestrator that walks the corpus and the
   grader that scores it stay deterministic and offline-testable.
2. **The model never authors its own ground truth.** A "completeness critic" may
   point at coverage gaps and even draft candidate fixture *code*, but a human writes
   the correctness labels (`.expected`) and merges them through a reviewed PR. That
   line keeps this out of the runtime-learning-store / prompt-injection risk (#15's
   rejected "Mechanism 2").

Honest caveat (unchanged): an offline corpus measures the reasoning pass, not
real-repo value. A green eval means "didn't get worse," not "better at the real job."

---

## Goals & non-goals

**Goals**
- Close the loop: run a scan over the corpus and score it, end to end.
- Keep `detect.sh` **model-free**; isolate every model call in swappable runners.
- Handle non-determinism: aggregate **mean±stddev over N runs**, default N=5.
- **Precision-first gating** against committed, CODEOWNERS-gated, per-split baselines.
- A **completeness critic** that surfaces coverage gaps and optionally drafts
  candidate fixtures into a *staging* area the grader ignores — humans label + PR.
- The harness logic is **provable offline** (a stub runner; no model in CI).
- Fold in the real corpus debts: add `held-out/` splits, document the escaped-bug →
  fixture workflow. (Java is **already** populated — see §8.)

**Non-goals (YAGNI for this phase)**
- Running the harness on every PR. Manual-dispatch / local only.
- A model in the grader or orchestrator (ever — that is the point).
- Auto-merging model-proposed fixtures or `.expected` labels.
- Changing `cmd_eval`'s scoring contract (it is Phase-1, CODEOWNERS-protected; we
  build *around* it, scoring a whole split per run — see §1).
- A first-class `--format eval` product output mode (we use a sentinel block, §3).
- Cross-language dashboards / historical trend storage.

---

## 1. Architecture, scoring unit & the model-free boundary

```
detect.sh eval-run <lang> [--runs N] [--split seen|held-out|all] [--update-baseline]
  │   (model-FREE orchestrator)
  └─ for run r in 1..N:
       findings_r = empty
       for each SOURCE fixture in tests/eval/<lang>/<split>/:      # NOT the .expected sidecar
            out = $DEFECT_SCAN_EVAL_RUNNER <fixture-path> <lang>   # swappable model call
            block = extract exactly one <<<EVAL…EVAL>>> (validated, §3)
            append block lines (path-prefixed) to findings_r
       metrics_r = detect.sh eval  tests/eval/<lang>/<split>/  findings_r   # score the SPLIT once
  └─ aggregate metrics_1..N → mean±stddev; clean-fixture FP rate (X/N, §4)
  └─ write .last-run artifact (§2.5); gate vs baseline.<split>.txt (§4) → PASS/WARN/FLAG/FAIL
```

**The scoring unit is one whole split per run, not one fixture** (Codex F1). `cmd_eval`
keys expected/actual by fixture **basename** across an entire corpus dir
(`detect.sh:300-348`); scoring a single fixture against the split would mark every
other fixture's expected defect as a false negative. So the runner is invoked
per-fixture (isolation — each fixture scanned in its own context), but their findings
are **accumulated into one findings file per run** and scored once against the split.

The Phase-1 split holds: the **orchestrator and grader are deterministic shell, no
model**; the **runner is the only model-bearing part** and lives *outside* `lib/`.

## 2. Components

### 2.1 `eval-run` orchestrator (new `detect.sh` subcommand, model-free)
- Resolves `tests/eval/<lang>/<split>/`; errors clearly if lang/split absent.
- Runs the per-run loop in §1; accumulates findings; scores the split per run.
- Aggregates across runs: **mean** = arithmetic mean (2-dp), **stddev** = population
  stddev. Separately computes the **clean-fixture FP rate**: in how many of the N runs
  did any **clean fixture** (defined by an **empty `.expected` sidecar** — Codex F6,
  matching the scorer at `detect.sh:305-339`, *not* a filename convention) produce ≥1
  finding.
- Loads `baseline.<split>.txt` (§2.4), applies the gate (§4), prints a report, writes
  the `.last-run` artifact (§2.5). **Exit status:** `0` on PASS/WARN/FLAG (printed),
  **nonzero on FAIL** so a `workflow_dispatch` job goes red.
- `--update-baseline`: write the current aggregated means into `baseline.<split>.txt`
  for the maintainer to commit (CODEOWNERS PR). The harness never auto-commits.
- If `DEFECT_SCAN_EVAL_RUNNER` is unset → **exit 3** with a usage hint (graceful-
  degradation convention). Never a silent pass.

### 2.2 Runner scripts (`tests/eval/runners/{claude,codex}.sh`)
- Selected via `DEFECT_SCAN_EVAL_RUNNER` (absolute path or one of these).
- **Contract — explicit (Codex F2):** `runner <fixture-path> <lang>`. The runner:
  1. Stages **only the source file** into a fresh temp working dir — never the
     `.expected` sidecar (feeding the answer to the scanner would invalidate the eval).
  2. Runs the scan **headless**, **`--lang <lang>`** (force the profile; no detection
     guesswork on a one-file target), eval-mode on, with the temp dir as cwd so
     analyzer resolution (`detect.sh tool`) and the Codex driver's
     "cwd = target repo" assumption (`codex/defect-scan.md:16-24`) both hold.
  3. Prints raw model output (must contain the sentinel block) to stdout; exits
     nonzero on tool failure.
  - `codex.sh` → `codex exec --sandbox read-only --skip-git-repo-check` (mirrors the
    proven `cmd_codex_verify`, `detect.sh:358-370`).
  - `claude.sh` → `claude -p '/defect-scan:scan <path> --lang <lang>'` **with a
    read-only tool policy** (no Edit/Write/Bash-write; see §6 security) — parity with
    Codex's read-only sandbox.
- They live **outside `lib/`** by design (they hold the model call). They are trusted
  **only when executed from a trusted ref by a maintainer** (§6) — *not* inherently,
  since a PR can modify them.

### 2.3 Eval-mode prompt addendum (shared knowledge)
- One shared snippet (sourced by both drivers — "two harnesses, one brain"): *when
  eval mode is signaled, in addition to the normal report, emit exactly one block
  between `<<<EVAL` and `EVAL>>>`, one finding per line as `<path>:<line>:<category>`,
  using only categories from the language's registry (§2.6).*
- The default human report is **unchanged**; eval mode only *adds* the block.

### 2.4 Per-split baseline files (`tests/eval/<lang>/baseline.<split>.txt`)
- One file per split (`baseline.seen.txt`, `baseline.held-out.txt`) — Codex F5.
- Keys (plain `key=value`, awk-parsed, no new dep):
  `precision_floor`, `recall_floor` (absolute floors);
  `precision_baseline`, `recall_baseline` (recorded accepted means, for erosion);
  `noise_band` (erosion tolerance on the recorded means);
  `overfit_band` (max acceptable seen-vs-held-out mean-precision gap).
- Under `/tests/eval/` → CODEOWNERS-protected; floors/baselines move only via PR.

### 2.5 Run artifact (`tests/eval/<lang>/.last-run.<split>.json`)
- Deterministic record `eval-run` writes (Codex F4): per-run metrics, aggregated
  mean±stddev, clean-FP rate, and **per-category** tp/fp/fn (derived by the model-free
  scorer over the category registry). **Gitignored** (a transient local artifact, not
  ground truth). It is the sole input `eval-gaps` reads — no prose parsing.

### 2.6 Category registry (`detect.sh eval-categories <lang>`, model-free)
- Resolves the authoritative valid-label set for a language (Codex F3): the baseline
  categories `cat#1…cat#5` (`baseline-categories.md`) **∪** the language-specific
  labels actually present in that language's corpus `.expected` files (e.g. `panic`
  for rust, `coerce` for yaml, `quoting` for shell). Pure set-union over existing
  artifacts — no new declarations, deterministic.
- Two consumers: eval-mode tells the model the valid set (so emitted labels match what
  the scorer compares against, exactly); `eval-gaps` uses it as the denominator for
  per-category coverage.

## 3. Findings capture — the sentinel block (Codex F8)

Eval mode appends one delimited block to the normal report:

```
…normal human report…

<<<EVAL
BugEmptyCatch.java:4:cat#2
BugSqlInjection.java:5:cat#3
EVAL>>>
```

Extraction is strict and deterministic:
- **Exactly one** block. Zero, two, or nested blocks → **protocol error** for that
  fixture's run.
- Every line must match `^[^:]+:[0-9]+:[^:]+$` and carry a category in the registry
  (§2.6); a malformed line → protocol error.
- **Missing block ≠ empty block.** A *missing* block is a protocol error (the scan
  produced nothing parseable). An *empty but present* block is a legitimate "no
  findings" — correct for a clean fixture. This distinction is load-bearing: without
  it, a missing block on a clean fixture would score a perfect 1.00 (empty expected ∩
  empty actual), hiding a broken runner (Codex's exact catch).
- A fixture whose run hits a protocol error is marked **inconclusive**, excluded from
  that run's score, and reported. A run with any inconclusive fixture is flagged
  partial — never silently counted as a clean pass.

## 4. Scoring & gate policy (precision-first)

Per split, on the aggregated metrics:
- **Precision — hard gate.** `mean_precision ≥ precision_floor` **and**
  `mean_precision ≥ precision_baseline − noise_band` (erosion check). Else **FAIL**.
- **Clean-fixture FPs — tripwire as a rate** (`FP on clean: 1/5 runs`). Any nonzero
  rate → at least **FLAG**, surfaced prominently; a flaky clean-fixture FP must not
  hide inside an averaged pass.
- **Recall — soft.** `mean_recall < recall_floor` → **WARN**, not FAIL (a miss is
  cheaper than a false alarm).
- **Overfitting (only under `--split all`).** Score `seen` and `held-out` separately
  against their own baselines; if `seen_mean_precision − heldout_mean_precision >
  overfit_band` → **FLAG**.
- **Severity → exit:** FAIL → nonzero exit; WARN/FLAG/PASS → exit 0 but printed
  distinctly. (FLAG = "look now," not "block.")
- **Baseline only moves via a CODEOWNERS PR** (`--update-baseline` writes; a human
  commits). The system cannot ratchet its own grader.

## 5. Completeness critic (`eval-gaps`)

**(a) Gap report — model-free, safe.** `detect.sh eval-gaps <lang>` reads only
deterministic inputs (it is a `detect.sh` subcommand → contains no model): the
`.last-run` artifact (§2.5) for per-category recall, and the category registry (§2.6)
for the expected category set. Output is advisory text ("python cat#2 recall weak";
"rust corpus has no `clean_*` near-miss for `panic`"). No writes. (It does **not**
parse profile-checklist prose — Codex F4.)

**(b) Staged drafts — optional, human-labeled.** Separate from `eval-gaps` (model-
driven, via a runner — not part of `detect.sh`): a maintainer may invoke a drafting
step that writes candidate fixture **source** into `tests/eval/_proposals/` — a
staging dir `eval-run`/`cmd_eval` **explicitly ignore** (they read only the configured
splits). The model produces *code*, never a `.expected` label. A human then (1)
authors the `.expected` ground truth, (2) moves the fixture into `seen/` or
`held-out/`, (3) opens a PR (CODEOWNERS review). Net-new self-proposed checks cap at
**Medium** (High stays tool-confirmed-only). This boundary keeps model/scanned content
out of graded ground truth without a human author + reviewed merge.

## 6. CI & security posture

- **PR CI — unchanged.** Phase-1 model-free scorer tests stay (fast/free/
  deterministic), plus the new harness-logic tests (§7) — also model-free via the stub
  runner.
- **Loop-closing harness — manual only.** A `workflow_dispatch` job (model credentials
  as repo secrets) or local. Never per-PR: model cost, non-determinism, no model in
  standard CI.
- **Runner / workflow security (Codex F7):**
  - Both runners enforce **read-only model permissions** (Codex `--sandbox read-only`;
    Claude `-p` with a no-write tool policy). A runner can never mutate the repo.
  - The `workflow_dispatch` job checks out a **trusted ref** (a protected branch, not
    an arbitrary PR head), runs under a **GitHub Environment with required approval**
    for secret access, with a **minimal `GITHUB_TOKEN`** (`contents: read`), model API
    keys scoped to that environment (never exposed to fork PRs), and per-run timeouts.
  - "In-repo runners are origin-trusted" holds **only from a trusted ref**; the harness
    must never run with secrets against untrusted PR-modified runner scripts.
- **CODEOWNERS guarantee is conditional (Codex F9).** CODEOWNERS coverage exists
  (`.github/CODEOWNERS`), but the "can't weaken the grader" guarantee **requires branch
  protection with required code-owner review enabled** — a documented **rollout
  prerequisite to verify**, not an automatic property of the file.

## 7. Testing — the harness must be provable without a model

- **Stub runner** (`tests/fixtures/eval-runner-stub`): emits canned `<<<EVAL…EVAL>>>`
  output, parameterized to simulate a clean-fixture FP, a miss, run-to-run variance,
  and malformed/missing/duplicate/empty blocks. `DEFECT_SCAN_EVAL_RUNNER` points at it.
  bats then proves, offline:
  - per-run-then-aggregate scoring (§1), mean±stddev math,
  - baseline PASS / WARN / FLAG / FAIL transitions + exit codes (§4),
  - clean-fixture FP-rate flagging by **empty sidecar** (§2.1),
  - seen-vs-held-out overfit FLAG (§4),
  - sentinel strictness (§3): exactly-one-block, line validation, **missing-block-on-
    clean = protocol error (not a 1.00 pass)**, empty-but-present = clean ok,
  - unset `DEFECT_SCAN_EVAL_RUNNER` → exit 3.
- **`eval-categories`** tested: baseline ∪ corpus labels per language (incl. `panic`/
  `coerce`/`quoting`).
- **`eval-gaps`** tested against a fixture `.last-run` artifact (deterministic report).
- Cross-platform (BSD/GNU), POSIX `sh`, no bashisms (repo convention).

## 8. Corpus debts folded in

- **Java is already populated** (Codex F6): `tests/eval/java/seen/` has `Bug*.java` +
  `Clean*.java` with sidecars and a passing test (`detect.bats:745-758`). **No work.**
  (The earlier "fill java" item was a false reading from a `bug_*`/`clean_*` glob that
  missed Java's `Bug*`/`Clean*` naming.)
- **Add `held-out/` splits**: a small held-out set per language for the anti-overfitting
  gate (§4). Land incrementally — `eval-run` tolerates a missing held-out split (scores
  `seen` only). Start with higher-traffic languages.
- **Document the workflow** in `CONTRIBUTING.md`: confirmed-FP or escaped-prod-bug →
  add fixture + `.expected` + (optional) check → PR. The real self-improvement loop.

## 9. Files touched (anticipated)

- `skills/scan/lib/detect.sh` — new `cmd_eval_run`, `cmd_eval_gaps`,
  `cmd_eval_categories`; dispatch entries.
- `tests/eval/runners/claude.sh`, `tests/eval/runners/codex.sh` — new.
- `tests/eval/<lang>/baseline.seen.txt` (+ `baseline.held-out.txt` where held-out
  exists) — new per language.
- `tests/eval/<lang>/held-out/*` — new (incremental).
- `tests/eval/_proposals/.gitkeep` — staging dir the grader ignores.
- `.gitignore` — ignore `tests/eval/*/.last-run.*.json`.
- shared eval-mode prompt snippet + references in `SKILL.md` and the Codex driver.
- `tests/fixtures/eval-runner-stub` — new.
- `tests/detect.bats` — new harness tests; update profile/corpus-list assertions.
- `CONTRIBUTING.md`, `README.md`, `tests/eval/README.md` — workflow, caveat, and
  `eval-run`/runners/baselines/registry/`_proposals/` docs.
- `.github/workflows/` — manual `eval-run` dispatch job (trusted-ref + approval-gated).

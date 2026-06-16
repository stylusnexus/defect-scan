# defect-scan eval corpus

A labeled fixture corpus for **measuring** whether a profile/pattern change makes the
scanner better — or just louder. This is the spine of safe self-improvement (issue
#15): the grader (`detect.sh eval`) is model-free and lives in git, separate from the
markdown the model reads, so improvement is measurable and can't silently regress.

## How the full eval works

The eval has **four parts** — three model-free `detect.sh` subcommands plus a swappable
runner that is the *only* part that calls a model:

| Part | What it is | Model? |
|------|-----------|--------|
| **Validator** — `detect.sh eval` | Scores a findings list against the corpus → precision/recall/tp/fp/fn | **No** (deterministic) |
| **Harness** — `detect.sh eval-run` | Drives a real scan over the corpus, scores it, aggregates, gates vs baseline | **No** (orchestrator; calls the runner) |
| **Completeness critic** — `detect.sh eval-gaps` | Per-category coverage report from the last run | **No** |
| **Runner** — `tests/eval/runners/*.sh` | Runs the actual scan on one fixture, emits a `<<<EVAL>>>` block | **Yes** — and it lives *outside* the engine |

Data flow for one `eval-run <lang>`:

```
  corpus fixture ─▶ runner (claude.sh / codex.sh)         [the only model call]
                      │  scans it read-only; is told the
                      │  valid label set (eval-categories)
                      ▼
                 <<<EVAL                                   stdout
                 file:line:category                        (sentinel block)
                 EVAL>>>
                      │  extract_eval_block (strict: exactly one block; missing ≠ empty)
                      ▼
            accumulate all fixtures ─▶ detect.sh eval  ──▶ precision / recall  (±2 line
            into one findings file       (the Validator)     tolerance, 1:1 match)
                      │
                      ▼
          aggregate mean±stddev over N runs ─▶ gate vs baseline.<split>.txt
                      │                          (FAIL / WARN / FLAG / PASS)
                      ▼
            write .last-run.<split>.txt  ──▶ detect.sh eval-gaps  (coverage critic)
```

**Why it's safe (the load-bearing properties):**
- **The engine never calls a model.** `detect.sh` (validator + harness + critic) is
  deterministic POSIX `sh`; the model lives only in the runner, outside `lib/`. So the
  thing that *judges* improvement is separate from the thing being improved — it can't
  optimize its own ruler.
- **Precision-first.** A false positive costs more than a miss (findings can auto-file
  issues / auto-fix). Clean fixtures (empty `.expected`) are the false-positive
  tripwire — any finding on one is an FP; the ±2 tolerance never applies to them. The
  ±2 line tolerance + 1:1 matching absorbs real models' line-attribution wobble without
  rewarding a spray of guesses (a spray near one label = 1 TP + the rest FP).
- **Human-gated write path.** Ground truth (`.expected`) and the bar (`baseline.*.txt`)
  only change through a **CODEOWNERS-reviewed PR**. The completeness critic may *draft*
  fixtures into `_proposals/`, but a human authors the label. There is no runtime
  learning store (that would be the prompt-injection surface #15 rejects).
- **Overfitting guard.** `--split all` scores `seen` vs `held-out` separately and FLAGs
  a gap beyond `overfit_band` — a profile tuned to memorized fixtures shows up here.
- **Honest about itself.** A green eval means "didn't get worse" against this corpus,
  not "better at the real job." It's a regression floor, not a proof of quality.

The rest of this doc is the operational reference for each part.

## Layout

```
tests/eval/<language>/
  seen/        # fixtures you author checks against
  held-out/    # (Phase 2) fixtures never consulted while authoring — overfitting guard
```

Each fixture is a small source file plus a sibling `<fixture>.expected` sidecar:

- **Buggy fixture** → sidecar lists the expected findings, one per line as
  `<line>:<category>` (e.g. `5:cat#2`). Categories are from `baseline-categories.md`.
- **Clean fixture** → **empty** sidecar. The fixture MUST produce zero findings.
  Clean fixtures are the false-positive tripwire — most regressions make the scanner
  noisier, not blinder. Include **near-miss** clean fixtures (code that looks like the
  bug but has the guard), e.g. `clean_near_miss_except.py`.

## Scoring

```sh
# findings-file: lines of "<path>:<line>:<category>" from a scan of the corpus.
detect.sh eval tests/eval/python/seen <findings-file>
# → precision=… recall=… tp=… fp=… fn=…
```

Matching is by fixture **basename** + **category**, with a **±2 line tolerance** and
strict **1:1** assignment: a finding is a true positive when it hits the same fixture
and category within 2 lines of the labelled line. Real models attribute a multi-line
defect (an empty `try/catch`, an unclosed resource) a line or two off from the label;
exact-line matching would score a correct find as both a false positive and a false
negative. The 1:1 rule keeps it honest — a *spray* of findings near one label scores
**one** TP and the rest as FPs, so noise is still punished. The `±2` is a committed
constant in `cmd_eval` (no runtime knob — a tunable ruler is a gameable ruler); widen
it only via a CODEOWNERS-reviewed change. Clean fixtures have no labelled lines, so
the tolerance never applies — any finding on a clean fixture is still a false positive.
Score one dir at a time. The scorer is deterministic and model-free — that's
deliberate: the thing that judges improvement must not be the thing being improved.

## How to use it (precision-first)

- A finding on a `clean_*` fixture is a **false positive** → precision drops. Treat a
  precision regression as a failing change, not a shipped improvement.
- The reasoning pass is non-deterministic — average **≥3 runs** (report mean ± stddev)
  before trusting a delta. A check that swings precision run-to-run is noise.
- New self-proposed checks enter at **Medium** at most; **High** stays reserved for
  tool-confirmed findings. The eval never edits tier rules.

## The loop-closing harness (maintainer-run)

The `eval` grader above scores *one* findings file you produced by hand. The harness
automates the whole loop — run the scan over the corpus, score it, repeat for variance,
and gate the result against a committed baseline. It is **maintainer-run** (a manual
`workflow_dispatch` or local invocation), never on PR, because each run executes a real
model over the corpus.

**Every run involves two separate choices — don't conflate them:**

| | What it is | How you set it |
|---|---|---|
| **Language** (`<lang>`) | *Which corpus to scan against* — `python`, `java`, … (the thing being measured) | The positional argument; **always required**, e.g. `eval-run python` |
| **Runner** (`DEFECT_SCAN_EVAL_RUNNER`) | *Which AI engine performs the scan* — `claude` vs `codex` (`tests/eval/runners/*.sh`) | An env var. `scripts/eval-run` auto-selects one; calling `detect.sh` directly requires you to `export` it (else it exits 3) |

(Analogy: the **language is the exam paper**; the **runner is which student sits it**. You always name the paper; the runner just chooses whether Claude or Codex takes the exam.)

The easiest entry point is the **`scripts/eval-run`** wrapper — it locates `detect.sh`
and auto-selects a runner (prefers `claude`, falls back to `codex`) if you haven't set
one, then forwards every flag through:

```sh
scripts/eval-run python                       # one run over the seen split, gate vs baseline
scripts/eval-run python --runs 5              # average 5 runs → mean ± stddev
scripts/eval-run python --split held-out      # score the overfitting-guard split
scripts/eval-run python --split all           # seen ∪ held-out
scripts/eval-run python --update-baseline     # rewrite baseline.<split>.txt from this run

# Override the auto-selected runner when you need a specific one:
DEFECT_SCAN_EVAL_RUNNER=tests/eval/runners/codex.sh scripts/eval-run rust
```

Or call the engine directly (you must set the runner yourself — `eval-run` exits 3 if
`DEFECT_SCAN_EVAL_RUNNER` is unset):

```sh
export DEFECT_SCAN_EVAL_RUNNER=tests/eval/runners/claude.sh   # or .../codex.sh
skills/scan/lib/detect.sh eval-run python --runs 5
```

`eval-run` runs the scan via the selected runner, scores each run with the model-free
grader, aggregates `mean ± stddev` across `--runs`, and **gates** the result against the
baseline (precision/recall floors, plus noise/overfit bands). Both runners are read-only:
`codex.sh` runs in a read-only sandbox, `claude.sh` under a read-only tool policy.

**Credentials.** The runners drive a real model and need auth. Locally, `codex.sh`
uses your existing `codex login`; `claude.sh` uses your local `claude`. In CI, the
`.github/workflows/eval-run.yml` job installs `@openai/codex` and runs
`codex login --with-api-key` from an **`OPENAI_API_KEY` secret** that you must add to the
repo's **`eval-run` Environment** (the same Environment gates the run behind required
reviewers, so the secret is never exposed to an unapproved dispatch). The workflow only
runs from `main`/`dev` (trusted-ref guard) and fails loudly if the secret is missing.

**Pick a runner whose model actually executes the scan.** The runner has to *run*
`/defect-scan:scan`, not just plan it. If your Codex is configured planning/verify-only
(e.g. a global `AGENTS.md` that forbids running commands — a common personal setup, since
Codex is also used here for read-only review), `codex.sh` will refuse and hand off; use
`claude.sh` instead. `codex.sh` is the right default in environments where Codex executes.

**Cost.** Each fixture is a full model scan session — empirically **~90s/fixture**. A
language has ~6 fixtures, so one run of one language is ~10 min; a real baseline
(`--runs 5` across all 13 languages, ~390 scans) is **multiple hours**. Treat a full
baseline sweep as a deliberate, batched (or overnight) job, not an inline command.

### Reading the corpus the way the grader does

```sh
detect.sh eval-categories python          # the valid label set: baseline cat#1..5 ∪ corpus labels
detect.sh eval-gaps python                # model-free coverage: per-category expected vs detected
detect.sh eval-gaps python --split all    # …for a given split
```

`eval-categories` prints the labels a `.expected` sidecar may use (the five baseline
categories union whatever the corpus already references). `eval-gaps` is a coverage
report — per category, how many expected findings vs how many the scan detected — read
from the last run's `.last-run` artifact, with no model in the loop.

### Baselines and artifacts

- **`baseline.<split>.txt`** — the gate's committed reference, one per split. Keys:
  `precision_floor`, `recall_floor`, `precision_baseline`, `recall_baseline`,
  `noise_band`, `overfit_band`. Regenerate it with `eval-run --update-baseline`, then
  commit the change through a **CODEOWNERS-reviewed PR** (this is moving the bar — it
  gets the same scrutiny as the ground truth).
  - **Calibration.** `precision_baseline`/`recall_baseline` are **measured** from real
    `eval-run` passes (not hand-tuned); the hard `*_floor` values stay conservative
    until a larger sweep justifies tightening them (a separate deliberate edit). A
    language with no measured baseline yet carries placeholder floors (`0.80`/`0.50`).
    Recalibrate when a profile materially changes — and only trust `--update-baseline`
    output from a run whose findings used the language's valid label set (see
    `eval-categories`); a label mismatch depresses the measured numbers, so don't bake
    those in.
- **`.last-run.<split>.txt`** — a **gitignored, transient** artifact from the most recent
  `eval-run`; it's what `eval-gaps` reads. Don't commit it.

### `_proposals/` — drafts, not ground truth

`tests/eval/_proposals/` is a staging dir the **grader ignores**. The completeness critic
may *draft* candidate fixtures there, but the model never authors ground truth: a **human**
writes the `.expected` label and moves the fixture into `seen/` or `held-out/` via a
CODEOWNERS-reviewed PR. Drafts in `_proposals/` score nothing until a person promotes them.

> **The honest caveat.** A green eval means the change **didn't get worse** against this
> corpus — *not* that the scanner got better at the real job. The corpus is a regression
> floor, not a proof of quality; treat a pass as "safe to ship," never as "improved."

## Adding to the corpus (Phase 2 workflow)

When a real bug escapes to production, or a finding is confirmed/dismissed, capture it
as a **new fixture + `.expected`** in a PR (see `CONTRIBUTING.md`). That — not a
runtime store — is the safe write path: human-reviewed, tested, versioned.

## Public-repo rules

This is a public repo, so the self-improvement loop has two hard rules:

1. **Fixtures must be synthetic.** Never paste proprietary code, customer code, or
   secrets into a fixture. An escaped-to-prod bug becomes a *minimized, synthetic
   reproduction* — the smallest standalone code that exhibits the defect. (CI's
   gitleaks scan guards secrets; the no-proprietary-code rule is on you.)
2. **The grader is protected.** CI proves a check isn't *noisy*; it can't catch a PR
   that *weakens the grader* (deleting a `clean_*` fixture, editing a `.expected` to
   bless a false positive). So `tests/eval/`, the `eval` scorer, and the profiles are
   **CODEOWNERS-protected** (`.github/CODEOWNERS`) and require maintainer review.

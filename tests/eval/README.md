# defect-scan eval corpus

A labeled fixture corpus for **measuring** whether a profile/pattern change makes the
scanner better — or just louder. This is the spine of safe self-improvement (issue
#15): the grader (`detect.sh eval`) is model-free and lives in git, separate from the
markdown the model reads, so improvement is measurable and can't silently regress.

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

Matching is by fixture **basename**:line:category, so score one dir at a time. The
scorer is deterministic and model-free — that's deliberate: the thing that judges
improvement must not be the thing being improved.

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

```sh
# Pick a runner first — eval-run exits 3 if DEFECT_SCAN_EVAL_RUNNER is unset.
export DEFECT_SCAN_EVAL_RUNNER=tests/eval/runners/codex.sh   # default; read-only sandbox
# or:  DEFECT_SCAN_EVAL_RUNNER=tests/eval/runners/claude.sh  # read-only tool policy

detect.sh eval-run python                       # one run over the seen split, gate vs baseline
detect.sh eval-run python --runs 5              # average 5 runs → mean ± stddev
detect.sh eval-run python --split held-out      # score the overfitting-guard split
detect.sh eval-run python --split all           # seen ∪ held-out
detect.sh eval-run python --update-baseline     # rewrite baseline.<split>.txt from this run
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

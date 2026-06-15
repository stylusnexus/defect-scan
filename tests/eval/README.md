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

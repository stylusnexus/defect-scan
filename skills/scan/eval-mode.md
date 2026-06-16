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

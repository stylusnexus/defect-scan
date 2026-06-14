# Manual verification scenarios

Run after `./install.sh`. Each is a behavior the automated tests cannot assert.

1. **Python tool-confirmed (High).** `/defect-scan tests/fixtures/python`
   → reports the bare-except (cat#2) as **High, tool-confirmed (ruff E722)**, and
   the unclosed file (cat#4) at least Medium.
2. **React reasoning (Medium/High).** `/defect-scan tests/fixtures/react-ts`
   → reports the leaked interval (cat#4) and the stale closure / missing deps
   (cat#5). exhaustive-deps may be tool-confirmed if eslint+plugin present.
3. **Adversarial refutation.** Point the scan at a file where a guard clause makes
   a suspected null-deref unreachable → the finding must be **dropped or Low**, not
   reported as High. (Plant one when testing.)
4. **Missing toolchain.** Temporarily rename `ruff` off PATH and re-run scenario 1
   → scan still completes; header lists ruff under "Tools missing" with an install
   hint; the bare-except now appears as a **reasoning** finding, not tool-confirmed.
5. **--fix safety on dirty tree.** With uncommitted changes present, `--fix`
   → refuses and explains; after committing, `--fix` applies only Auto-fix-safe
   High items and re-runs the tool to confirm.
6. **Generic fallback.** `/defect-scan tests/fixtures/empty` → uses the generic
   profile, reasoning-only, nothing ranked above Medium.
7. **Triage order on a large scope.** `/defect-scan --full` on a multi-file repo
   → the report header states the deep pass processed files in triage priority
   order (churn/size/security-sensitive first) and how far it reached.

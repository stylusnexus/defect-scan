# Profile: python

## Detection
`pyproject.toml`, `setup.py`, or any `*.py`. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>` (venv-first, then global). Skip-with-hint
if unresolved.
- `ruff check --output-format=json <files>`  — lint/correctness rules.
- `mypy --no-error-summary <files>`           — type errors.
Optional (deeper, run if installed):
- `bandit -f json -r <paths>`                 — security: subprocess (P4), SQL (P9),
  hardcoded secrets, weak crypto (cat#3). Findings are High (tool-confirmed).
- `pip-audit -f json`                         — known-vuln dependencies (a dimension
  reasoning can't see); High.
Install hints: `pip install ruff mypy` (or `uv pip install ruff mypy`);
optional: `pip install bandit pip-audit`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: unchecked `dict[...]`/attribute access, functions that may return `None`.
- cat#2: bare `except:` / `except Exception: pass`, swallowed errors.
- cat#3: f-string/`%`-built SQL, `subprocess(..., shell=True)`, `os.system`.
- cat#4: files/sockets opened without `with`, sessions not closed.
- cat#5: shared state without locks, `asyncio` blocking calls, mutable default args.
Python-specific: `==` vs `is` for identity, mutable default arguments,
late-binding closures in loops, `assert` used for runtime validation.

## Auto-fix-safe
Only `ruff`-confirmed rules with an autofix (`ruff check --fix` applies them) AND
the rule is in the safe set: bare-except → named except is NOT auto-safe (changes
semantics); unused-import / f-string-without-placeholder ARE. Type findings from
`mypy` are never auto-fixed (require human-chosen types).

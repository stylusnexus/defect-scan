---
name: shell
detect_files:
extensions: sh bash
tools: shellcheck
---
# Profile: shell

Promotes `shellcheck` from a cross-cutting analyzer to a first-class profile. defect-scan
is itself shell-heavy, so this profile **dogfoods on its own `lib/detect.sh` + hooks**.

## Detection
Any `*.sh`/`*.bash` (these are also in the always-on triage base set). There's no
reliable manifest file, so `detect_files` is empty and detection is **extension-only**.
Caveat: extensionless scripts with a `#!/bin/sh`/`#!/usr/bin/env bash` shebang won't
trigger detection by extension — the reasoning pass should still treat a shebanged file
in scope as shell. See `detect.sh stacks`.

## Toolchain
Resolve via `detect.sh tool <name>`. Source-only — no build.
- `shellcheck -f json <files>` — the shell static analyzer. Reads the shebang/`# shellcheck
  shell=` directive to pick the dialect (`sh` POSIX vs `bash`). Per-finding JSON with the
  `SCxxxx` code, line/col, and severity. Install: `brew install shellcheck` (or
  `apt-get install shellcheck`). Exit code 1 = findings (parse); a usage/parse error is
  inconclusive, not clean.

## Reasoning checklist
Baseline categories specialized (shellcheck `SCxxxx` / CWE):
- shell-specific (the #1 shell bug — word-splitting/globbing): **unquoted `$var` /
  `$(...)`** in a command or test — `rm $f`, `for x in $(ls)` — splits on `$IFS` and
  glob-expands, breaking on spaces/newlines/metachars (`SC2086` unquoted var, `SC2046`
  unquoted command-substitution, `SC2068` unquoted `$@` — use `"$@"`). Often a latent
  injection vector too.
- cat#2: **ignored exit codes / proceeding after failure** — `cd "$dir"` without
  `|| exit` (`SC2164` — a failed `cd` then runs the rest in the wrong directory),
  checking `$?` indirectly instead of `if cmd; then` (`SC2181`), `local x=$(cmd)` /
  `declare x=$(cmd)` masking the command's exit status (`SC2155`); missing
  `set -euo pipefail` so a failed command mid-script is silently ignored; `cmd | while
  read …` running the loop in a **subshell** so variable assignments are lost (`SC2031`/
  `SC2030`).
- cat#3: **command injection** — `eval` on interpolated/untrusted input, unquoted
  expansion into `ssh host $cmd` / `sh -c "$x"` / `bash -c`, building a command string
  from user data (CWE-78); untrusted path into `rm`/redirection (CWE-22).
- shell-specific (catastrophic): **`rm -rf "$VAR/"` / `rm -rf "$dir/"*` with a
  possibly-empty/unset `VAR`** → deletes from `/` or `$HOME`; guard with `${VAR:?}`
  (`SC2115`). Also `> "$file"` truncation with an unvalidated path.
- shell-specific (portability/correctness): **bashisms under `#!/bin/sh`** — `[[ ]]`,
  arrays, `local`, `==` in `[ ]`, `source`, `function` keyword — break on dash/POSIX sh
  (`SC2039`/`SC3xxx` in POSIX mode); `[ $x = y ]` with an unquoted possibly-empty `$x`
  (test syntax error — quote it); backticks vs `$(…)` (`SC2006`); `printf` with a
  variable format string (`SC2059`); `read` without `-r` mangling backslashes (`SC2162`).

## Auto-fix-safe
shellcheck has **no autofix** (it emits suggested diffs via `-f diff`, applied with
`shellcheck -f diff … | git apply`, but only for a mechanical subset). Treat shellcheck
findings as **report-only** — the right fix for an unquoted variable, an ignored exit
code, or an `eval` is a human decision (quoting can change intended word-splitting; the
fix for `rm -rf "$VAR/"` is a guard, not a rewrite). No security/quoting finding is
auto-fixed.

## Eval labels
quoting: unquoted `$var` / `$(...)` / `$@` in a command or test → word-splitting & glob expansion on spaces/newlines/metachars (SC2086/SC2046/SC2068); use `"$var"`/`"$@"`. NOT ignored exit codes (cat#2) or eval/command injection (cat#3).

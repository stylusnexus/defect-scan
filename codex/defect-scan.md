Run the **defect-scan** defect hunter under Codex, on the user's current repo.

The deterministic plumbing and ALL defect knowledge are **shared** with the Claude
plugin — do not reinvent them. This prompt is only the Codex-flavored *driver*; the
canonical spec is `skills/scan/SKILL.md` in the defect-scan install. Read it.

## 0. Locate the install (`DEFECT_SCAN_HOME`)

defect-scan must be checked out somewhere. Resolve its root, in order:

1. `$DEFECT_SCAN_HOME`, if set and it contains `skills/scan/lib/detect.sh`.
2. First of these that exists: `~/.defect-scan`, `~/src/defect-scan`, `~/code/defect-scan`.
3. Otherwise **stop** and tell the user:
   `git clone https://github.com/stylusnexus/defect-scan ~/.defect-scan && export DEFECT_SCAN_HOME=~/.defect-scan`

Let `H` = that root and `DETECT="$H/skills/scan/lib/detect.sh"`. `detect.sh` resolves
its own knowledge files from its script location, so it works regardless of your cwd
— always invoke it by that absolute path. The scan target is the user's **current
working directory** (a real git repo), never `$H`.

Read the canonical spec and knowledge before scanning:
`$H/skills/scan/SKILL.md`, `$H/skills/scan/baseline-categories.md`,
`$H/skills/scan/report-format.md`, and every file from
`"$DETECT" profiles "$PWD"` and `"$DETECT" patterns "$PWD"`.

## 1. Run the five stages

Follow `SKILL.md` exactly — it is the source of truth. Codex specifics: run the
shell directly, capture JSON with `jq`, read files with your own tools.

1. **Detect** — `"$DETECT" scope <target|--full> "$PWD"` and `"$DETECT" stacks "$PWD"`;
   load each matched profile via `"$DETECT" profiles "$PWD"`.
2. **Triage** — pipe the scoped files through `"$DETECT" triage "$PWD"`; deep-reason
   the top `--depth N` (default 20); the rest are tool-scanned only. Report coverage.
3. **Tool pass** — resolve each profile's tools with `"$DETECT" tool <name> "$PWD"`;
   run if resolved, else record missing-with-hint. Read exit codes (a tool *error* is
   inconclusive, not "clean"). **Origin-gate:** built-in profiles auto-run; for
   user/project profiles, CONFIRM with the user before running their tools.
4. **Reasoning pass** — read the in-scope files against each profile's checklist +
   `baseline-categories.md` + the pattern packs; run the **adversarial verification**
   step before ranking every reasoning-only finding.
5. **Report (→ correlate → file → fix)** — emit per `report-format.md`. Correlation
   (Stage 4a), `--file-issues` (Stage 4b), and `--fix`/`--fix-all` behave **exactly**
   as documented in `SKILL.md` — including the mandatory dedup gate, `gh` auth
   requirement, label/priority proposal, batch confirmation, and the dirty-tree
   refusal for fixes. Do not relax any of these invariants in the Codex port.

## 2. Arguments & flags

Identical to the skill: `(no arg)` = recent changes · `<path>` · `--full` ·
`--depth N` · `--lang <profile>` · `--no-correlate` · `--file-issues[=medium]` /
`--dry-run` · `--fix` / `--fix-all`. See `SKILL.md` "Arguments" for semantics.

## 3. Stay faithful to the safety model

Report-only by default. Never auto-run a scanned repo's profile tools (pattern P4).
Never file/​fix without the corresponding flag + confirmation. The Codex port must be
behavior-identical to the Claude skill — any divergence is a bug.

## 4. Eval mode (harness only)

**Eval mode (harness only).** When invoked by the eval harness, additionally follow
`eval-mode.md` to append the machine-readable `<<<EVAL>>>` findings block. Normal scans
never emit it.

#!/usr/bin/env sh
# Eval runner (Codex). Scans ONE source fixture read-only and prints the scan output
# (which must contain the eval-mode <<<EVAL>>> block). Never writes — mirrors
# cmd_codex_verify's sandbox. Usage: codex.sh <fixture-path> <lang> [<scan-profile>]
# arg3 (scan_profile) overrides the scan's --lang profile (e.g. eval-run --as) while the
# LABEL set still comes from <lang> (the corpus name); defaults to <lang>.
set -eu
fixture="${1:?codex.sh: need fixture path}"; lang="${2:?codex.sh: need lang}"
scan_profile="${3:-$lang}"
cx="${DEFECT_SCAN_CODEX:-codex}"
# Resolve the engine + this language's valid label set BEFORE cd-ing into the temp dir.
# Telling the model the exact label vocabulary stops it inventing synonyms (panic vs
# unwrap-panic) that the exact-match grader can't score. eval-categories is read-only.
detect="$(CDPATH= cd "$(dirname "$0")/../../.." && pwd)/skills/scan/lib/detect.sh"
labels="$(sh "$detect" eval-categories "$lang" 2>/dev/null | tr '\n' ' ')"
if [ -n "$labels" ]; then
  labelinstr="Use ONLY these category labels (exact strings, nothing else): $labels"
else
  labelinstr="category = cat#1..cat#5 or a language-specific label"
fi
# Opaque label IDs (cat#1..6 + language-specific) need their definitions inline so the
# model labels by meaning, not by guessing — keeps this runner self-contained and parallel
# with claude.sh (divergence is a bug). The full legend (cat# bodies + language-specific
# label defs) is built once by detect.sh. See #68 (title-only legend) / #105 (full).
legend="$(sh "$detect" eval-legend "$lang" 2>/dev/null)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# A DIRECTORY fixture is a mini-repo: copy its contents and scan the whole dir, asking
# for paths relative to it. A FILE fixture: copy the one file and scan its basename.
if [ -d "$fixture" ]; then
  cp -R "$fixture"/. "$work/"                 # contents only — the .expected sidecar is a sibling, not inside
  scan_instr="Run /defect-scan:scan on the directory in this directory (.) with --lang $scan_profile."
  reason_instr="reason directly about the files in this directory."
  path_instr="path = the file's path relative to this directory (e.g. src/index.js), NOT just the basename"
else
  cp "$fixture" "$work/"                      # SOURCE only — never the .expected sidecar
  scan_instr="Run /defect-scan:scan on the file in this directory with --lang $scan_profile."
  reason_instr="reason directly about the single file in this directory."
  path_instr="path = the file's basename; line = integer"
fi
prompt="$(mktemp)"
{
  echo "$scan_instr"
  echo "The category definitions are provided inline below, so do NOT read baseline-categories.md,"
  echo "eval-mode.md, or any other skill file, and skip the git/correlation/tool-resolution stages —"
  echo "$reason_instr"
  echo "Category definitions: $legend"
  echo "After the normal report, append EXACTLY ONE machine block for the grader:"
  echo 'a line "<<<EVAL", then one line per finding as "<path>:<line>:<category>"'
  echo "($path_instr). $labelinstr"
  echo "Then a line \"EVAL>>>\". If you find nothing, emit the two sentinel lines with"
  echo "nothing between. Always emit the block; never omit it."
} > "$prompt"
cd "$work"
"$cx" exec --sandbox read-only --skip-git-repo-check -o /dev/stdout - < "$prompt"
rm -f "$prompt"

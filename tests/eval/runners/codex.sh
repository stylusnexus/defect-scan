#!/usr/bin/env sh
# Eval runner (Codex). Scans ONE source fixture read-only and prints the scan output
# (which must contain the eval-mode <<<EVAL>>> block). Never writes — mirrors
# cmd_codex_verify's sandbox. Usage: codex.sh <fixture-path> <lang>
set -eu
fixture="${1:?codex.sh: need fixture path}"; lang="${2:?codex.sh: need lang}"
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
# Opaque label IDs (cat#1..5) need their definitions inline so the model labels by meaning,
# not by guessing the numbers — keeps this runner self-contained and parallel with
# claude.sh (divergence between runners is a bug). See issue #68.
legend="$(awk '/^## [0-9]+\./ { n=$2; sub(/\./,"",n); t=$0; sub(/^## [0-9]+\. /,"",t); sub(/  .*/,"",t); printf "cat#%s = %s; ", n, t }' "$(dirname "$detect")/../baseline-categories.md" 2>/dev/null)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$fixture" "$work/"                       # SOURCE only — never the .expected sidecar
prompt="$(mktemp)"
{
  echo "Run /defect-scan:scan on the file in this directory with --lang $lang."
  echo "The category definitions are provided inline below, so do NOT read baseline-categories.md,"
  echo "eval-mode.md, or any other skill file, and skip the git/correlation/tool-resolution stages —"
  echo "reason directly about the single file in this directory."
  echo "Category definitions: $legend"
  echo "After the normal report, append EXACTLY ONE machine block for the grader:"
  echo 'a line "<<<EVAL", then one line per finding as "<path>:<line>:<category>"'
  echo "(path = the file's basename; line = integer). $labelinstr"
  echo "Then a line \"EVAL>>>\". If you find nothing, emit the two sentinel lines with"
  echo "nothing between. Always emit the block; never omit it."
} > "$prompt"
cd "$work"
"$cx" exec --sandbox read-only --skip-git-repo-check -o /dev/stdout - < "$prompt"
rm -f "$prompt"

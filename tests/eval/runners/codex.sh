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
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$fixture" "$work/"                       # SOURCE only — never the .expected sidecar
prompt="$(mktemp)"
{
  echo "Run /defect-scan:scan on the file in this directory with --lang $lang."
  echo "After the normal report, append EXACTLY ONE machine block for the grader:"
  echo 'a line "<<<EVAL", then one line per finding as "<path>:<line>:<category>"'
  echo "(path = the file's basename; line = integer). $labelinstr"
  echo "Then a line \"EVAL>>>\". If you find nothing, emit the two sentinel lines with"
  echo "nothing between. Do not omit the block."
} > "$prompt"
cd "$work"
"$cx" exec --sandbox read-only --skip-git-repo-check -o /dev/stdout - < "$prompt"
rm -f "$prompt"

#!/usr/bin/env sh
# Eval runner (Claude Code, headless, READ-ONLY). Scans ONE source fixture and prints
# output containing the eval-mode <<<EVAL>>> block. Read-only tool policy: no file
# writes, no shell mutation. Usage: claude.sh <fixture-path> <lang>
set -eu
fixture="${1:?claude.sh: need fixture path}"; lang="${2:?claude.sh: need lang}"
cc="${DEFECT_SCAN_CLAUDE:-claude}"
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
cp "$fixture" "$work/"                        # SOURCE only — never the .expected sidecar
cd "$work"
# Read-only: deny mutating tools so a runner can never edit the repo under test.
"$cc" -p "Run /defect-scan:scan $(basename "$fixture") --lang $lang.
After the normal report, append EXACTLY ONE machine block for the grader:
a line \"<<<EVAL\", then one line per finding as \"<path>:<line>:<category>\"
(path = the file's basename; line = integer). $labelinstr
Then a line \"EVAL>>>\". If you find nothing, emit the two sentinel lines with
nothing between. Do not omit the block." \
  --permission-mode plan \
  --disallowedTools "Edit,Write,NotebookEdit"

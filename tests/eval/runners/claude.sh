#!/usr/bin/env sh
# Eval runner (Claude Code, headless, READ-ONLY). Scans ONE source fixture and prints
# output containing the eval-mode <<<EVAL>>> block. Read-only tool policy: no file
# writes, no shell mutation. Usage: claude.sh <fixture-path> <lang>
set -eu
fixture="${1:?claude.sh: need fixture path}"; lang="${2:?claude.sh: need lang}"
cc="${DEFECT_SCAN_CLAUDE:-claude}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$fixture" "$work/"                        # SOURCE only — never the .expected sidecar
cd "$work"
# Read-only: deny mutating tools so a runner can never edit the repo under test.
"$cc" -p "Run /defect-scan:scan $(basename "$fixture") --lang $lang.
After the normal report, append EXACTLY ONE machine block for the grader:
a line \"<<<EVAL\", then one line per finding as \"<path>:<line>:<category>\"
(path = the file's basename; line = integer; category = cat#1..cat#5 or a
language-specific label), then a line \"EVAL>>>\". If you find nothing, emit the
two sentinel lines with nothing between. Do not omit the block." \
  --permission-mode plan \
  --disallowedTools "Edit,Write,NotebookEdit"

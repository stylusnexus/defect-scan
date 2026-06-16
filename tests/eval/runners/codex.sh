#!/usr/bin/env sh
# Eval runner (Codex). Scans ONE source fixture read-only and prints the scan output
# (which must contain the eval-mode <<<EVAL>>> block). Never writes — mirrors
# cmd_codex_verify's sandbox. Usage: codex.sh <fixture-path> <lang>
set -eu
fixture="${1:?codex.sh: need fixture path}"; lang="${2:?codex.sh: need lang}"
cx="${DEFECT_SCAN_CODEX:-codex}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$fixture" "$work/"                       # SOURCE only — never the .expected sidecar
prompt="$(mktemp)"
{
  echo "Run /defect-scan:scan on the file in this directory with --lang $lang."
  echo "After the normal report, append EXACTLY ONE machine block for the grader:"
  echo 'a line "<<<EVAL", then one line per finding as "<path>:<line>:<category>"'
  echo "(path = the file's basename; line = integer; category = cat#1..cat#5 or a"
  echo "language-specific label), then a line \"EVAL>>>\". If you find nothing, emit the"
  echo "two sentinel lines with nothing between. Do not omit the block."
} > "$prompt"
cd "$work"
"$cx" exec --sandbox read-only --skip-git-repo-check -o /dev/stdout - < "$prompt"
rm -f "$prompt"

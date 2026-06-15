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
"$cc" -p "/defect-scan:scan $(basename "$fixture") --lang $lang ; then follow eval-mode.md and append one <<<EVAL>>> block" \
  --permission-mode plan \
  --disallowedTools "Edit,Write,NotebookEdit"

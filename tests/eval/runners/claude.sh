#!/usr/bin/env sh
# Eval runner (Claude Code, headless, READ-ONLY). Scans ONE source fixture and prints
# output containing the eval-mode <<<EVAL>>> block. Read-only tool policy: no file
# writes, no shell mutation. Usage: claude.sh <fixture-path> <lang> [<scan-profile>]
# arg3 (scan_profile) overrides the scan's --lang profile (e.g. eval-run --as) while the
# LABEL set still comes from <lang> (the corpus name); defaults to <lang>.
set -eu
fixture="${1:?claude.sh: need fixture path}"; lang="${2:?claude.sh: need lang}"
scan_profile="${3:-$lang}"
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
# The labels above are opaque IDs (cat#1..5). The headless run is sandboxed to the temp
# work dir, so the model CANNOT read the skill's baseline-categories.md to learn what they
# mean — without the definitions it thrashes on denied reads (→ missing EVAL block, PARTIAL)
# and guesses categories (cat#2-vs-cat#3 flips). Inject the definitions inline from the dev
# repo so the run is self-contained. See issue #68.
legend="$(awk '/^## [0-9]+\./ { n=$2; sub(/\./,"",n); t=$0; sub(/^## [0-9]+\. /,"",t); sub(/  .*/,"",t); printf "cat#%s = %s; ", n, t }' "$(dirname "$detect")/../baseline-categories.md" 2>/dev/null)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# A DIRECTORY fixture is a mini-repo: copy its contents and scan the whole dir, asking
# for paths relative to it. A FILE fixture: copy the one file and scan its basename.
if [ -d "$fixture" ]; then
  cp -R "$fixture"/. "$work/"                  # contents only — the .expected sidecar is a sibling, not inside
  scan_target="."
  reason_instr="reason directly about the files in your current directory."
  path_instr="path = the file's path relative to this directory (e.g. src/index.js), NOT just the basename"
else
  cp "$fixture" "$work/"                        # SOURCE only — never the .expected sidecar
  scan_target="$(basename "$fixture")"
  reason_instr="reason directly about the single file in your current directory."
  path_instr="path = the file's basename; line = integer"
fi
cd "$work"
# Read-only: deny mutating tools so a runner can never edit the repo under test.
"$cc" -p "Run /defect-scan:scan $scan_target --lang $scan_profile.
The category definitions are provided inline below, so do NOT read baseline-categories.md,
eval-mode.md, or any other skill file, and skip the git/correlation/tool-resolution stages —
$reason_instr
Category definitions: $legend
After the normal report, append EXACTLY ONE machine block for the grader:
a line \"<<<EVAL\", then one line per finding as \"<path>:<line>:<category>\"
($path_instr). $labelinstr
Then a line \"EVAL>>>\". If you find nothing, emit the two sentinel lines with
nothing between. Always emit the block; never omit it." \
  --permission-mode plan \
  --disallowedTools "Edit,Write,NotebookEdit"

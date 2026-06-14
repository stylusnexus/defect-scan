#!/usr/bin/env sh
# Opt-in pre-commit advisory for the defect-scan plugin.
#
# OFF by default. When DEFECT_SCAN_HOOK is set, and Claude is about to run a
# `git commit` via Bash, this runs defect-scan's DETERMINISTIC tool pass over the
# CHANGED source files only and prints a one-line advisory. It is report-only and
# NEVER blocks the commit — it always exits 0. (A shell hook can't run the
# reasoning pass; for that, run /defect-scan:scan.)
set -u

[ -n "${DEFECT_SCAN_HOOK:-}" ] || exit 0          # opt-in gate
command -v jq >/dev/null 2>&1 || exit 0           # need jq to read the payload

payload="$(cat 2>/dev/null)" || exit 0
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
case "$cmd" in
  *"git commit"*) : ;;
  *) exit 0 ;;                                     # only nudge on commits
esac

DETECT="${CLAUDE_PLUGIN_ROOT:-}/skills/scan/lib/detect.sh"
[ -x "$DETECT" ] || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

changed="$("$DETECT" scope "" "" "$root" 2>/dev/null | tail -n +2 \
            | "$DETECT" triage "$root" 2>/dev/null | cut -f2)"
[ -n "$changed" ] || exit 0
n_files="$(printf '%s\n' "$changed" | sed '/^$/d' | wc -l | tr -d ' ')"

findings=0
if printf '%s\n' "$changed" | grep -q '\.py$'; then
  ruff="$("$DETECT" tool ruff "$root" 2>/dev/null || true)"
  if [ -n "$ruff" ]; then
    c="$(printf '%s\n' "$changed" | grep '\.py$' \
          | xargs "$ruff" check --output-format=concise 2>/dev/null \
          | grep -cE ':[0-9]+:[0-9]+:' || true)"
    findings=$((findings + ${c:-0}))
  fi
fi

printf 'defect-scan: %s tool-confirmed issue(s) across %s changed source file(s). Run /defect-scan:scan for the full report. (advisory — commit not blocked)\n' \
  "$findings" "$n_files" >&2
exit 0

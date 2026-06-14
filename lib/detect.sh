#!/usr/bin/env sh
# detect.sh — deterministic plumbing for the defect-scan skill.
# Subcommands: stacks <dir> | tool <name> [cwd] | scope [target] [--full] [cwd]
set -eu

cmd_stacks() { :; }   # implemented in Task 2
cmd_tool()   { :; }   # implemented in Task 3
cmd_scope()  { :; }   # implemented in Task 4

main() {
  sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    stacks) cmd_stacks "$@" ;;
    tool)   cmd_tool "$@" ;;
    scope)  cmd_scope "$@" ;;
    *) echo "usage: detect.sh {stacks|tool|scope} ..." >&2; return 2 ;;
  esac
}
main "$@"

#!/usr/bin/env sh
# detect.sh — deterministic plumbing for the defect-scan skill.
# Subcommands: stacks <dir> | tool <name> [cwd] | scope [target] [--full] [cwd]
set -eu

cmd_stacks() {
  root="${1:?usage: detect.sh stacks <dir>}"
  found=""
  # React/TypeScript: a package.json plus either a tsconfig or any .ts/.tsx file.
  if [ -f "$root/package.json" ]; then
    if [ -f "$root/tsconfig.json" ] || \
       find "$root" -type f \( -name '*.ts' -o -name '*.tsx' \) 2>/dev/null | head -1 | grep -q .; then
      found="$found react-typescript"
    fi
  fi
  # Python: pyproject.toml, setup.py, or any .py file.
  if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] || \
     find "$root" -type f -name '*.py' 2>/dev/null | head -1 | grep -q .; then
    found="$found python"
  fi
  [ -n "$found" ] || found="generic"
  for p in $found; do echo "$p"; done
}
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

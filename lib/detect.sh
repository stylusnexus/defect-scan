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
cmd_tool() {
  name="${1:?usage: detect.sh tool <name> [cwd]}"
  cwd="${2:-$PWD}"
  # 1. JS/TS project-local
  if [ -x "$cwd/node_modules/.bin/$name" ]; then
    echo "$cwd/node_modules/.bin/$name"; return 0
  fi
  # 2. Python venv (active env, then project .venv)
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/$name" ]; then
    echo "$VIRTUAL_ENV/bin/$name"; return 0
  fi
  if [ -x "$cwd/.venv/bin/$name" ]; then
    echo "$cwd/.venv/bin/$name"; return 0
  fi
  # 3. Global PATH
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"; return 0
  fi
  return 1
}
cmd_scope() {
  target=""; full=""; cwd=""
  # Collect positional (non-flag, non-empty) args in order.
  # Convention: scope [target] [--full] [cwd]
  # The LAST positional arg is always the repo cwd (an absolute dir path).
  # The FIRST positional arg (if present and not the same as cwd) is the target.
  p1=""; p2=""
  for a in "$@"; do
    case "$a" in
      --full) full="1" ;;
      "") : ;;
      *) if [ -z "$p1" ]; then p1="$a"; elif [ -z "$p2" ]; then p2="$a"; fi ;;
    esac
  done
  # If two positional args: first=target, second=cwd.
  # If one positional arg: it's the cwd (no target).
  if [ -n "$p2" ]; then
    target="$p1"; cwd="$p2"
  elif [ -n "$p1" ]; then
    cwd="$p1"
  fi
  cwd="${cwd:-$PWD}"
  cd "$cwd" || return 1

  if [ -n "$full" ]; then
    echo "MODE=full"; git ls-files; return 0
  fi
  if [ -n "$target" ]; then
    echo "MODE=path"
    if [ -d "$target" ]; then git ls-files -- "$target"; else echo "$target"; fi
    return 0
  fi
  echo "MODE=changes"
  if ! git rev-parse --git-dir >/dev/null 2>&1; then return 1; fi
  changed="$(git diff --name-only; git diff --cached --name-only; \
             git ls-files --others --exclude-standard)"
  if [ -z "$changed" ]; then
    changed="$(git diff --name-only HEAD~1 2>/dev/null || true)"
  fi
  printf '%s\n' "$changed" | sort -u | sed '/^$/d'
}

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

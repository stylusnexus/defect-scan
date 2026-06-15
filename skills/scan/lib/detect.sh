#!/usr/bin/env sh
# detect.sh — deterministic plumbing for the defect-scan skill.
# Subcommands: stacks <dir> | tool <name> [cwd] | scope [target] [--full] [cwd]
set -eu

# Absolute path to this skill dir (the dir containing lib/). Works via symlink.
skill_dir() { CDPATH= cd -- "$(dirname -- "$0")/.." && pwd; }

# fm_get <file> <key>: print the frontmatter value for <key>. Frontmatter is the
# block between the first two '---' lines. Lists (comma/space) → space-separated.
# Trailing '# comment' is stripped. Prints nothing if absent / no frontmatter.
fm_get() {
  awk -v k="$2" '
    NR==1 && $0!="---" { exit }
    NR==1 { next }
    $0=="---" { exit }
    {
      i=index($0,":"); if (i==0) next
      key=substr($0,1,i-1); val=substr($0,i+1)
      sub(/[ \t]*#.*$/,"",val)
      gsub(/^[ \t]+|[ \t]+$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",val)
      gsub(/,/," ",val); gsub(/[ \t]+/," ",val)
      gsub(/^ | $/,"",val)
      if (key==k) { print val; exit }
    }
  ' "$1" 2>/dev/null
}

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
  # Dart/Flutter: pubspec.yaml or any .dart file.
  if [ -f "$root/pubspec.yaml" ] || \
     find "$root" -type f -name '*.dart' 2>/dev/null | head -1 | grep -q .; then
    found="$found dart"
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

cmd_triage() {
  cwd="${1:-$PWD}"
  cd "$cwd" || return 1
  # Churn in ONE git pass (not per-file): count commits touching each path.
  # Per-file `git log` does not scale — a 16k-file repo means 16k git processes,
  # each walking full history. One `--name-only` pass + tally is O(history) once.
  churn_file="$(mktemp 2>/dev/null || echo "/tmp/defect-scan-churn.$$")"
  git log --name-only --pretty=format: 2>/dev/null | sed '/^$/d' | sort | uniq -c \
    > "$churn_file" 2>/dev/null || : > "$churn_file"
  # Pre-filter before awk. Two jobs, both shell builtins (no subprocess) so they
  # stay fast on large repos:
  #  1. Drop directories (incl. symlinks to dirs): getline on a directory is a
  #     fatal i/o error in BSD awk and would truncate the ranking.
  #  2. Keep only source extensions: defect-scan targets code, so docs/config/data
  #     (e.g. high-churn .md memory files) must not out-rank source. Non-existent
  #     paths with a source extension are kept (ranked loc=0) so callers can triage
  #     not-yet-written files.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -d "$f" ] && continue
    case "$f" in
      *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.pyi|*.go|*.rs|*.c|*.cc|*.cpp|*.cxx|\
      *.h|*.hpp|*.hh|*.cs|*.java|*.rb|*.php|*.swift|*.kt|*.kts|*.scala|*.dart|*.sh|*.bash) ;;
      *) continue ;;
    esac
    printf '%s\n' "$f"
  done | awk '
    NR==FNR {
      cnt=$1
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")   # strip "  N " -> bare path
      churn[$0]=cnt; next
    }
    {
      f=$0; if (f=="") next
      ch=(f in churn)?churn[f]:0
      loc=0; while ((getline line < f) > 0) loc++; close(f)
      sec=(tolower(f) ~ /auth|login|session|password|secret|token|crypto|query|sql|exec|eval|admin|payment/)?10:0
      printf "%d\t%s\n", ch*3 + sec + int(loc/50), f
    }
  ' "$churn_file" - | sort -rn -k1,1
  rm -f "$churn_file"
}

# Correlate a finding against existing tracker issues. Search-driven (NOT a bulk
# pull) so it scales past the default `gh` 30-item cap and a 2000+ issue repo:
# one targeted search per call, capped at DEFECT_SCAN_ISSUE_LIMIT. Degrades
# cleanly (exit 3, no stdout) when gh is missing or the query fails — correlation
# is an enhancement, never a hard dependency. DEFECT_SCAN_GH overrides the binary
# (used by tests to stay offline).
cmd_issues() {
  [ $# -ge 1 ] || { echo "usage: detect.sh issues <keyword> [keyword...]" >&2; return 2; }
  gh_bin="${DEFECT_SCAN_GH:-gh}"
  command -v "$gh_bin" >/dev/null 2>&1 || {
    echo "defect-scan: gh not available; skipping issue correlation" >&2; return 3; }
  out="$("$gh_bin" issue list --state all --limit "${DEFECT_SCAN_ISSUE_LIMIT:-60}" \
          --search "$*" --json number,state,title 2>/dev/null)" || {
    echo "defect-scan: issue query failed (no remote / not authenticated)" >&2; return 3; }
  [ -n "$out" ] || return 0
  printf '%s' "$out" | jq -r '.[] | "#\(.number)\t\(.state)\t\(.title)"'
}

# fm_field <name> <key> [repo]: effective value for <key> of profile <name>,
# taking the highest-precedence layer that DEFINES the key (field inheritance).
fm_field() {
  fname="$1"; fkey="$2"; repo="${3:-$PWD}"
  # Reverse profile_layers output to get high→low precedence order.
  hi="$(profile_layers "$repo" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')"
  # Walk layers high→low; collect the first (highest-precedence) non-empty value.
  # We avoid pipe-subshell `return` issues by reading into a variable via process
  # substitution and breaking as soon as we have a value.
  result=""
  while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      n="$(fm_get "$f" name)"; [ -n "$n" ] || n="$(basename "$f" .md)"
      [ "$n" = "$fname" ] || continue
      v="$(fm_get "$f" "$fkey")"
      if [ -n "$v" ]; then result="$v"; break 2; fi
    done
  done <<EOF
$hi
EOF
  [ -n "$result" ] && printf '%s\n' "$result"
}

# Echo the enabled profile dirs, low→high precedence, one per line.
profile_layers() {
  repo="${1:-$PWD}"
  echo "$(skill_dir)/profiles"                                   # builtin
  [ -n "${DEFECT_SCAN_NO_USER:-}" ]    || echo "$HOME/.config/defect-scan/profiles"
  [ -n "${DEFECT_SCAN_NO_PROJECT:-}" ] || echo "$repo/.defect-scan/profiles"
}

cmd_profiles() {
  repo="${1:-$PWD}"
  { profile_layers "$repo" | while IFS= read -r dir; do
      case "$dir" in
        "$repo/.defect-scan/"*) origin=project ;;
        "$HOME/.config/"*) origin=user ;;
        *) origin=builtin ;;
      esac
      [ -d "$dir" ] || continue
      for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        name="$(fm_get "$f" name)"; [ -n "$name" ] || name="$(basename "$f" .md)"
        printf '%s\t%s\t%s\n' "$name" "$f" "$origin"
      done
    done; } | awk -F'\t' '{m[$1]=$0} END{for(k in m) print m[k]}'
}

main() {
  sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    stacks)    cmd_stacks "$@" ;;
    tool)      cmd_tool "$@" ;;
    scope)     cmd_scope "$@" ;;
    triage)    cmd_triage "$@" ;;
    issues)    cmd_issues "$@" ;;
    profiles)  cmd_profiles "$@" ;;
    __fmget)   fm_get "$@" ;;
    __fmfield) fm_field "$@" ;;
    *) echo "usage: detect.sh {stacks|tool|scope|triage|issues|profiles} ..." >&2; return 2 ;;
  esac
}
main "$@"

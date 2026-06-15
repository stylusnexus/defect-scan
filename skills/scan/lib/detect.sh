#!/usr/bin/env sh
# detect.sh — deterministic plumbing for the defect-scan skill.
# Subcommands: stacks|tool|scope|triage|issues|profiles|patterns
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
  matched="$("$0" profiles "$root" | while IFS="$(printf '\t')" read -r name _ _; do
    [ "$name" = "generic" ] && continue
    df="$(fm_field "$name" detect_files "$root" 2>/dev/null || :)"
    ext="$(fm_field "$name" extensions "$root" 2>/dev/null || :)"
    m=""
    for f in $df;  do [ -e "$root/$f" ] && m=1; done
    for e in $ext; do find "$root" -type f -name "*.$e" 2>/dev/null | head -n 1 | grep -q . && m=1; done
    [ -n "$m" ] && echo "$name"
  done | sort -u)"
  if [ -n "$matched" ]; then printf '%s\n' "$matched"; else echo "generic"; fi
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
    # Clean working tree: fall back to the last commit's net effect. For a normal
    # --no-ff feature merge, HEAD~1 (first-parent diff) is exactly the merged work.
    changed="$(git diff --name-only HEAD~1 2>/dev/null || true)"
  fi
  if [ -z "$changed" ]; then
    # HEAD~1 was empty too — the no-op back-merge case (HEAD's tree already equals
    # its first parent's, the common post-merge/post-deploy state). Resolve the
    # most recent NON-merge commit and diff it against its parent so the scan still
    # has the last real change to chew on instead of dead-ending.
    last="$(git rev-list --no-merges -1 HEAD 2>/dev/null || true)"
    if [ -n "$last" ]; then
      parent="$(git rev-parse --verify -q "${last}^" || true)"
      if [ -n "$parent" ]; then
        changed="$(git diff --name-only "$parent" "$last" 2>/dev/null || true)"
      else
        # Root commit (no parent): everything it introduced.
        changed="$(git show --name-only --pretty=format: "$last" 2>/dev/null || true)"
      fi
    fi
  fi
  changed="$(printf '%s\n' "$changed" | sort -u | sed '/^$/d')"
  if [ -z "$changed" ]; then
    # Never dead-end silently — the agent must be able to tell "tool found nothing"
    # from "tool couldn't resolve a scope."
    echo "defect-scan: no uncommitted changes and no resolvable recent-commit diff (merge-only history?) — pass a <path> or use --full" >&2
    return 0
  fi
  printf '%s\n' "$changed"
}

# Union of every discovered profile's extensions + an always-on base, space-sep.
all_extensions() {
  repo="${1:-$PWD}"
  { echo "sh bash"
    "$0" profiles "$repo" | while IFS="$(printf '\t')" read -r name _ _; do
      fm_field "$name" extensions "$repo" || :
    done
  } | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' '
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
  exts=" $(all_extensions "$cwd") "
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -d "$f" ] && continue
    e="${f##*.}"
    case "$exts" in *" $e "*) : ;; *) continue ;; esac
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

# List the remote repo's existing label names (one per line). The SKILL reasons
# over these to PROPOSE an existing defect-related label (bug/defect/…) rather than
# assuming one or creating noise. Degrades cleanly (exit 3) when gh is missing or
# the query fails. DEFECT_SCAN_GH overrides the binary (tests stay offline).
cmd_labels() {
  gh_bin="${DEFECT_SCAN_GH:-gh}"
  command -v "$gh_bin" >/dev/null 2>&1 || {
    echo "defect-scan: gh not available; cannot read labels" >&2; return 3; }
  "$gh_bin" label list --limit "${DEFECT_SCAN_LABEL_LIMIT:-200}" --json name --jq '.[].name' 2>/dev/null || {
    echo "defect-scan: label query failed (no remote / not authenticated)" >&2; return 3; }
}

# Ensure a label exists before filing. Best-effort: an "already exists" error is
# fine (we only want it present), and a failure here must NEVER block filing — the
# caller ignores the exit. Exit 3 if gh is unavailable. DEFECT_SCAN_GH overrides.
# Usage: detect.sh issues-ensure-label <name> [color] [description]
cmd_issues_ensure_label() {
  [ $# -ge 1 ] || { echo "usage: detect.sh issues-ensure-label <name> [color] [desc]" >&2; return 2; }
  gh_bin="${DEFECT_SCAN_GH:-gh}"
  command -v "$gh_bin" >/dev/null 2>&1 || return 3
  name="$1"; color="${2:-5319e7}"; desc="${3:-Filed by defect-scan}"
  "$gh_bin" label create "$name" --color "$color" --description "$desc" >/dev/null 2>&1 || true
}

# File a tracker issue from a finding. OUTWARD-FACING and DEDUP-GATED: the SKILL
# must call this ONLY for findings the correlation stage (cmd_issues) tagged [NEW],
# and only after confirming the batch with the user (see SKILL Stage 4b). This
# helper is the dumb create primitive — it does not itself dedupe; the dedupe gate
# lives in the SKILL because it requires reasoning over search results, not string
# matching. Prints the new issue URL on success. Degrades cleanly (exit 3) when gh
# is missing/unauthenticated, like cmd_issues. DEFECT_SCAN_GH overrides the binary
# (tests stay offline). Body is passed via file so multi-line content is safe.
# Usage: detect.sh issues-create <title> <body-file> [comma,separated,labels]
cmd_issues_create() {
  [ $# -ge 2 ] || { echo "usage: detect.sh issues-create <title> <body-file> [comma,labels]" >&2; return 2; }
  title="$1"; body_file="$2"; labels="${3:-}"
  [ -f "$body_file" ] || { echo "defect-scan: body file not found: $body_file" >&2; return 2; }
  gh_bin="${DEFECT_SCAN_GH:-gh}"
  command -v "$gh_bin" >/dev/null 2>&1 || {
    echo "defect-scan: gh not available; cannot file issue" >&2; return 3; }
  if [ -n "$labels" ]; then set -- --label "$labels"; else set --; fi
  "$gh_bin" issue create --title "$title" --body-file "$body_file" "$@" 2>/dev/null || {
    echo "defect-scan: issue creation failed (no remote / not authenticated / label missing)" >&2; return 3; }
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

cmd_patterns() {
  repo="${1:-$PWD}"
  echo "$(skill_dir)/patterns/recurring.md"
  [ -n "${DEFECT_SCAN_NO_USER:-}" ]    || for f in "$HOME/.config/defect-scan/patterns"/*.md; do [ -f "$f" ] && echo "$f"; done
  [ -n "${DEFECT_SCAN_NO_PROJECT:-}" ] || for f in "$repo/.defect-scan/patterns"/*.md; do [ -f "$f" ] && echo "$f"; done
}

# eval <corpus-dir> <findings-file>: model-FREE scorer for the per-language eval.
# This is the un-gameable grader — it deliberately contains NO model, so the thing
# that judges "did a profile change improve the scan" is a deterministic, testable
# artifact separate from the markdown the model reads.
#
# Inputs:
#   <corpus-dir>      a dir of fixtures, each with a sibling "<fixture>.expected"
#                     sidecar. Each sidecar line is "<line>:<category>" (e.g.
#                     "12:cat#4"); an EMPTY sidecar means the fixture must produce
#                     ZERO findings (a clean fixture — the false-positive tripwire).
#   <findings-file>   lines of "<path>:<line>:<category>" from a scan of the corpus.
# Keys are matched by fixture BASENAME:line:category, so score one corpus dir at a
# time. Prints: precision recall tp fp fn  (precision-first: a finding on a clean
# fixture is an FP; precision drops — that is the regression signal).
cmd_eval() {
  dir="${1:?usage: detect.sh eval <corpus-dir> <findings-file>}"
  findings="${2:?usage: detect.sh eval <corpus-dir> <findings-file>}"
  [ -d "$dir" ]      || { echo "eval: corpus dir not found: $dir" >&2; return 2; }
  [ -f "$findings" ] || { echo "eval: findings file not found: $findings" >&2; return 2; }
  exp="$(mktemp 2>/dev/null || echo "/tmp/ds-eval-exp.$$")"
  act="$(mktemp 2>/dev/null || echo "/tmp/ds-eval-act.$$")"
  # Expected set: prefix each "<line>:<cat>" with its fixture basename.
  for f in "$dir"/*.expected; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .expected)"
    # `|| [ -n "$ln" ]` so a final line with no trailing newline is still processed —
    # a grader must not silently drop the last finding.
    while IFS= read -r ln || [ -n "$ln" ]; do
      [ -n "$ln" ] || continue
      case "$ln" in \#*) continue ;; esac
      printf '%s:%s\n' "$base" "$ln"
    done < "$f"
  done | sort -u > "$exp"
  # Actual set: normalize each finding's path to its basename so it matches.
  while IFS= read -r ln || [ -n "$ln" ]; do
    [ -n "$ln" ] || continue
    case "$ln" in \#*) continue ;; esac
    p="${ln%%:*}"; rest="${ln#*:}"
    printf '%s:%s\n' "$(basename "$p")" "$rest"
  done < "$findings" | sort -u > "$act"
  tp=$(comm -12 "$exp" "$act" | grep -c . || true)
  fp=$(comm -13 "$exp" "$act" | grep -c . || true)
  fn=$(comm -23 "$exp" "$act" | grep -c . || true)
  rm -f "$exp" "$act"
  awk -v tp="$tp" -v fp="$fp" -v fn="$fn" 'BEGIN{
    p = (tp+fp)>0 ? tp/(tp+fp) : 1
    r = (tp+fn)>0 ? tp/(tp+fn) : 1
    printf "precision=%.2f recall=%.2f tp=%d fp=%d fn=%d\n", p, r, tp, fp, fn
  }'
}

# codex-verify <prompt-file>: cross-model second opinion via Codex (a DIFFERENT model
# than the one running the scan = different blind spots). Runs Codex NON-INTERACTIVELY
# and READ-ONLY — it may reason and read, but never write or run side-effecting
# commands, so a verification can never mutate the scanned repo (pattern P4). Prints
# Codex's final message. Used by --cross-model. Degrades cleanly (exit 3) when codex
# is absent or the call fails — cross-model is an enhancement, never a hard dependency.
# DEFECT_SCAN_CODEX overrides the binary (tests stay offline).
cmd_codex_verify() {
  [ $# -ge 1 ] || { echo "usage: detect.sh codex-verify <prompt-file>" >&2; return 2; }
  pf="$1"
  [ -f "$pf" ] || { echo "codex-verify: prompt file not found: $pf" >&2; return 2; }
  cx="${DEFECT_SCAN_CODEX:-codex}"
  command -v "$cx" >/dev/null 2>&1 || {
    echo "defect-scan: codex not available; skipping cross-model verification" >&2; return 3; }
  out="$(mktemp 2>/dev/null || echo "/tmp/ds-codex.$$")"
  if "$cx" exec --sandbox read-only --skip-git-repo-check -o "$out" - < "$pf" >/dev/null 2>&1; then
    cat "$out"; rm -f "$out"
  else
    rm -f "$out"
    echo "defect-scan: codex exec failed (cross-model verification skipped)" >&2; return 3
  fi
}

# preflight: verify the external tools detect.sh depends on are present, so users on
# an unsupported shell/platform get a clear, actionable message instead of a cryptic
# awk/git failure mid-scan. Core tools are required; jq/gh are optional (correlation
# + issue filing). Exits non-zero if any core tool is missing.
cmd_preflight() {
  core="git awk sed grep find sort head tr mktemp comm"
  missing=""
  for t in $core; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    echo "defect-scan preflight: MISSING core tools:$missing" >&2
    echo "  defect-scan needs a POSIX shell + coreutils. On Windows use WSL or Git-Bash" >&2
    echo "  (native PowerShell: run via windows/defect-scan.ps1, which delegates to Git-Bash)." >&2
    return 1
  fi
  for t in jq gh; do
    command -v "$t" >/dev/null 2>&1 || \
      echo "defect-scan preflight: optional '$t' not found — needed for issue correlation/filing" >&2
  done
  command -v codex >/dev/null 2>&1 || \
    echo "defect-scan preflight: optional 'codex' not found — needed for --cross-model verification" >&2
  echo "defect-scan preflight: OK — core tools present"
}

main() {
  sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    preflight)    cmd_preflight "$@" ;;
    eval)         cmd_eval "$@" ;;
    codex-verify) cmd_codex_verify "$@" ;;
    stacks)    cmd_stacks "$@" ;;
    tool)      cmd_tool "$@" ;;
    scope)     cmd_scope "$@" ;;
    triage)    cmd_triage "$@" ;;
    issues)              cmd_issues "$@" ;;
    issues-create)       cmd_issues_create "$@" ;;
    issues-ensure-label) cmd_issues_ensure_label "$@" ;;
    labels)              cmd_labels "$@" ;;
    profiles)  cmd_profiles "$@" ;;
    patterns)  cmd_patterns "$@" ;;
    __fmget)   fm_get "$@" ;;
    __fmfield) fm_field "$@" ;;
    *) echo "usage: detect.sh {preflight|eval|codex-verify|stacks|tool|scope|triage|issues|issues-create|issues-ensure-label|labels|profiles|patterns} ..." >&2; return 2 ;;
  esac
}
main "$@"

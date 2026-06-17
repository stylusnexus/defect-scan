#!/usr/bin/env sh
# detect.sh — deterministic plumbing for the defect-scan skill.
# Subcommands: stacks|tool|scope|triage|issues|profiles|patterns
set -eu

# Absolute path to this skill dir (the dir containing lib/). Works via symlink.
skill_dir() { CDPATH= cd -- "$(dirname -- "$0")/.." && pwd; }

# eval_corpus_root: where the labeled eval corpus lives. Defaults to the repo's
# tests/eval (resolved from this script's location), overridable for tests.
eval_corpus_root() {
  printf '%s\n' "${DEFECT_SCAN_EVAL_CORPUS:-$(skill_dir)/../../tests/eval}"
}

# extract_eval_block: read runner output on stdin; emit the validated findings of the
# single <<<EVAL ... EVAL>>> block to stdout (possibly empty). Exit 4 = PROTOCOL ERROR:
# zero blocks, more than one block, or any malformed line. The missing(=4) vs
# empty(=0, no output) distinction is load-bearing — a missing block on a clean fixture
# must NOT score as a perfect run.
extract_eval_block() {
  in="$(cat)"
  nstart=$(printf '%s\n' "$in" | grep -c '^<<<EVAL$' 2>/dev/null || true)
  nend=$(printf '%s\n' "$in" | grep -c '^EVAL>>>$' 2>/dev/null || true)
  [ "$nstart" = "1" ] && [ "$nend" = "1" ] || return 4
  body=$(printf '%s\n' "$in" | sed -n '/^<<<EVAL$/,/^EVAL>>>$/p' | sed '1d;$d')
  # every non-empty body line must be <path>:<line>:<category>
  bad=$(printf '%s\n' "$body" | grep -vE '^$|^[^:]+:[0-9]+:[^:]+$' | grep -c . 2>/dev/null || true)
  [ "$bad" = "0" ] || return 4
  # print non-empty lines only (empty block => no output)
  printf '%s\n' "$body" | grep -v '^$' || true
}

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
  for f in "$(skill_dir)/patterns"/*.md; do
    [ -f "$f" ] || continue
    case "$f" in */recurring.md) continue ;; esac   # already emitted first
    echo "$f"
  done
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
  # Match with ±N line tolerance, 1:1 within (basename, category) buckets.
  # N is a COMMITTED CONSTANT — do NOT make it a runtime/env knob (a tunable ruler
  # is a gameable ruler). Widen only via a CODEOWNERS-reviewed change here.
  # exp/act lines are "basename:line:category"; basenames/categories carry no ':'.
  result="$(
    { awk -F: '{print "E\t"$1"\t"$3"\t"$2}' "$exp"
      awk -F: '{print "A\t"$1"\t"$3"\t"$2}' "$act"; } \
    | awk -F'\t' '
      BEGIN { N=2 }   # line tolerance (committed constant)
      { key=$2 SUBSEP $3; keys[key]=1
        if ($1=="E") { ec[key]++; el[key,ec[key]]=$4+0 }
        else         { ac[key]++; al[key,ac[key]]=$4+0 } }
      END {
        tp=0; fp=0; fn=0
        for (k in keys) {
          ne=ec[k]+0; na=ac[k]+0
          for(i=2;i<=ne;i++){v=el[k,i];j=i-1;while(j>=1&&el[k,j]>v){el[k,j+1]=el[k,j];j--}el[k,j+1]=v}
          for(i=2;i<=na;i++){v=al[k,i];j=i-1;while(j>=1&&al[k,j]>v){al[k,j+1]=al[k,j];j--}al[k,j+1]=v}
          for(i=1;i<=ne;i++){
            best=0; bestd=N+1
            for(j=1;j<=na;j++){
              if(m[k,j]) continue
              d=al[k,j]-el[k,i]; if(d<0)d=-d
              if(d<=N && d<bestd){bestd=d; best=j}
            }
            if(best){m[k,best]=1; tp++} else fn++
          }
          for(j=1;j<=na;j++) if(!m[k,j]) fp++
        }
        printf "%d %d %d\n", tp, fp, fn
      }'
  )"
  rm -f "$exp" "$act"
  tp="${result%% *}"; rest="${result#* }"; fp="${rest%% *}"; fn="${rest##* }"
  awk -v tp="$tp" -v fp="$fp" -v fn="$fn" 'BEGIN{
    p = (tp+fp)>0 ? tp/(tp+fp) : 1
    r = (tp+fn)>0 ? tp/(tp+fn) : 1
    printf "precision=%.2f recall=%.2f tp=%d fp=%d fn=%d\n", p, r, tp, fp, fn
  }'
}

# eval-categories <lang>: the authoritative valid-label set for a language —
# baseline cat#1..5 UNION every label present in that language's corpus .expected
# files. Model-FREE (pure set union over existing artifacts). Used by eval-mode (tell
# the model which labels to emit) and eval-gaps (per-category coverage denominator).
cmd_eval_categories() {
  lang="${1:?usage: detect.sh eval-categories <lang>}"
  root="$(eval_corpus_root)"
  [ -d "$root/$lang" ] || { echo "eval-categories: no corpus for '$lang' under $root" >&2; return 2; }
  {
    printf 'cat#1\ncat#2\ncat#3\ncat#4\ncat#5\ncat#6\n'
    # labels are the part after "<line>:" in each non-empty, non-comment .expected line
    find "$root/$lang" -name '*.expected' -type f 2>/dev/null | while IFS= read -r f; do
      while IFS= read -r ln || [ -n "$ln" ]; do
        [ -n "$ln" ] || continue
        case "$ln" in \#*) continue ;; esac
        printf '%s\n' "${ln#*:}"
      done < "$f"
    done
  } | sort -u
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

# --- eval-run: model-FREE orchestrator over the swappable runner -------------

# _bv <file> <key>: read a key=value baseline value (empty if absent).
_bv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# eval_gate <baseline-file> <mean_precision> <mean_recall> <clean_fp_runs>
# Precision-first. Prints one verdict line; exit nonzero ONLY on FAIL.
eval_gate() {
  bf="$1"; mp="$2"; mr="$3"; cfp="$4"
  pf="$(_bv "$bf" precision_floor)"; rf="$(_bv "$bf" recall_floor)"
  pb="$(_bv "$bf" precision_baseline)"; nb="$(_bv "$bf" noise_band)"
  [ -n "$pf" ] || pf=0; [ -n "$rf" ] || rf=0; [ -n "$pb" ] || pb=0; [ -n "$nb" ] || nb=0
  if awk -v p="$mp" -v f="$pf" -v b="$pb" -v n="$nb" 'BEGIN{exit !(p<f || p<(b-n))}'; then
    echo "eval-gate: FAIL — mean_precision=$mp (floor=$pf, baseline=$pb, noise_band=$nb)"
    return 1
  fi
  rc_msg="PASS"
  if [ "${cfp:-0}" -gt 0 ] 2>/dev/null; then rc_msg="FLAG (clean-fixture FP in $cfp run(s))"; fi
  if awk -v r="$mr" -v f="$rf" 'BEGIN{exit !(r<f)}'; then
    rc_msg="$rc_msg; WARN (mean_recall=$mr < floor=$rf)"
  fi
  echo "eval-gate: $rc_msg — mean_precision=$mp mean_recall=$mr"
  return 0
}

# eval_update_baseline <baseline-file> <mean_precision> <mean_recall>
# Writes/refreshes the recorded baseline means, PRESERVING existing floors/bands.
eval_update_baseline() {
  bf="$1"; mp="$2"; mr="$3"
  pf="$(_bv "$bf" precision_floor)"; rf="$(_bv "$bf" recall_floor)"
  nb="$(_bv "$bf" noise_band)"; ob="$(_bv "$bf" overfit_band)"
  [ -n "$pf" ] || pf=0.90; [ -n "$rf" ] || rf=0.70; [ -n "$nb" ] || nb=0.05; [ -n "$ob" ] || ob=0.10
  printf 'precision_floor=%s\nrecall_floor=%s\nprecision_baseline=%s\nrecall_baseline=%s\nnoise_band=%s\noverfit_band=%s\n' \
    "$pf" "$rf" "$mp" "$mr" "$nb" "$ob" > "$bf"
}

# eval-run <lang> [--runs N] [--split seen|held-out|all] [--update-baseline]
# Model-FREE orchestrator. Per split: N runs, each run scans every SOURCE fixture via
# the swappable $DEFECT_SCAN_EVAL_RUNNER (per-fixture), accumulates findings into one
# file, and scores the whole split ONCE with cmd_eval. Aggregates mean/stddev and the
# clean-fixture FP rate, writes the .last-run artifact, then gates (Phase 4).
cmd_eval_run() {
  lang=""; runs=5; split="seen"; update=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --runs) runs="${2:?}"; shift 2 ;;
      --split) split="${2:?}"; shift 2 ;;
      --update-baseline) update=1; shift ;;
      -*) echo "eval-run: unknown flag $1" >&2; return 2 ;;
      *) [ -z "$lang" ] && lang="$1" || { echo "eval-run: unexpected arg $1" >&2; return 2; }; shift ;;
    esac
  done
  [ -n "$lang" ] || { echo "usage: detect.sh eval-run <lang> [--runs N] [--split seen|held-out|all]" >&2; return 2; }
  runner="${DEFECT_SCAN_EVAL_RUNNER:-}"
  [ -n "$runner" ] || { echo "eval-run: set DEFECT_SCAN_EVAL_RUNNER to a runner script (tests/eval/runners/*.sh)" >&2; return 3; }
  root="$(eval_corpus_root)"
  case "$split" in all) splits="seen held-out" ;; *) splits="$split" ;; esac

  overall_rc=0
  for sp in $splits; do
    dir="$root/$lang/$sp"
    if [ ! -d "$dir" ]; then
      [ "$split" = all ] && { echo "eval-run: $lang/$sp absent — skipping"; continue; }
      echo "eval-run: corpus split not found: $dir" >&2; return 2
    fi
    pvals=""; rvals=""; clean_fp_runs=0; partial=0
    last_findings=""
    r=1
    while [ "$r" -le "$runs" ]; do
      findings="$(mktemp 2>/dev/null || echo "/tmp/ds-er-$$.$r")"
      for src in "$dir"/*; do
        case "$src" in *.expected) continue ;; esac
        [ -f "$src" ] || continue
        out="$("$runner" "$src" "$lang" 2>/dev/null)" || { partial=1; continue; }
        block="$(printf '%s' "$out" | extract_eval_block)" || { partial=1; continue; }
        [ -n "$block" ] && printf '%s\n' "$block" >> "$findings"
      done
      m="$(cmd_eval "$dir" "$findings")"
      p="$(printf '%s\n' "$m" | sed -n 's/.*precision=\([0-9.]*\).*/\1/p')"
      rr="$(printf '%s\n' "$m" | sed -n 's/.*recall=\([0-9.]*\).*/\1/p')"
      pvals="$pvals $p"; rvals="$rvals $rr"
      if eval_clean_fp "$dir" "$findings"; then clean_fp_runs=$((clean_fp_runs+1)); fi
      last_findings="$(cat "$findings")"
      rm -f "$findings"
      r=$((r+1))
    done

    mp="$(_eval_mean $pvals)"; sp_p="$(_eval_stddev $pvals)"
    mr="$(_eval_mean $rvals)"; sp_r="$(_eval_stddev $rvals)"

    art="$root/$lang/.last-run.$sp.txt"
    {
      printf 'runs=%s\nmean_precision=%s\nstddev_precision=%s\nmean_recall=%s\nstddev_recall=%s\nclean_fp_runs=%s\n' \
        "$runs" "$mp" "$sp_p" "$mr" "$sp_r" "$clean_fp_runs"
      printf '@findings\n%s\n' "$last_findings"
    } > "$art"

    echo "eval-run $lang/$sp: runs=$runs mean_precision=$mp(±$sp_p) mean_recall=$mr(±$sp_r) clean_fp_runs=$clean_fp_runs"
    [ "$partial" = 1 ] && echo "eval-run $lang/$sp: PARTIAL — at least one fixture run was inconclusive (missing/invalid block)"

    if [ "$update" = 1 ]; then
      if [ "$partial" = 1 ]; then
        echo "eval-run $lang/$sp: PARTIAL — refusing to update baseline from an inconclusive run" >&2
        overall_rc=1
      else
        eval_update_baseline "$root/$lang/baseline.$sp.txt" "$mp" "$mr"
        echo "eval-run $lang/$sp: baseline updated (commit via CODEOWNERS PR)"
      fi
    else
      eval_gate "$root/$lang/baseline.$sp.txt" "$mp" "$mr" "$clean_fp_runs" || overall_rc=1
      if [ "$partial" = 1 ]; then
        echo "eval-run $lang/$sp: PARTIAL run is not a pass — failing (investigate runner/model setup)"
        overall_rc=1
      fi
    fi
  done

  if [ "$split" = all ]; then
    sa="$root/$lang/.last-run.seen.txt"; ha="$root/$lang/.last-run.held-out.txt"
    if [ -f "$sa" ] && [ -f "$ha" ]; then
      smp="$(_bv "$sa" mean_precision)"; hmp="$(_bv "$ha" mean_precision)"
      smr="$(_bv "$sa" mean_recall)";    hmr="$(_bv "$ha" mean_recall)"
      ob="$(_bv "$root/$lang/baseline.seen.txt" overfit_band)"; [ -n "$ob" ] || ob=0.15
      # Overfit shows as a seen-vs-held-out gap in EITHER metric: a profile memorized to
      # the seen set drops held-out RECALL; one tuned to avoid seen FPs drops held-out
      # PRECISION. (Precision alone misses the recall case — zero held-out findings score
      # a vacuous precision=1.00.)
      if awk -v sp="$smp" -v hp="$hmp" -v sr="$smr" -v hr="$hmr" -v o="$ob" \
           'BEGIN{exit !((sp-hp)>o || (sr-hr)>o)}'; then
        echo "eval-run $lang: FLAG overfit — seen P=$smp R=$smr vs held-out P=$hmp R=$hmr (gap > overfit_band $ob)"
      fi
    fi
  fi
  return "$overall_rc"
}

# _eval_gaps_expected <dir>: emit one category label per expected defect across all
# non-empty .expected files in <dir> (the part after "<line>:"). Skips comment/blank
# lines. Kept a separate function so its `case` is not nested in a command
# substitution (older bash mis-parses `case` inside `$(...)`).
_eval_gaps_expected() {
  for e in "$1"/*.expected; do
    [ -s "$e" ] || continue
    while IFS= read -r ln || [ -n "$ln" ]; do
      [ -n "$ln" ] || continue
      case "$ln" in \#*) continue ;; esac
      printf '%s\n' "${ln#*:}"
    done < "$e"
  done
}

# eval-gaps <lang> [--split seen|held-out]: model-FREE completeness critic (report
# half). Reads the .last-run artifact (last run's findings + recall) and reports, per
# category in the registry, how many defects the corpus EXPECTS vs how many the last
# run DETECTED. Surfaces zero-coverage and weak categories. No writes; no model.
cmd_eval_gaps() {
  lang=""; split="seen"
  while [ $# -gt 0 ]; do
    case "$1" in
      --split) split="${2:?}"; shift 2 ;;
      -*) echo "eval-gaps: unknown flag $1" >&2; return 2 ;;
      *) lang="$1"; shift ;;
    esac
  done
  [ -n "$lang" ] || { echo "usage: detect.sh eval-gaps <lang> [--split seen|held-out]" >&2; return 2; }
  root="$(eval_corpus_root)"; dir="$root/$lang/$split"
  art="$root/$lang/.last-run.$split.txt"
  [ -d "$dir" ] || { echo "eval-gaps: no corpus split: $dir" >&2; return 2; }
  [ -f "$art" ] || { echo "eval-gaps: no run artifact ($art) — run 'eval-run $lang --split $split' first" >&2; return 2; }

  exp_counts="$(_eval_gaps_expected "$dir" | sort | uniq -c)"
  det="$(sed -n '/^@findings$/,$p' "$art" | sed '1d')"

  echo "eval-gaps $lang/$split:"
  printf '%s\n' "$exp_counts" | while read -r cnt cat; do
    [ -n "$cat" ] || continue
    found="$(printf '%s\n' "$det" | awk -F: -v c="$cat" '$NF==c{n++} END{print n+0}')"
    if [ "${found:-0}" -eq 0 ]; then
      echo "  GAP: $cat — $cnt expected, 0 detected"
    elif [ "$found" -lt "$cnt" ]; then
      echo "  weak: $cat — $cnt expected, $found detected"
    else
      echo "  ok:   $cat — $cnt expected, $found detected"
    fi
  done
  cmd_eval_categories "$lang" | while IFS= read -r cat; do
    # Exact (literal) compare on the category field — `uniq -c` lines are
    # "<count> <category>", so $NF is the label. A regex grep here would let a
    # metachar label (e.g. "a.c") spuriously match a sibling ("axc") and suppress
    # a real "uncovered" report; match exactly, as the detected side does.
    printf '%s\n' "$exp_counts" | awk -v c="$cat" '$NF==c{f=1} END{exit !f}' \
      || echo "  uncovered: $cat — no corpus fixtures"
  done
}

# eval_clean_fp <dir> <findings>: exit 0 if any CLEAN fixture (empty .expected) appears
# in the findings file (an FP), else exit 1.
eval_clean_fp() {
  d="$1"; f="$2"
  for exp in "$d"/*.expected; do
    [ -f "$exp" ] || continue
    [ -s "$exp" ] && continue
    base="$(basename "$exp" .expected)"
    if awk -F: -v b="$base" '{p=$1; sub(/.*\//,"",p); if(p==b){found=1}} END{exit !found}' "$f"; then
      return 0
    fi
  done
  return 1
}

# _eval_mean / _eval_stddev: arithmetic mean and POPULATION stddev of space-separated
# decimals, printed to 2 dp. Empty input -> 0.00.
_eval_mean() { awk 'BEGIN{n=0;s=0; for(i=1;i<=ARGC-1;i++){s+=ARGV[i];n++}; printf "%.2f", n? s/n:0}' "$@"; }
_eval_stddev() {
  awk 'BEGIN{n=0;s=0; for(i=1;i<=ARGC-1;i++){a[++n]=ARGV[i];s+=ARGV[i]}
       if(!n){printf "0.00"; exit} m=s/n; v=0; for(i=1;i<=n;i++)v+=(a[i]-m)*(a[i]-m);
       printf "%.2f", sqrt(v/n)}' "$@"
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

# supply-chain-config <repo>: emit the resolved internal-scope/registry allowlist,
# user-layer then project-layer (project wins by appearing later; consumers dedup).
# Unknown keys warned to stderr and skipped. Read-only. Absent/malformed never abort.
cmd_supply_chain_config() {
  repo="${1:-$PWD}"
  for cf in "$HOME/.config/defect-scan/supply-chain.conf" "$repo/.defect-scan/supply-chain.conf"; do
    case "$cf" in
      "$HOME/.config/"*)
        if [ -n "${DEFECT_SCAN_NO_USER:-}" ]; then continue; fi ;;
    esac
    case "$cf" in
      "$repo/.defect-scan/"*)
        if [ -n "${DEFECT_SCAN_NO_PROJECT:-}" ]; then continue; fi ;;
    esac
    [ -f "$cf" ] || continue
    while IFS= read -r ln || [ -n "$ln" ]; do
      case "$ln" in ''|\#*) continue ;; esac
      case "$ln" in
        internal_scope=*|internal_registry=*) printf '%s\n' "$ln" ;;
        *) printf 'supply-chain-config: ignoring unknown directive: %s\n' "$ln" >&2 ;;
      esac
    done < "$cf"
  done
  return 0
}

# manifest <repo>: deterministic, READ-ONLY supply-chain surface for the reasoning pass.
# Emits sliced sections (LIFECYCLE / DEPENDENCIES / LOCKFILE / NPMRC / SCRIPT:<path>) when
# an npm ecosystem is present. Never executes anything. jq-preferred; awk fallback.
cmd_manifest() {
  repo="${1:-$PWD}"
  pj="$repo/package.json"
  [ -f "$pj" ] || return 0                      # not an npm repo → clean no-op
  jqbin="$(command -v jq 2>/dev/null || true)"
  [ -n "${DEFECT_SCAN_NO_JQ:-}" ] && jqbin=""   # test/CI hook: force the awk fallback

  echo "=== LIFECYCLE ==="
  if [ -n "$jqbin" ]; then
    "$jqbin" -r '.scripts // {} | to_entries[]
      | select(.key|test("^(pre|post)?install$|^prepare$|^prepublishOnly$"))
      | "\(.key): \(.value)"' "$pj" 2>/dev/null || echo "(manifest: package.json unparseable — INCONCLUSIVE)"
  else
    # Print "<name>: <command>" with quotes stripped, mirroring the jq path. The
    # grep isolates each whole "key": "value" lifecycle pair (compact or multi-line
    # JSON keeps a pair on one physical line), then sed peels the quoting.
    grep -oE '"(pre|post)?install"[[:space:]]*:[[:space:]]*"[^"]*"|"prepare"[[:space:]]*:[[:space:]]*"[^"]*"|"prepublishOnly"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" \
      | sed -E 's/^"([^"]*)"[[:space:]]*:[[:space:]]*"(.*)"$/\1: \2/' \
      || echo "(manifest: no jq and no lifecycle scripts matched — INCONCLUSIVE if scripts present)"
  fi

  echo "=== DEPENDENCIES ==="
  if [ -n "$jqbin" ]; then
    "$jqbin" -r '[(.dependencies//{}),(.devDependencies//{}),(.optionalDependencies//{})]
      | add // {} | keys[]' "$pj" 2>/dev/null
  else
    _manifest_dep_names_awk "$pj"
  fi

  for lf in package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml; do
    [ -f "$repo/$lf" ] || continue
    echo "=== LOCKFILE $lf ==="
    grep -nE '"?(resolved|integrity)"?[[:space:]]*[:=]' "$repo/$lf" | head -200
  done

  if [ -f "$repo/.npmrc" ]; then
    echo "=== NPMRC ==="
    grep -E '(^|@[^:]+:)registry[[:space:]]*=' "$repo/.npmrc" || true
  fi

  _manifest_resolve_scripts "$repo" "$pj" "$jqbin"
  return 0
}

# _manifest_dep_names_awk <package.json>: no-jq fallback that prints every
# dependency name across dependencies/devDependencies/optionalDependencies, for BOTH
# compact (single-line) and multi-line layouts. JSON is not line-oriented, so it
# slurps the whole file into one buffer and does a brace-depth-aware scan: for each
# of the three keys it finds the matching `{`, walks to the depth-0 close, and emits
# the quoted object keys at depth 1 (those immediately followed by `:`). This avoids
# pulling in script names (different object) or version-string values (they are not
# followed by `:` at depth 1). POSIX awk; BSD+GNU safe (no gensub, no length-of-array
# reliance, no getline tricks).
_manifest_dep_names_awk() {
  awk '
    { buf = buf $0 "\n" }      # slurp: JSON spans lines; brace matching needs the whole doc
    END {
      n = split("dependencies devDependencies optionalDependencies", keys, " ")
      for (k = 1; k <= n; k++) emit(buf, keys[k])
    }
    function emit(s, key,   m, i, c, depth, started, instr, esc, name, collecting, ch) {
      # locate the "<key>" token, then its opening brace
      m = index(s, "\"" key "\"")
      if (m == 0) return
      i = m + length(key) + 2          # just past the closing quote of the key
      # skip to the first { (the value object)
      while (i <= length(s) && substr(s, i, 1) != "{") i++
      if (i > length(s)) return
      depth = 0; instr = 0; esc = 0; name = ""; collecting = 0
      for (; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (instr) {
          if (esc) { esc = 0; if (collecting) name = name ch; continue }
          if (ch == "\\") { esc = 1; if (collecting) name = name ch; continue }
          if (ch == "\"") { instr = 0; continue }
          if (collecting) name = name ch
          continue
        }
        if (ch == "\"") {
          # start of a string. At depth 1 it may be an object key (name) — capture it
          # provisionally; we only print it if a ":" follows at depth 1.
          instr = 1
          if (depth == 1) { collecting = 1; name = "" } else collecting = 0
          continue
        }
        if (ch == "{") { depth++; continue }
        if (ch == "}") { depth--; if (depth == 0) return; continue }
        if (ch == ":" && depth == 1 && name != "") { print name; name = ""; collecting = 0; continue }
        if (ch == "," && depth == 1) { name = ""; collecting = 0 }
      }
    }
  ' "$1"
}

# Resolve ONE level of repo-local script references in lifecycle commands. Read-only,
# size-capped, no recursion, no node_modules, no traversal outside the repo.
_MANIFEST_SCRIPT_MAXLINES=200
_manifest_resolve_scripts() {
  _repo="$1"; _pj="$2"; _jq="$3"
  if [ -n "$_jq" ]; then
    _cmds="$("$_jq" -r '.scripts // {} | to_entries[]
      | select(.key|test("^(pre|post)?install$|^prepare$|^prepublishOnly$")) | .value' "$_pj" 2>/dev/null)"
  else
    _cmds="$(grep -oE '"[^"]*"' "$_pj")"
  fi
  printf '%s\n' "$_cmds" | tr ' \t' '\n\n' | while IFS= read -r tok; do
    tok="${tok#\"}"; tok="${tok%\"}"          # strip surrounding quotes (fallback path emits them)
    case "$tok" in
      /*|*..*|*node_modules/*) continue ;;                 # abs / traversal / vendored → refuse
      *.js|*.cjs|*.mjs|*.sh|./*) : ;;                       # plausible local script
      *) continue ;;
    esac
    rel="${tok#./}"
    f="$_repo/$rel"
    [ -f "$f" ] || continue
    echo "=== SCRIPT: $rel ==="
    head -n "$_MANIFEST_SCRIPT_MAXLINES" "$f"
    _n="$(wc -l < "$f" 2>/dev/null | tr -d ' ')"
    [ "${_n:-0}" -gt "$_MANIFEST_SCRIPT_MAXLINES" ] && echo "(manifest: SCRIPT truncated at $_MANIFEST_SCRIPT_MAXLINES lines)"
  done
}

main() {
  sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    preflight)    cmd_preflight "$@" ;;
    eval)         cmd_eval "$@" ;;
    eval-categories) cmd_eval_categories "$@" ;;
    eval-run)     cmd_eval_run "$@" ;;
    eval-gaps)    cmd_eval_gaps "$@" ;;
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
    manifest)  cmd_manifest "$@" ;;
    supply-chain-config) cmd_supply_chain_config "$@" ;;
    __fmget)   fm_get "$@" ;;
    __fmfield) fm_field "$@" ;;
    __evalblock) extract_eval_block ;;
    __evalgate)   eval_gate "$@" ;;
    __evalupdate) eval_update_baseline "$@" ;;
    *) echo "usage: detect.sh {preflight|eval|eval-categories|eval-run|eval-gaps|codex-verify|stacks|tool|scope|triage|manifest|supply-chain-config|issues|issues-create|issues-ensure-label|labels|profiles|patterns} ..." >&2; return 2 ;;
  esac
}

main "$@"

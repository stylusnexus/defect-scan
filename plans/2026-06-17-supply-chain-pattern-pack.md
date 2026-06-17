# Supply-Chain Pattern Pack (npm-first) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `cat#6` supply-chain/dependency-integrity category, a deterministic `detect.sh manifest` hook (with a bounded local-script resolver), a `patterns/supply-chain.md` pack (P11–P14), a backward-compatible multi-file eval corpus, both-harness wiring, and docs — so defect-scan flags novel npm supply-chain attacks that `npm audit`/`osv-scanner` miss.

**Architecture:** Same deterministic/reasoning split as the rest of the tool — `detect.sh` (POSIX `sh`, `set -eu`) mechanically locates + slices `package.json`/lockfile/`.npmrc` and resolves referenced local scripts; the model reasons over the slices using the pattern pack. The eval harness gains additive directory-fixture support so a fixture can be a mini-repo. Offline; never executes manifest/script content.

**Tech Stack:** POSIX `sh`, `awk`/`grep`/`sed`, optional `jq`, `bats` (CI on ubuntu + macos).

**Spec:** `specs/2026-06-17-supply-chain-pattern-pack-design.md` · **Branch:** `feat/66-supply-chain-pattern-pack` (spec already committed there).

---

## Plain-English version (for non-engineers)

npm packages can run code the instant you install them, and that's how a lot of attacks land. The standard checkers only know about bad packages that have *already been reported*, so a brand-new malicious one slips through. We're teaching defect-scan to read a project's own dependency files and spot the *shape* of these attacks — a suspicious install script, a package name that's a typo of a popular one, a lockfile entry pointing somewhere it shouldn't. The shell layer reliably pulls out the relevant bits; the model judges whether they look malicious. We add a new "supply-chain" defect category (security standards treat this as its own thing), prove it works with a labeled set of test projects, and update both the Claude and Codex versions plus all the docs. We build it in eight checkpoints, each one tested before moving on, so nothing half-finished piles up.

---

## File structure

**New files**
- `skills/scan/patterns/supply-chain.md` — the P11–P14 pattern pack (model-facing prose).
- `tests/eval/supply-chain/seen/<case>/…` — multi-file fixture repos + sibling `<case>.expected`.
- `tests/eval/supply-chain/baseline.seen.txt` — calibrated baseline (CODEOWNERS PR).

**Modified — `skills/scan/lib/detect.sh`** (one file, several focused functions)
- `cmd_eval_categories` — emit `cat#6`.
- `cmd_patterns` — glob built-in `patterns/*.md` (recurring.md first).
- `cmd_manifest` (new) + `_resolve_local_script` (new helper) — the hook + resolver.
- `cmd_supply_chain_config` (new) — the allowlist reader.
- `cmd_eval` (grader) — case-relative path keying for directory fixtures.
- `cmd_eval_run` — directory fixtures + `--as <profile>`.
- `main` dispatch + usage string — register `manifest`.

**Modified — knowledge/driver/doc files**
- `skills/scan/baseline-categories.md`, `skills/scan/SKILL.md`, `codex/defect-scan.md`, `AGENTS.md`, `skills/scan/report-format.md`.
- `tests/eval/runners/{claude,codex}.sh`, `.github/workflows/eval-run.yml`.
- `tests/detect.bats`.
- `README.md`, `tests/eval/README.md`, `commands/help.md`, `EXTENDING.md`, `CONTRIBUTING.md`, `CLAUDE.md`.

**Dependency order:** Phase 1 → 2 → 3 → 4 are independent-ish and can land in any order; **Phase 5 (harness) must land before Phase 7 (corpus)**; Phase 6 (drivers) needs Phases 2+4; Phase 8 (docs) last.

---

## Phase 1 — `cat#6` category

### Task 1.1: Add `cat#6` to the category registry + enum

**Files:**
- Modify: `skills/scan/baseline-categories.md` (after the `## 5.` section, before "Each finding cites…")
- Modify: `skills/scan/lib/detect.sh:414` (`cmd_eval_categories` printf)
- Test: `tests/detect.bats`

- [ ] **Step 1: Write the failing test** (plain English: *`eval-categories` on any corpus lists `cat#6`; and `baseline-categories.md` defines a 6th section*)

```bash
@test "eval-categories includes cat#6 (supply-chain)" {
  run "$DETECT" eval-categories python
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat#6"* ]]
}

@test "baseline-categories.md defines cat#6 supply-chain (High)" {
  f="$BATS_TEST_DIRNAME/../skills/scan/baseline-categories.md"
  grep -qi "^## 6\. Supply-chain" "$f"
  grep -qi "default severity: High" "$f"
}
```

- [ ] **Step 2: Run to verify fail**

Run: `bats tests/detect.bats -f "cat#6"`
Expected: FAIL (`cat#6` absent from output / `## 6.` not found).

- [ ] **Step 3: Add the category section** — append to `baseline-categories.md` after the `## 5.` block:

```markdown
## 6. Supply-chain / dependency integrity  · default severity: High
Malicious or untrustworthy dependencies and the manifest surface that admits them:
malicious lifecycle scripts (`pre/postinstall`/`prepare`) and the local scripts they
invoke, install-time credential/env exfiltration, typosquatted package names,
dependency-confusion (internal-looking names resolving to the public registry), and
lockfile tampering (resolved host ≠ registry, missing/malformed integrity). Covers both
**A06** known-vulnerable/outdated components (found by `npm audit`/`osv-scanner`) and
**A08** integrity failures (found by reasoning over the manifest). This is an
integrity/provenance class (OWASP A06/A08, CWE-1357/829, SLSA, MITRE T1195) — *not* an
injection variant: the trust boundary is violated, not an interpreter.
```

- [ ] **Step 4: Update the enum** — `detect.sh:414`, change:

```sh
    printf 'cat#1\ncat#2\ncat#3\ncat#4\ncat#5\n'
```
to:
```sh
    printf 'cat#1\ncat#2\ncat#3\ncat#4\ncat#5\ncat#6\n'
```

- [ ] **Step 5: Run to verify pass**

Run: `bats tests/detect.bats -f "cat#6"`
Expected: PASS (both).

- [ ] **Step 6: Confirm the runner legend auto-includes cat#6** (no code change; guard test)

```bash
@test "runner legend picks up cat#6 from baseline-categories headers" {
  f="$BATS_TEST_DIRNAME/../skills/scan/baseline-categories.md"
  legend="$(awk '/^## [0-9]+\./ { n=$2; sub(/\./,"",n); t=$0; sub(/^## [0-9]+\. /,"",t); sub(/  .*/,"",t); printf "cat#%s=%s;", n, t }' "$f")"
  [[ "$legend" == *"cat#6=Supply-chain"* ]]
}
```
Run: `bats tests/detect.bats -f "legend picks up cat#6"` → PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/scan/baseline-categories.md skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(scan): add cat#6 supply-chain/dependency-integrity category"
```

---

## Phase 2 — `detect.sh manifest` hook + bounded local-script resolver

### Task 2.1: Register the `manifest` subcommand (usage + dispatch)

**Files:** Modify `skills/scan/lib/detect.sh` (dispatch ~709, usage ~715) · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: `detect.sh` usage lists `manifest`; an unknown subcommand still errors*)

```bash
@test "detect.sh usage lists the manifest subcommand" {
  run "$DETECT" bogus
  [[ "$output" == *"manifest"* ]]
}
```
- [ ] **Step 2: Run → FAIL.** `bats tests/detect.bats -f "lists the manifest"`
- [ ] **Step 3: Add dispatch case** after the `patterns)` line (~709):
```sh
    manifest)  cmd_manifest "$@" ;;
```
- [ ] **Step 4: Add `manifest` to the usage string** (~715) — insert `|manifest` after `patterns`:
```sh
    *) echo "usage: detect.sh {preflight|eval|eval-categories|eval-run|eval-gaps|codex-verify|stacks|tool|scope|triage|manifest|issues|issues-create|issues-ensure-label|labels|profiles|patterns} ..." >&2; return 2 ;;
```
- [ ] **Step 5: Run → PASS** (`cmd_manifest` defined in Task 2.2; until then this test passes on the usage string alone — keep this commit with Task 2.2).

### Task 2.2: `cmd_manifest` — locate + slice

**Files:** Modify `skills/scan/lib/detect.sh` (new function before `main`) · Test `tests/detect.bats` + a fixture

- [ ] **Step 1: Failing test** (*plain English: given a repo with a package.json that has a postinstall and two deps, `manifest` prints a LIFECYCLE section containing the postinstall command and a DEPENDENCIES section listing both names; a repo with no package.json prints nothing and exits 0*)

```bash
@test "manifest: surfaces lifecycle scripts and dependency names" {
  repo="$BATS_TEST_TMPDIR/npm1"; mkdir -p "$repo"
  cat > "$repo/package.json" <<'JSON'
{ "name": "x", "scripts": { "postinstall": "node scripts/setup.js" },
  "dependencies": { "left-pad": "1.0.0" }, "devDependencies": { "typescript": "5.0.0" } }
JSON
  run "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIFECYCLE"* ]]
  [[ "$output" == *"postinstall"* ]]
  [[ "$output" == *"node scripts/setup.js"* ]]
  [[ "$output" == *"DEPENDENCIES"* ]]
  [[ "$output" == *"left-pad"* ]]
  [[ "$output" == *"typescript"* ]]
}

@test "manifest: no package.json is a clean no-op (exit 0, no output)" {
  repo="$BATS_TEST_TMPDIR/empty"; mkdir -p "$repo"
  run "$DETECT" manifest "$repo"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```
- [ ] **Step 2: Run → FAIL** (`cmd_manifest` undefined).
- [ ] **Step 3: Implement `cmd_manifest`** (jq-preferred, awk fallback). Insert before `main()`:

```sh
# manifest <repo>: deterministic, READ-ONLY supply-chain surface for the reasoning pass.
# Emits sliced sections (LIFECYCLE / DEPENDENCIES / LOCKFILE / NPMRC / SCRIPT:<path>) when
# an npm ecosystem is present. Never executes anything. jq-preferred; awk fallback.
cmd_manifest() {
  repo="${1:-$PWD}"
  pj="$repo/package.json"
  [ -f "$pj" ] || return 0                      # not an npm repo → clean no-op
  jqbin="$(command -v jq 2>/dev/null || true)"

  echo "=== LIFECYCLE ==="
  if [ -n "$jqbin" ]; then
    "$jqbin" -r '.scripts // {} | to_entries[]
      | select(.key|test("^(pre|post)?install$|^prepare$|^prepublishOnly$"))
      | "\(.key): \(.value)"' "$pj" 2>/dev/null || echo "(manifest: package.json unparseable — INCONCLUSIVE)"
  else
    # fallback: grep the known lifecycle keys out of the scripts block
    grep -oE '"(pre|post)?install"[[:space:]]*:[[:space:]]*"[^"]*"|"prepare"[[:space:]]*:[[:space:]]*"[^"]*"|"prepublishOnly"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" \
      || echo "(manifest: no jq and no lifecycle scripts matched — INCONCLUSIVE if scripts present)"
  fi

  echo "=== DEPENDENCIES ==="
  if [ -n "$jqbin" ]; then
    "$jqbin" -r '[(.dependencies//{}),(.devDependencies//{}),(.optionalDependencies//{})]
      | add // {} | keys[]' "$pj" 2>/dev/null
  else
    awk '/"(dev|optional)?[Dd]ependencies"[[:space:]]*:/{f=1;next} f&&/}/{f=0} f&&/"/{gsub(/[",:].*/,"");gsub(/^[[:space:]]+/,"");if($0)print}' "$pj"
  fi

  # lockfile slice (resolved + integrity) — relevant subset, never the whole file
  for lf in package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml; do
    [ -f "$repo/$lf" ] || continue
    echo "=== LOCKFILE $lf ==="
    grep -nE '"?(resolved|integrity)"?[[:space:]]*[:=]' "$repo/$lf" | head -200
  done

  # registry config
  if [ -f "$repo/.npmrc" ]; then
    echo "=== NPMRC ==="
    grep -E '(^|@[^:]+:)registry[[:space:]]*=' "$repo/.npmrc" || true
  fi

  # resolved local scripts referenced by lifecycle commands (Task 2.3)
  _manifest_resolve_scripts "$repo" "$pj" "$jqbin"
  return 0
}
```
- [ ] **Step 4: Stub `_manifest_resolve_scripts`** (real body in Task 2.3) so the file parses:
```sh
_manifest_resolve_scripts() { : ; }   # replaced in Task 2.3
```
- [ ] **Step 5: Run → PASS.** `bats tests/detect.bats -f "manifest:"`
- [ ] **Step 6: `sh -n` gate.** Run: `sh -n skills/scan/lib/detect.sh` → no output.
- [ ] **Step 7: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(scan): detect.sh manifest hook — slice package.json/lockfile/.npmrc"
```

### Task 2.3: Bounded local-script resolver

**Files:** Modify `skills/scan/lib/detect.sh` (replace the `_manifest_resolve_scripts` stub) · Test `tests/detect.bats`

- [ ] **Step 1: Failing tests** (*plain English: a postinstall `node scripts/setup.js` surfaces a `SCRIPT: scripts/setup.js` section containing the file's contents; an absolute path, a `../` traversal, and a `node_modules/...` path are REFUSED (no SCRIPT section); a file larger than the cap is truncated with a marker*)

```bash
@test "manifest: resolves a referenced repo-local install script" {
  repo="$BATS_TEST_TMPDIR/npm2"; mkdir -p "$repo/scripts"
  printf '{ "scripts": { "postinstall": "node scripts/setup.js" } }\n' > "$repo/package.json"
  printf 'require("https").get(process.env.NPM_TOKEN)\n' > "$repo/scripts/setup.js"
  run "$DETECT" manifest "$repo"
  [[ "$output" == *"SCRIPT: scripts/setup.js"* ]]
  [[ "$output" == *"process.env.NPM_TOKEN"* ]]
}

@test "manifest: refuses unsafe script references (abs / traversal / node_modules)" {
  repo="$BATS_TEST_TMPDIR/npm3"; mkdir -p "$repo"
  printf '{ "scripts": { "postinstall": "node /etc/evil.js && node ../x.js && node node_modules/y.js" } }\n' > "$repo/package.json"
  run "$DETECT" manifest "$repo"
  [[ "$output" != *"SCRIPT: /etc/evil.js"* ]]
  [[ "$output" != *"SCRIPT: ../x.js"* ]]
  [[ "$output" != *"node_modules"* ]]
}
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — replace the stub:
```sh
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
  # tokenize on whitespace; a token that looks like a relative path to a script file = candidate
  printf '%s\n' "$_cmds" | tr ' \t' '\n\n' | while IFS= read -r tok; do
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
```
- [ ] **Step 4: Run → PASS.** `bats tests/detect.bats -f "referenced repo-local\|refuses unsafe"`
- [ ] **Step 5: `sh -n` gate** → clean.
- [ ] **Step 6: Commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(scan): bounded read-only local-script resolver in manifest hook"
```

---

## Phase 3 — `supply-chain.conf` allowlist reader

### Task 3.1: `cmd_supply_chain_config` — layered allowlist

**Files:** Modify `skills/scan/lib/detect.sh` (new function + dispatch + usage) · Test `tests/detect.bats`

- [ ] **Step 1: Failing tests** (*plain English: with a project `.defect-scan/supply-chain.conf` declaring `internal_scope=@acme`, the reader prints `internal_scope=@acme`; a user-layer file is used when no project file exists; absent files print nothing (exit 0); a malformed line warns on stderr but the scan-usable output still lists the valid directives*)

```bash
@test "supply-chain-config: reads project-layer internal scopes" {
  repo="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$repo/.defect-scan"
  printf '# ours\ninternal_scope=@acme\ninternal_registry=https://npm.acme.internal\n' > "$repo/.defect-scan/supply-chain.conf"
  run "$DETECT" supply-chain-config "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"internal_scope=@acme"* ]]
  [[ "$output" == *"internal_registry=https://npm.acme.internal"* ]]
}

@test "supply-chain-config: absent files are a clean no-op" {
  repo="$BATS_TEST_TMPDIR/nocfg"; mkdir -p "$repo"
  run "$DETECT" supply-chain-config "$repo"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** (mirror the `DEFECT_SCAN_NO_USER/NO_PROJECT` layering from `cmd_patterns`):
```sh
# supply-chain-config <repo>: emit the resolved internal-scope/registry allowlist,
# user-layer then project-layer (project wins by appearing later; consumers dedup).
# Unknown keys warned to stderr and skipped. Read-only.
cmd_supply_chain_config() {
  repo="${1:-$PWD}"
  for cf in "$HOME/.config/defect-scan/supply-chain.conf" "$repo/.defect-scan/supply-chain.conf"; do
    case "$cf" in "$HOME/.config/"*) [ -n "${DEFECT_SCAN_NO_USER:-}" ] && continue ;; esac
    case "$cf" in "$repo/.defect-scan/"*) [ -n "${DEFECT_SCAN_NO_PROJECT:-}" ] && continue ;; esac
    [ -f "$cf" ] || continue
    while IFS= read -r ln || [ -n "$ln" ]; do
      case "$ln" in ''|\#*) continue ;; esac
      case "$ln" in
        internal_scope=*|internal_registry=*) printf '%s\n' "$ln" ;;
        *) echo "supply-chain-config: ignoring unknown directive: $ln" >&2 ;;
      esac
    done < "$cf"
  done
  return 0
}
```
- [ ] **Step 4: Dispatch + usage** — add `supply-chain-config) cmd_supply_chain_config "$@" ;;` to `main`, and `|supply-chain-config` to the usage string.
- [ ] **Step 5: Run → PASS.** `bats tests/detect.bats -f "supply-chain-config"`
- [ ] **Step 6: `sh -n` + commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(scan): layered supply-chain internal-scope allowlist reader"
```

---

## Phase 4 — `patterns/supply-chain.md` (P11–P14) + `cmd_patterns` glob

### Task 4.1: Glob built-in pattern packs

**Files:** Modify `skills/scan/lib/detect.sh:319` (`cmd_patterns`) · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: `patterns` lists BOTH recurring.md and supply-chain.md as built-ins, recurring.md first*)
```bash
@test "patterns: lists built-in supply-chain.md alongside recurring.md" {
  run "$DETECT" patterns "$BATS_TEST_TMPDIR"
  [[ "${lines[0]}" == *"recurring.md" ]]
  [[ "$output" == *"patterns/supply-chain.md"* ]]
}
```
- [ ] **Step 2: Run → FAIL** (supply-chain.md not listed).
- [ ] **Step 3: Implement** — replace the single recurring.md echo at `detect.sh:319` with a recurring-first glob:
```sh
  echo "$(skill_dir)/patterns/recurring.md"
  for f in "$(skill_dir)/patterns"/*.md; do
    [ -f "$f" ] || continue
    case "$f" in */recurring.md) continue ;; esac   # already emitted first
    echo "$f"
  done
```
- [ ] **Step 4: Create a minimal `patterns/supply-chain.md`** so the glob has a target (full prose in Task 4.2; start with a valid stub):
```markdown
# Supply-Chain Defect Patterns (npm-first)

Cross-cutting integrity/provenance defects (cat#6). Consulted in the reasoning pass
alongside `recurring.md`. npm-first; examples show how each manifests.
```
- [ ] **Step 5: Run → PASS.** `bats tests/detect.bats -f "supply-chain.md alongside"`
- [ ] **Step 6: Confirm existing patterns test still green** (the prior "recurring.md plus a project pattern pack" test): `bats tests/detect.bats -f "patterns:"` → all PASS.
- [ ] **Step 7: Commit**
```bash
git add skills/scan/lib/detect.sh skills/scan/patterns/supply-chain.md tests/detect.bats
git commit -m "feat(scan): glob built-in pattern packs; add supply-chain.md"
```

### Task 4.2: Write the P11–P14 pattern prose

**Files:** Modify `skills/scan/patterns/supply-chain.md` · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: the pack defines P11–P14, each citing cat#6, with a severity table*)
```bash
@test "supply-chain.md defines P11-P14 mapped to cat#6" {
  f="$BATS_TEST_DIRNAME/../skills/scan/patterns/supply-chain.md"
  for p in P11 P12 P13 P14; do grep -q "$p" "$f"; done
  grep -qi "cat#6" "$f"
}
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Write the full pack** — replace the stub with P11–P14, each section following `recurring.md`'s shape (Generic defect / Invariants to check / Detection heuristic / Default severity / maps to cat#6). Content:
  - **P11 Malicious lifecycle script** (High): network/`exec`/`child_process`/obfuscation/`curl|sh` in a lifecycle command *or its resolved local script* (SCRIPT section). Adversarial check: is it a legit build step (tsc/webpack)?
  - **P12 Typosquat / dependency confusion** (Low–Medium): a dependency name one edit from a popular package; an internal-looking `@scope` resolving to the public registry. Honor the `supply-chain-config` allowlist (declared-internal scopes are expected; an *undeclared* internal-looking scope is the finding). Always adversarially verify — model knowledge can be wrong.
  - **P13 Lockfile tampering** (Medium): `resolved` host ≠ configured/default registry; **absent** integrity; **malformed** integrity. Semver-range-vs-manifest is model-only judgment, lower confidence.
  - **P14 Install-time credential/env exfil** (High): reads `process.env`/`~/.npmrc`/`~/.aws`/tokens and sends them out during install — in the inline command or the resolved SCRIPT.
  - A severity table mirroring `recurring.md`'s.
- [ ] **Step 4: Run → PASS.** `bats tests/detect.bats -f "P11-P14"`
- [ ] **Step 5: Commit**
```bash
git add skills/scan/patterns/supply-chain.md tests/detect.bats
git commit -m "docs(scan): P11-P14 supply-chain pattern prose"
```

---

## Phase 5 — Backward-compatible multi-file fixture harness *(riskiest — touches the shared grader/runner)*

### Task 5.1: Grader — case-relative path keying

**Files:** Modify `skills/scan/lib/detect.sh` (`cmd_eval` expected/actual normalization ~354/362) · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: a directory fixture `case/` with sidecar `case.expected` listing `pkg/a.js:3:cat#6`; given findings keyed `case/pkg/a.js:3:cat#6`, the grader scores tp=1; and the existing single-file basename matching still scores correctly*)
```bash
@test "eval grader: matches directory-fixture findings by case-relative path" {
  dir="$BATS_TEST_TMPDIR/sc/seen"; mkdir -p "$dir/case1/pkg"
  printf 'pkg/a.js:3:cat#6\n' > "$dir/case1.expected"
  printf 'case1/pkg/a.js:3:cat#6\n' > "$BATS_TEST_TMPDIR/findings.txt"
  run "$DETECT" eval "$dir" "$BATS_TEST_TMPDIR/findings.txt"
  [[ "$output" == *"tp=1"* ]]; [[ "$output" == *"fp=0"* ]]; [[ "$output" == *"fn=0"* ]]
}
```
  (Plain-English back-compat: keep the existing single-file tests, e.g. `eval: python corpus scores a clean run`, green — they assert basename matching.)
- [ ] **Step 2: Run → FAIL** (current grader keys both sides by basename, so `a.js` vs `case1/pkg/a.js` won't align on the case).
- [ ] **Step 3: Implement** — change the *actual*-side normalization (`detect.sh:362`) to key by path relative to the corpus dir's case, and the *expected*-side to prefix `base/` when the case is a directory. Concretely: expected sidecar `case1.expected` whose matching fixture `case1/` is a directory → prefix each expected line with `case1/`; single-file `foo.java.expected` → keep basename. Actual findings → strip a leading `<corpus>/`-style prefix to the case-relative form. Implement by deriving, for each `*.expected`, whether a sibling **directory** of the same case-name exists; if so use `case/relpath`, else basename. Keep the ±2 line tolerance and bucket logic unchanged.
- [ ] **Step 4: Run → PASS** (new test) **and** `bats tests/detect.bats -f "eval:"` (all existing grader tests still green — backward compat).
- [ ] **Step 5: `sh -n` + commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(eval): grader keys directory fixtures by case-relative path (back-compat)"
```

### Task 5.2: Runner 3-arg interface + directory scan

**Files:** Modify `tests/eval/runners/{claude,codex}.sh` · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: each runner accepts a 3rd arg (scan profile); when arg 3 is absent it defaults to arg 2; the runner still forces `--lang` and stays read-only*)
```bash
@test "runners accept a scan-profile 3rd arg, defaulting to the corpus arg" {
  for rn in claude codex; do
    f="$BATS_TEST_DIRNAME/../tests/eval/runners/$rn.sh"
    grep -q '\${3:-\$lang}\|\${3:-"\$lang"}\|scan_profile' "$f"
  done
}
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — in each runner add `scan_profile="${3:-$lang}"`, pass `--lang "$scan_profile"` to the scan (instead of `--lang "$lang"`), keep `eval-categories "$lang"` for labels, and when the fixture path is a **directory** copy the whole dir (not one file) into the temp workdir and scan the dir. Preserve read-only flags.
- [ ] **Step 4: Run → PASS**, and `bats tests/detect.bats -f "runners exist, are read-only"` still green.
- [ ] **Step 5: Commit**
```bash
git add tests/eval/runners/claude.sh tests/eval/runners/codex.sh tests/detect.bats
git commit -m "feat(eval): 3-arg runner interface (corpus labels vs scan profile) + dir fixtures"
```

### Task 5.3: `eval-run` — directory fixtures + `--as`

**Files:** Modify `skills/scan/lib/detect.sh` (`cmd_eval_run` loop ~519 + arg parse ~493) · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: `eval-run --as react-typescript supply-chain` passes `react-typescript` to the runner as the scan profile while using `supply-chain` as corpus+labels; a directory fixture is scanned (not skipped)*). Use the stub runner pattern already in the suite (assert the args the runner received).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — add `--as) as_profile="${2:?}"; shift 2 ;;` to the arg loop (default `as_profile=""`); in the fixture loop, replace `[ -f "$src" ] || continue` with handling both files and **directories** (`[ -f "$src" ] || [ -d "$src" ] || continue`; skip `*.expected`); invoke the runner as `"$runner" "$src" "$lang" "${as_profile:-$lang}"`.
- [ ] **Step 4: Run → PASS**, and `bats tests/detect.bats -f "eval-run"` all green.
- [ ] **Step 5: `sh -n` + commit**
```bash
git add skills/scan/lib/detect.sh tests/detect.bats
git commit -m "feat(eval): eval-run --as profile override + directory-fixture scanning"
```

### Task 5.4: CI workflow passthrough

**Files:** Modify `.github/workflows/eval-run.yml`

- [ ] **Step 1:** Update the `workflow_dispatch` inputs + the `eval-run` invocation to accept/forward an optional `as_profile` (`--as`). No model runs in PR CI (unchanged), so this is config only.
- [ ] **Step 2: `sh -n`/yaml lint locally if available; commit**
```bash
git add .github/workflows/eval-run.yml
git commit -m "ci(eval): forward --as scan-profile to eval-run"
```

---

## Phase 6 — Wire both harness drivers + report-format

### Task 6.1: SKILL.md (Claude) + report-format.md

**Files:** Modify `skills/scan/SKILL.md`, `skills/scan/report-format.md` · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: SKILL.md tells the model to run `detect.sh manifest` when an npm ecosystem is present, references the supply-chain pattern, tags npm-audit/osv findings cat#6; report-format mentions cat#6*)
```bash
@test "SKILL.md wires the manifest hook and cat#6" {
  f="$BATS_TEST_DIRNAME/../skills/scan/SKILL.md"
  grep -q "detect.sh manifest" "$f"
  grep -qi "cat#6\|supply-chain" "$f"
}
@test "report-format documents cat#6" {
  grep -qi "cat#6\|supply-chain" "$BATS_TEST_DIRNAME/../skills/scan/report-format.md"
}
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Edit SKILL.md** — in Stage 1/2 (detection) add: when `detect.sh stacks` shows an npm ecosystem, run `detect.sh manifest <repo>` and feed its sections to the Stage-3 reasoning pass; consult `patterns/supply-chain.md` (auto-listed); when `npm audit`/`osv-scanner` report known-vuln deps, categorize those findings as `cat#6` (A06). Edit `report-format.md` to include cat#6 in the category grouping.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit**
```bash
git add skills/scan/SKILL.md skills/scan/report-format.md tests/detect.bats
git commit -m "feat(scan): wire manifest hook + cat#6 into the Claude driver"
```

### Task 6.2: Codex driver parity

**Files:** Modify `codex/defect-scan.md`, `AGENTS.md` · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: the Codex driver references the manifest hook + cat#6 the same way Claude's does*)
```bash
@test "Codex driver mirrors the manifest hook + cat#6" {
  f="$BATS_TEST_DIRNAME/../codex/defect-scan.md"
  grep -q "detect.sh manifest" "$f"
  grep -qi "cat#6\|supply-chain" "$f"
}
```
- [ ] **Step 2: Run → FAIL → Step 3: mirror the SKILL.md additions into `codex/defect-scan.md` (and any AGENTS.md pointer) → Step 4: PASS → Step 5: commit**
```bash
git add codex/defect-scan.md AGENTS.md tests/detect.bats
git commit -m "feat(scan): Codex driver parity for manifest hook + cat#6"
```

---

## Phase 7 — Eval corpus + baseline *(needs Phase 5)*

### Task 7.1: Build the fixture mini-repos

**Files:** Create under `tests/eval/supply-chain/seen/` + sibling `.expected` · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: the supply-chain corpus exists with ≥1 buggy and ≥1 clean case; each buggy `.expected` is non-empty and labels cat#6; each clean `.expected` is empty*)
```bash
@test "supply-chain corpus has labeled buggy + empty clean cases" {
  d="$BATS_TEST_DIRNAME/../tests/eval/supply-chain/seen"
  [ -d "$d" ]
  grep -rq "cat#6" "$d"/*.expected
  # at least one empty (clean) sidecar exists
  found_empty=0; for e in "$d"/*.expected; do [ -s "$e" ] || found_empty=1; done; [ "$found_empty" -eq 1 ]
}
```
- [ ] **Step 2: Run → FAIL → Step 3: create the mini-repos** (each a directory + sibling `<case>.expected`):
  - `malicious-postinstall/` (inline `curl … | sh` in postinstall) → `…:cat#6`
  - `postinstall-script/` (`postinstall: node scripts/install.js` + a malicious `scripts/install.js`) → label points at the SCRIPT path → `scripts/install.js:N:cat#6`
  - `dependency-confusion/` (`package.json` `@acme/...` + `.npmrc` pointing the scope at the public registry) → `cat#6`
  - `tampered-lockfile/` (`package-lock.json` with a non-registry `resolved` + absent integrity) → `cat#6`
  - `install-exfil/` (reads `process.env`/`~/.npmrc`, posts it) → `cat#6`
  - clean: `clean-build-postinstall/` (`postinstall: tsc -p .`), `clean-internal-scope/` (`@acme/...` + allowlist + correct registry), `clean-lockfile/` → empty `.expected`
- [ ] **Step 4: Run → PASS** (structure test). **Do not** hand-calibrate the baseline.
- [ ] **Step 5: Commit**
```bash
git add tests/eval/supply-chain tests/detect.bats
git commit -m "test(eval): supply-chain fixture mini-repos (cat#6)"
```

### Task 7.2: Calibrate the baseline (maintainer-run, real model)

**Files:** Create `tests/eval/supply-chain/baseline.seen.txt`

- [ ] **Step 1:** Run the harness (real model spend; needs a runner):
```bash
DEFECT_SCAN_EVAL_RUNNER=tests/eval/runners/claude.sh \
  scripts/eval-run --as react-typescript supply-chain --split seen --runs 3
```
Expected: a `mean_precision/…` line; clean cases produce zero findings (`clean_fp_runs` high).
- [ ] **Step 2:** If it lands well, write the baseline from the measured run:
```bash
DEFECT_SCAN_EVAL_RUNNER=tests/eval/runners/claude.sh \
  scripts/eval-run --as react-typescript supply-chain --split seen --runs 3 --update-baseline
```
- [ ] **Step 3:** If results are noisy/PARTIAL or a clean case false-positives, fix the fixture/pattern (loop back to Task 4.2 / 7.1) — do **not** force the baseline.
- [ ] **Step 4: Commit via a CODEOWNERS-reviewed PR** (the corpus + baseline are protected):
```bash
git add tests/eval/supply-chain/baseline.seen.txt
git commit -m "test(eval): calibrate supply-chain baseline.seen.txt"
```

---

## Phase 8 — Docs

### Task 8.1: Update all category/pattern-count docs

**Files:** Modify `README.md`, `tests/eval/README.md`, `commands/help.md`, `EXTENDING.md`, `CONTRIBUTING.md`, `CLAUDE.md` · Test `tests/detect.bats`

- [ ] **Step 1: Failing test** (*plain English: README says six categories; help.md no longer says "9 patterns"; tests/eval/README documents the multi-file fixture format*)
```bash
@test "docs reflect cat#6 and multi-file fixtures" {
  root="$BATS_TEST_DIRNAME/.."
  grep -qi "six\|cat#6\|supply-chain" "$root/README.md"
  ! grep -q "9 battle-tested patterns" "$root/commands/help.md"
  grep -qi "multi-file\|fixture repo\|directory fixture" "$root/tests/eval/README.md"
}
```
- [ ] **Step 2: Run → FAIL → Step 3: edit each doc:**
  - `README.md`: "five baseline defect categories" → six; add supply-chain to capabilities.
  - `commands/help.md`: correct the pattern count (now P1–P14); mention supply-chain detection.
  - `tests/eval/README.md`: add the `supply-chain` corpus + the directory-fixture format (`<case>/` + `<case>.expected`, case-relative grading, `--as`).
  - `EXTENDING.md`/`CONTRIBUTING.md`: `supply-chain.md` as the worked built-in pattern-pack example; `supply-chain.conf` as a project-layer extension point.
  - `CLAUDE.md`: six categories; the `manifest` hook + resolver; multi-file fixtures.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit**
```bash
git add README.md tests/eval/README.md commands/help.md EXTENDING.md CONTRIBUTING.md CLAUDE.md tests/detect.bats
git commit -m "docs: six categories, supply-chain pack, multi-file eval fixtures"
```

### Task 8.2: Full-suite gate + ship

- [ ] **Step 1:** `bats tests/detect.bats` → all green (0 failures).
- [ ] **Step 2:** `sh -n skills/scan/lib/detect.sh tests/eval/runners/*.sh` → clean.
- [ ] **Step 3:** Ship via `/review-merge-pipeline` (Phases 1–6, 8) and the CODEOWNERS PR for Phase 7. Do **not** `/deploy` until you choose to cut a release.

---

## Self-review notes (author)

- **Spec coverage:** C1→P1; C2/C2.1→P2; C4→P3; C3/D4→P4; C6 harness→P5; C5→P6; C6 corpus→P7; C7→P8. cat#6-tags-known-vuln → Task 6.1 step 3. All spec sections mapped.
- **Backward-compat (the load-bearing risk):** P5 keeps single-file basename matching (Task 5.1 step 4 re-runs existing `eval:` tests) and `[ -f "$src" ]` → `[ -f ] || [ -d ]` is additive (dirs are skipped today).
- **No network / no execution:** the resolver `head`s files, never runs them; refuses abs/traversal/node_modules; manifest never invokes npm.
- **Open implementation choices** (from spec): resolver size cap set to 200 lines here (adjust if needed); `&&`-chained commands are tokenized so each script token is independently resolved.

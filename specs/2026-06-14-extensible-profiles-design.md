# Extensible Profiles & Defect Packs — Design Spec

**Date:** 2026-06-14
**Issue:** stylusnexus/defect-scan#4
**Status:** Approved (brainstorming) → ready for implementation plan

---

## Plain-English summary

Today, teaching defect-scan a new language means editing its engine — adding Dart
required changing `cmd_stacks` detection and the hardcoded triage source-extension
allowlist. After this change, you drop a single Markdown file with a small
structured header into `.defect-scan/profiles/` in your repo (or
`~/.config/defect-scan/profiles/` for personal use) and the scanner picks up the
new language — detection, which files to scan, and the reasoning checklist — with
**zero changes to core**. The same goes for custom defect patterns: drop `.md`
files into `.defect-scan/patterns/` and the reasoning pass reads them alongside the
built-in P1–P10.

Anything that merely *describes* (detection data, checklists, patterns) loads
freely from any layer — it can't execute. Anything that *runs a command* from a
repo you're scanning is confirmation-gated, so this feature can't become the
workspace-config-→-RCE hole defect-scan itself flags as pattern P4.

---

## Goals & non-goals

**Goals**
- A new language requires **zero edits to `detect.sh` core** — just a profile file.
- Teams share profiles & defect packs by committing them to the repo
  (`.defect-scan/`); individuals carry them in `~/.config/defect-scan/`.
- Custom defect patterns (org-specific recurring bugs) load into the reasoning pass.
- No new execution/RCE risk from profiles found inside a scanned repo.
- Built-ins and user profiles are identical in shape (one mechanism).

**Non-goals (YAGNI for v1)**
- Full YAML parsing — a constrained "frontmatter-lite" suffices.
- An arbitrary `DEFECT_SCAN_PROFILE_PATH` env override (three fixed layers only).
- Marketplace-distributed profile *packs* (future; the issue notes it).
- A formal JSON-schema validator beyond the required-field checks.

---

## 1. Profile format (frontmatter-lite)

Each `profiles/*.md` gains a constrained frontmatter header. Format rules (kept
minimal so a small `awk` parser handles it — no YAML dependency):
- Delimited by `---` lines at the top of the file.
- Flat `key: value` pairs only (no nesting).
- List values are space- or comma-separated on a single line.

```markdown
---
name: dart
detect_files: pubspec.yaml          # any of these files present in target → match
extensions: dart                    # source exts → detection AND triage source-filter
tools: dart, flutter                # tool NAMES only (resolved via detect.sh tool)
---
## Detection
## Toolchain
## Reasoning checklist
## Auto-fix-safe
```

Field semantics:
- `name` (required) — profile identifier; dedupe key across layers.
- `detect_files` (optional) — manifest filenames; presence of any → match.
- `extensions` (optional) — source extensions (no dot); used for both detection
  (any file with the ext → match) and the triage source-filter.
- `tools` (optional) — analyzer names the Toolchain prose uses; names only.

The four prose sections are unchanged and still drive the reasoning/tool passes.
**Built-in profiles (generic, python, react-typescript, dart) are migrated to
declare this frontmatter** — that migration is what removes the hardcoded
detection from core. Not optional.

`generic` has no `detect_files`/`extensions` (it is the fallback when nothing else
matches).

---

## 2. Discovery & precedence (`detect.sh` gains 2 subcommands)

Three layers, in precedence order **project > user > built-in**:
- built-in: `<skill>/profiles/` and `<skill>/patterns/`
- user: `~/.config/defect-scan/profiles/` and `.../patterns/`
- project: `./.defect-scan/profiles/` and `./.defect-scan/patterns/` (relative to
  the scan target's repo root)

New subcommands:
- `detect.sh profiles [<repo-root>]` → enumerates profile files across the three
  layers, dedupes by `name` (project wins over user wins over built-in), prints
  one line each: `name⇥path⇥origin` where origin ∈ `builtin|user|project`.
- `detect.sh patterns [<repo-root>]` → prints the path of built-in `recurring.md`
  plus every `patterns/*.md` from the user and project layers (no dedupe — packs
  are additive). One path per line.

---

## 3. Core becomes data-driven (the "zero core edit" payoff)

- `cmd_stacks` no longer hardcodes react/python/dart. It loops over
  `detect.sh profiles`, reads each profile's `detect_files`/`extensions` from
  frontmatter, tests the target dir, and emits the `name` of every match. Falls
  back to `generic` when nothing matches.
- `cmd_triage`'s source-extension allowlist is **built at runtime from the union
  of all discovered profiles' `extensions`** (plus a small always-on base for
  shell). A profile declaring `extensions: dart` makes triage include `.dart`
  with no change to `detect.sh`. This is the exact friction we hit, eliminated.

A tiny frontmatter reader (awk) is shared by `cmd_stacks`, `cmd_triage`, and
`cmd_profiles`: given a file and a key, it prints the value(s).

---

## 4. Safety (origin-gated execution)

- **Inert parts** — frontmatter data, reasoning prose, pattern packs — load from
  any layer freely. They cannot execute anything; the model just reads them.
- **Tool commands** — the only execution risk:
  - Built-in-origin profiles' tools auto-run (shipped with the plugin, trusted).
  - Project/user-origin profile tools are declared as **names** and resolved via
    `detect.sh tool` (never a raw shell string). `detect.sh profiles` marks each
    profile's `origin`; SKILL.md instructs: **for non-builtin origin, confirm with
    the user before running the tool.**
- This removes the P4 / workspace-config-→-RCE class by construction, and composes
  with Claude Code's own Bash permission prompt as a second layer.

---

## 5. SKILL.md orchestration changes

- **Stage 1 (detect):** `detect.sh stacks` (now profile-driven) selects profiles;
  load each matched profile by the path from `detect.sh profiles`.
- **Stage 2 (tool pass):** auto-run tools from `origin=builtin` profiles; for
  `origin=user|project`, surface the suggested tool and confirm before running.
- **Stage 3 (reasoning):** consult `baseline-categories.md`, the matched profiles'
  checklists, and **every file listed by `detect.sh patterns`** (built-in P1–P10
  + user + project packs).
- **Flags:** `--no-user-profiles` and `--no-project-profiles` for a pure built-in
  scan (and a clean way to test/repro).

---

## 6. Error handling

- Malformed frontmatter (missing `---`, unparseable key) → skip that profile, warn
  on stderr, continue. One bad drop-in never aborts a scan.
- Profile with no `extensions` → contributes detection/reasoning but its files
  won't be triaged; the report header notes it.
- Name collision across layers → precedence wins; the shadowed profile is noted in
  the report header (don't silently override).
- Missing `~/.config/defect-scan` or `./.defect-scan` dirs → simply no extra
  profiles; never an error.

---

## 7. Testing (plain-English cases)

- The frontmatter reader extracts `name` / `extensions` / `detect_files` / `tools`
  from a sample header; tolerates comma- and space-separated lists.
- `detect.sh profiles` merges three layers; a **project profile shadows a
  same-named built-in** (origin/path reflect the project copy).
- **Zero-core-edit proof:** a project-local profile for a fake language
  (`toml-lang`, `extensions: toml`, `detect_files: foo.toml`) makes `stacks`
  detect it AND triage rank a `.toml` file — with no change to `detect.sh` source.
- `detect.sh patterns` lists built-in `recurring.md` plus a project pattern pack.
- Safety: a project profile's tool is reported `origin=project`; a built-in stays
  `origin=builtin` (the gate signal the orchestration keys on).
- Migration regression: react-typescript / python / dart / generic still detect
  via their new frontmatter.
- Malformed frontmatter → skipped with warning, scan still completes.

---

## Decisions locked during brainstorming

1. **Frontmatter-lite in `profiles/*.md`** (not a separate manifest, not prose
   parsing) — self-describing profiles, sh-parseable, matches SKILL.md's own
   frontmatter convention.
2. **Three discovery layers** — built-in + user (`~/.config/defect-scan`) +
   project (`./.defect-scan`), precedence project > user > built-in.
3. **Profiles AND custom pattern packs** in v1 (discovery already exists; packs
   are a second glob).
4. **Origin-gated execution** — inert parts free from any layer; project/user tool
   commands resolved by name and confirmation-gated, never auto-run.
5. **Built-ins migrated to frontmatter** as part of v1 — removes hardcoded
   detection from core.

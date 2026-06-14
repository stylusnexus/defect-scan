# defect-scan — Design Spec

**Date:** 2026-06-14
**Status:** Approved (brainstorming) → ready for implementation plan
**Type:** Global, model-invocable Claude Code skill

---

## Plain-English summary

Point it at code — a file, a folder, a diff, or a whole repo — and it figures out
what language/stack you're in, runs the real bug-finding tools that stack already
has, then reasons about the bugs those tools can't catch. It hands you a ranked
list of defects with exact locations and evidence. By default it just reports.
Ask it to fix, and it'll repair the ones it's confident about and leave the
judgment calls to you.

It is **language-aware**: detection picks a *profile* (React/TypeScript, Python,
or a generic fallback in v1), and each profile bundles the right toolchain plus a
reasoning checklist tuned to that stack's common traps. Adding a new language
later is one new profile file — no change to the orchestration.

---

## Goals & non-goals

**Goals**
- Surface latent defects in arbitrary code, with evidence and exact locations.
- Be language-aware: run the *real* analyzers a stack already has, then reason
  about what they miss.
- Be safe to run anywhere globally, including read-only audits.
- Culminate in fixing (the "end result"), but in gated, confidence-tiered stages
  rather than fixing blind.

**Non-goals**
- Not a debugger for a *known* bug (that's `systematic-debugging` /
  `debug-feedback-loop`).
- Not a diff/PR reviewer (that's `/code-review`, `code-review-excellence`).
- Not a git-history health tool (that's `codebase-health`).
- Not a fix-everything refactorer — it hands heavy remediation off to
  `review-merge-pipeline` / `systematic-debugging`.

---

## Scope & invocation

- Lives at `~/.claude/skills/defect-scan/` (global; model-invocable and `/defect-scan`).
- **Adaptive target:**
  - no arg → recent changes (uncommitted diff; else last commit)
  - a path → that file or directory
  - `--full` → the whole repo
- **Flags:**
  - `--fix` — apply the high-confidence tier, then re-run the relevant tool to confirm
  - `--fix-all` — aggressive mode (also applies medium tier after confirmation)
  - `--lang <profile>` — force a profile, skip detection
  - `--help` — print use cases and flag reference instead of scanning

---

## Architecture — four stages

1. **Detect** — identify stack(s) from manifests/extensions
   (`package.json` + `tsconfig` → React/TS; `pyproject.toml`/`.py` → Python;
   otherwise generic). A repo can match multiple profiles; all matched profiles run.
2. **Tool pass** — for each detected profile, discover which of its analyzers are
   actually installed, run them on the target, capture structured output.
   Missing tools are noted, not fatal.
3. **Reasoning pass** — Claude reads the target against that profile's checklist
   for the defect classes tools miss. Every reasoning-only finding goes through an
   **adversarial verification** step (a refute-it pass) before it can rank above
   low confidence.
4. **Report (→ fix)** — merge tool + reasoning findings, dedupe, rank by
   confidence × severity, emit the report. If `--fix`, apply the high-confidence
   tier and re-run the relevant tool to confirm the fix held.

---

## Components (files)

```
defect-scan/
  SKILL.md                # orchestration: the 4 stages, flag handling, output format
  profiles/
    react-typescript.md   # toolchain list + reasoning checklist + auto-fix-safe rules
    python.md
    generic.md            # language-agnostic fallback (the 5 baseline categories)
  baseline-categories.md  # the 5 cross-cutting defect types, referenced by every profile
  report-format.md        # the ranked-findings template + confidence-tier definitions
```

Each **profile** declares:
- **Detection signals** — files/extensions that select it.
- **Ordered toolchain** — the exact command(s) to run, and how to read each tool's output.
- **Reasoning checklist** — the defect classes tools miss, specialized to the stack.
- **Auto-fix-safe rules** — which findings are safe for `--fix` to repair.

Profiles are **Markdown, not code** — LLM-readable and trivial to extend, consistent
with the existing skill family. Adding Go/Rust/C++/C# later = one new `profiles/*.md`.

---

## The five baseline defect categories

Cross-cutting, specialized per profile:

1. **Null/undefined & unchecked returns** — null derefs, ignored error returns,
   unchecked `Optional`/`nil`.
2. **Silent failures & swallowed errors** — empty catch blocks, log-and-continue,
   ignored return codes.
3. **Injection & untrusted input** — SQLi, command injection, path traversal, XSS.
4. **Resource leaks** — unclosed files/connections/sockets, missing
   `finally`/`defer`/`with`/`using`.
5. **Concurrency hazards** — races, unsynchronized shared state, await/lock misuse.

**Profile specializations (v1):**
- **React/TypeScript** — `useEffect` dependency bugs, stale closures, missing keys,
  hydration mismatches, `any` escapes, unhandled promise rejections,
  `dangerouslySetInnerHTML`.
- **Python** — mutable default args, bare `except`, async/await misuse,
  GIL-blocking calls, `==` vs `is`, unclosed resources.

**Toolchains (v1):**
- **React/TS** — `tsc --noEmit`, `eslint` (+ available plugins).
- **Python** — `ruff`, `mypy`.
- **generic** — reasoning only, against the five baseline categories.

---

## Confidence tiers

Drives both ranking and what `--fix` is allowed to touch.

- **High** — tool-confirmed, *or* a reasoning finding that survived adversarial
  verification with a clear repro path. → auto-fixable.
- **Medium** — credible reasoning finding, no ground-truth signal. → reported,
  never auto-fixed (unless `--fix-all`).
- **Low** — possible/stylistic. → listed in a collapsed appendix.

---

## Output (report-format.md)

Per finding: **severity · confidence tier · `file:line` · category · one-line
evidence · suggested fix.** Sorted high→low.

Header line: stacks detected, tools run vs. missing (with install hints), counts
per tier. **Honest about coverage** — if a tool wasn't installed, the report says
so rather than implying the code is clean.

---

## Error handling

- No recognized stack → generic profile + a note.
- Tool not installed → skip with an install hint, continue.
- Tool crashes/times out → capture stderr, mark that check inconclusive, continue
  (never abort the whole scan).
- `--fix` with zero high-confidence findings → no-op, says so.
- `--fix` on a dirty working tree → refuse unless changes are committed/stashed,
  so fixes stay revertable (aligns with the "clean checkpoint" rule).

---

## Testing — plain-English cases

- Detects React/TS from a `package.json` + `tsconfig` fixture; detects Python from
  `pyproject.toml`.
- Runs `ruff` on a Python fixture with a known bare-`except` and reports it as
  high-confidence.
- A planted `useEffect` missing-dependency bug surfaces in the React profile.
- A planted swallowed-error (empty catch) surfaces as a reasoning finding and
  survives verification.
- An invented/false "race condition" is *refuted* by the adversarial pass and does
  **not** appear as high-confidence.
- Missing toolchain → scan still completes, header flags the gap.
- `--fix` repairs a tool-confirmed defect and the re-run confirms it; leaves
  medium-tier findings untouched.

---

## Relationship to existing skills

| Existing | Role | How defect-scan differs |
|----------|------|-------------------------|
| `systematic-debugging`, `debug-feedback-loop` | Debug a *known* bug | defect-scan *finds* unknown latent defects |
| `/code-review`, `code-review-excellence` | Review a diff/PR | defect-scan scans arbitrary targets, language-aware, tool-backed |
| `codebase-health` | Git-history diagnostics | defect-scan reads the code itself |

defect-scan hands heavy remediation off to `review-merge-pipeline` /
`systematic-debugging` rather than doing it itself.

---

## Decisions locked during brainstorming

- **Name:** `defect-scan` (matches `exposure-scan` / `debt-scan` / `codebase-health`).
- **Scope:** adaptive (no arg / path / `--full`).
- **Detection method:** hybrid — real tools for ground truth + reasoning for the rest.
- **v1 profiles:** React/TypeScript + Python + generic fallback. Go/Rust/C++/C#
  are drop-in later.
- **Disposition:** report-only by default; `--fix` applies high-confidence tier;
  end-state is auto-fix, gated and tiered with adversarial verification before any
  reasoning finding ranks high.
- **Profiles are Markdown, not code.**

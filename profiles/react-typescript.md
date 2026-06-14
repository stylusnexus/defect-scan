# Profile: react-typescript

## Detection
`package.json` plus a `tsconfig.json` or any `*.ts`/`*.tsx`. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name> <project-dir>` (node_modules/.bin first,
then global). Skip-with-hint if unresolved. **Run from the project root** so
config (flat `eslint.config.*` / `tsconfig.json`) resolves.
- `tsc --noEmit`                              — type errors (whole project).
- `eslint --format json <files>`              — lint/correctness rules.

**ESLint exit codes are not all "problems" — read them:**
- `0` → clean. `1` → lint problems found; parse the JSON.
- `2` → **config/usage error (NOT clean)**. Mark the eslint check **inconclusive**
  in the report; never imply the files passed.

**ESLint 9 flat-config gotcha:** passing explicit file paths can yield
`No files matching the pattern` when those paths fall outside the flat config's
`files`/`ignores` scope (this is exit 2, inconclusive — not clean). Fallbacks, in
order: (1) lint the containing directory instead of individual files; (2) use the
project's own entry (`npm run lint -- <files>` / `npx eslint <files>`); (3) if
still exit 2, report eslint inconclusive and rely on the reasoning pass.

Install hints: `npm i -D typescript eslint`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: non-null assertions (`!`), `any` escapes hiding null, optional chaining gaps.
- cat#2: empty `catch {}`, `.catch(() => {})`, unhandled promise rejections.
- cat#3: `dangerouslySetInnerHTML` with non-sanitized input, `href`/`src` from input.
- cat#4: `useEffect` subscriptions/timers/listeners without cleanup return.
- cat#5: stale closures over state, `useEffect` missing/incorrect deps, setState in
  render, race between async effect and unmount.
React-specific: missing `key` in lists, conditional hook calls, derived-state-in-
effect anti-pattern, hydration mismatches (non-deterministic render output).

## Auto-fix-safe
Only `eslint`-confirmed rules invoked with `--fix` AND in the safe set
(`react-hooks/exhaustive-deps` is NOT auto-safe — it can change behavior; formatting
and unused-var removals ARE). `tsc` findings are never auto-fixed.

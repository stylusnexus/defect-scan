---
name: react-typescript
detect_files: tsconfig.json
extensions: ts tsx
tools: tsc eslint
---
# Profile: react-typescript

## Detection
`package.json` plus a `tsconfig.json` or any `*.ts`/`*.tsx`. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name> <project-dir>` (node_modules/.bin first,
then global). Skip-with-hint if unresolved. **Run from the project root** so
config (flat `eslint.config.*` / `tsconfig.json`) resolves.
- `tsc --noEmit`                              — type errors (whole project).
- `eslint --format json <files>`              — lint/correctness rules.
Optional (deeper, run if installed):
- `npm audit --json`                          — known-vuln dependencies; High.
- `osv-scanner --format json -r <dir>`        — cross-ecosystem vuln scan; High.

**ESLint exit codes are not all "problems" — read them:**
- `0` → clean. `1` → lint problems found; parse the JSON.
- `2` → **config/usage error (NOT clean)**. Mark the eslint check **inconclusive**
  in the report; never imply the files passed.

**ESLint 9 flat-config gotcha:** passing explicit file paths to a flat-config
project commonly breaks — two known exit-2 symptoms: `No files matching the
pattern` (paths outside the config's `files`/`ignores` scope) **and** a hard
`Oops! Something went wrong! :( ESLint: <ver>` internal crash. Treat **either** as
"explicit-paths-unsupported here," not a verdict on the files. **Auto-apply** the
fallbacks in order before reporting — don't stop at the first exit 2: (1) re-run
against the containing directory instead of individual files (same scan, not
inconclusive); (2) use the project's own entry (`npm run lint -- <files>` /
`npx eslint <files>`); (3) only if all three still exit 2, report eslint
inconclusive and rely on the reasoning pass.

Install hints: `npm i -D typescript eslint`.

**Type-aware lint is load-bearing here.** Several of the highest-value checks below
(`no-floating-promises`, `no-misused-promises`, `restrict-plus-operands`,
`switch-exhaustiveness-check`, `no-unsafe-*`) are **inert without type information** —
they only run when eslint uses `parserOptions.projectService: true` (or
`project: true` + `tsconfigRootDir`) and extends `recommendedTypeChecked`/
`strictTypeChecked`. Detect whether typed linting is already on; if not, the reasoning
pass must do this work (don't assume eslint covered it), and note the gap. Likewise
read `tsconfig.json`: with `strict`/`strictNullChecks` **off**, null-deref (cat#1) is
invisible to `tsc` — reason harder; flag absent `noUncheckedIndexedAccess` (hides the
whole `arr[i]`/`record[key]` undefined class) and `noFallthroughCasesInSwitch`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: non-null assertions (`!`), `any` escapes hiding null, optional-chaining gaps;
  unsafe `as`/double-assertion casts (`x as unknown as T`) that re-introduce shape/null
  bugs (`no-unnecessary-type-assertion`); `@ts-ignore`/`@ts-expect-error` masking real
  errors at trust boundaries (`ban-ts-comment`); non-exhaustive `switch` over a union /
  discriminated union — a later-added variant falls through silently
  (`switch-exhaustiveness-check`; pair with a `never` default).
- cat#2: empty `catch {}`, `.catch(() => {})`, unhandled rejections; **floating
  promises** — a Promise-returning call with no `await`/`.then`/`void`, so rejections
  vanish and ordering breaks (`no-floating-promises`).
- cat#3: `dangerouslySetInnerHTML` with non-sanitized input, `href`/`src` from input;
  unvalidated redirect / `new URL(userInput)` → `redirect()`/`router.push()`/`fetch()`
  (open-redirect/SSRF, CWE-601/918); **secrets reaching the client bundle** — any
  `process.env`/server secret read in (or imported by) a Client Component is inlined
  into the browser bundle (guard with the `server-only` package; `NEXT_PUBLIC_` is
  public by definition).
- cat#1+cat#3: `JSON.parse` / `localStorage` / `await res.json()` consumed **without
  runtime validation** — TS types are erased at runtime, so `obj.x.y` is an unguarded
  deref of untrusted input; remediate with a runtime validator (zod/valibot) at the
  boundary (`no-unsafe-member-access` flags the `any` flow).
- cat#4: `useEffect` subscriptions/timers/listeners without cleanup return.
- cat#5: stale closures over state; `useEffect`/`useMemo`/`useCallback` with
  missing/incorrect deps — a stale closure in a memoized callback is a correctness bug,
  not just perf (`react-hooks/exhaustive-deps` covers all deps arrays); setState in
  render; async-effect vs unmount race; **in-place mutation of props or state**
  (`arr.push`, `arr.sort()`, `state.obj.field = v` then `setState(sameRef)` → React
  skips the re-render).
React-specific: missing `key` **and `key={index}`** (index keys corrupt state/DOM
identity on reorder/insert — `react/no-array-index-key`); conditional hook calls;
`useState(expensiveCall())` re-running the initializer every render (use lazy
`useState(() => …)`); derived state stored in state + synced via an effect (compute
during render / `useMemo` instead — "You Might Not Need an Effect"); hydration
mismatches (non-deterministic render output).
TS-specific footguns: `==`/`!=` loose equality (`eqeqeq`; mind the `== null` idiom);
`+` across incompatible types / object→string coercion (`restrict-plus-operands`,
`no-base-to-string`); `async` function passed to a JSX event handler (`onClick={async …}`)
or `useEffect(async …)` (`no-misused-promises`).
Security headers (P10): check `next.config.*` `headers()` / middleware (or `helmet`)
for CSP, HSTS, `X-Frame-Options`, `X-Content-Type-Options`; flag `unsafe-inline`/
`unsafe-eval`/wildcard CSP sources and headers applied to only a subset of routes.
Rules-of-hooks / purity (React 18/19) — recurs in real codebases, eslint
`react-hooks/*` confirms many: `setState` inside an effect with no guard (render
loop), impure calls during render (`performance.now`, `Date.now`, `Math.random`),
reading/writing a ref during render, and breaking manual memoization. These are
behavior-relevant and **not** auto-fix-safe — surface for human review.

## Auto-fix-safe
Only `eslint`-confirmed rules invoked with `--fix` AND in the safe set:
- Safe: formatting, unused-var removals, `no-unnecessary-type-assertion` (removes
  provably-redundant `as` only), `eqeqeq` (`==`→`===`, but **not** the deliberate
  `== null` idiom — review those).
- **Never auto-fix:** `react-hooks/exhaustive-deps` (autofix was deliberately disabled
  upstream — auto-adding deps can cause infinite render loops); `no-floating-promises`
  and `no-misused-promises` (inserting `await` vs `void` changes semantics);
  `switch-exhaustiveness-check`, `ban-ts-comment`, `no-array-index-key` (needs a real
  stable key). `tsc` findings are never auto-fixed.

## Eval labels
cat#5: in React this also covers render/state-IDENTITY hazards (not only data-race concurrency) — index-as-key `key={index}` (corrupts state/DOM identity on reorder/insert), stale closures over state, in-place mutation of props/state, conditional hook calls.

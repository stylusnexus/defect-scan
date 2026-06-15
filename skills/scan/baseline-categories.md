# Baseline Defect Categories

These five categories are cross-cutting. Every profile references this file and
specializes each category to its language.

**Severity vs. confidence — two separate axes.** Each category below carries a
*default severity* (how bad it is **if real**). That is independent of a finding's
**confidence tier** (High/Medium/Low = how sure we are it's real). Never collapse them:
a High-confidence/Low-severity finding and a Low-confidence/High-severity finding are
both valid and different. The severity here is a **suggested default** — context can
raise or lower it (injection on a public endpoint vs. an internal one-off script), and
a project can override the policy entirely (see below).

## 1. Null / undefined & unchecked returns  · default severity: Medium
Null/undefined dereferences, ignored error returns, unchecked `Optional`/`nil`,
accessing a value that a prior call may have failed to produce.

## 2. Silent failures & swallowed errors  · default severity: Medium
Empty catch blocks, `except: pass`, log-and-continue where the caller needed the
error, ignored return/status codes, swallowed promise rejections.

## 3. Injection & untrusted input  · default severity: High
SQL injection, command injection, path traversal, XSS, unsanitized input reaching
an interpreter, a shell, a file path, or the DOM.

## 4. Resource leaks  · default severity: Medium
Unclosed files/sockets/connections/handles, missing `finally`/`defer`/`with`/
`using`, leaked subscriptions/listeners/timers.

## 5. Concurrency hazards  · default severity: High
Data races, unsynchronized shared mutable state, await/lock misuse, check-then-act
races, deadlock-prone lock ordering.

Each finding cites the category number so the report can group by it.

## Severity → priority (global default vs. project policy)
Severity is a **suggested default**; *priority* (what gets fixed first) is a business
decision, so the authoritative policy lives in the **project layer**, not here:

- **Global (this file):** the default bands above + each `recurring.md` pattern's own
  default. Use them for consistent baselines when a project says nothing.
- **Project (`<repo>/.defect-scan/`):** override the mapping for your context — e.g.
  "anything touching billing or auth is P0 here." A project pattern pack states its
  severities; the scan honors the highest-precedence policy, exactly like profile
  field inheritance. `--file-issues` maps the resulting severity to the repo's priority
  labels (P0/P1/P2 or your existing scheme).

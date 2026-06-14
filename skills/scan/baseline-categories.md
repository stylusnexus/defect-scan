# Baseline Defect Categories

These five categories are cross-cutting. Every profile references this file and
specializes each category to its language.

## 1. Null / undefined & unchecked returns
Null/undefined dereferences, ignored error returns, unchecked `Optional`/`nil`,
accessing a value that a prior call may have failed to produce.

## 2. Silent failures & swallowed errors
Empty catch blocks, `except: pass`, log-and-continue where the caller needed the
error, ignored return/status codes, swallowed promise rejections.

## 3. Injection & untrusted input
SQL injection, command injection, path traversal, XSS, unsanitized input reaching
an interpreter, a shell, a file path, or the DOM.

## 4. Resource leaks
Unclosed files/sockets/connections/handles, missing `finally`/`defer`/`with`/
`using`, leaked subscriptions/listeners/timers.

## 5. Concurrency hazards
Data races, unsynchronized shared mutable state, await/lock misuse, check-then-act
races, deadlock-prone lock ordering.

Each finding cites the category number so the report can group by it.

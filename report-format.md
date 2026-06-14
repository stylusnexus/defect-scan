# Report Format & Confidence Tiers

## Confidence tiers
- **High** — tool-confirmed (an analyzer flagged it with a named rule) OR a
  reasoning finding that survived adversarial verification with a clear repro
  path. Eligible for `--fix`.
- **Medium** — credible reasoning finding with no ground-truth signal. Reported,
  never auto-fixed unless `--fix-all`.
- **Low** — possible/stylistic. Listed in a collapsed appendix.

## Header (always printed first)
```
defect-scan — <target> (MODE=<changes|path|full>)
Stacks: <profiles>   Tools run: <list>   Tools missing: <list + install hint>
Triage: deep-reasoned top <k> of <n> in-scope files (rest tool-scanned only)
Findings: High <n> · Medium <n> · Low <n>
```
If a tool was missing, the header says so — never imply clean coverage. If triage
limited the deep pass, the header says how far it reached — never imply every file
was deep-reasoned.

## Per-finding line
```
[<SEVERITY>] (<tier>) <file>:<line> · cat#<n> <short title>
  evidence:  <one line: the rule id, or the reasoning + why it survives>
  fix:       <one-line suggested remedy>
```
Sorted High→Low, then by severity. Low tier goes under a `<details>`-style
"Low-confidence appendix" heading.

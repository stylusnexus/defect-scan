# Report Format & Confidence Tiers

Findings carry **two independent axes** — never collapse them:
- **Confidence tier** (`High/Medium/Low`) — *how sure we are it's real*.
- **Severity** (`High/Medium/Low`) — *how bad it is if real*. The default comes from
  the finding's category (`baseline-categories.md`) or pattern (`recurring.md`);
  context can adjust it, and a project's `.defect-scan/` policy overrides it. Severity
  is what `--file-issues` maps to a priority label (P0/P1/P2).

So a finding can be e.g. High-confidence/Low-severity (real but cosmetic) or
Low-confidence/High-severity (uncertain but scary) — both are meaningful and distinct.

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
Correlation: <on (m findings matched existing issues) | off | unavailable (no gh/remote)>
Findings: High <n> · Medium <n> · Low <n>   (NEW <n> · already-filed <n>)
```
If a tool was missing, the header says so — never imply clean coverage. If triage
limited the deep pass, the header says how far it reached — never imply every file
was deep-reasoned. If correlation was unavailable, the header says so — never imply
NEW when you couldn't check the tracker.

## Per-finding line
```
[<SEVERITY>] (<tier>) [<correlation>] <file>:<line> · cat#<n> <short title>
  evidence:  <one line: the rule id, or the reasoning + why it survives>
  fix:       <one-line suggested remedy>
```
`<correlation>` is one of: `NEW`, `LIKELY FILED #N`, `RELATED #N`,
`VERIFY REGRESSION #N` (closed match), or `FILED #N` (just filed this run via
`--file-issues`). Sorted High→Low, then by severity. Low tier goes under a
`<details>`-style "Low-confidence appendix" heading.

**Category grouping.** Findings are grouped by category number in the final report
block: `cat#1` (null/undefined) · `cat#2` (silent failures) · `cat#3` (injection) ·
`cat#4` (resource leaks) · `cat#5` (concurrency) · `cat#6` (supply-chain / dependency
integrity). `cat#6` covers both pattern-based supply-chain findings (P11–P14 from
`patterns/supply-chain.md`) and tool-confirmed known-vulnerable dependency findings from
`npm audit` / `osv-scanner` (OWASP A06). All are tagged `cat#6` so they surface together
under the supply-chain group.

When `--cross-model` ran, a finding may also carry **cross-model ✓** (a second model
confirmed it) or **cross-model ✗** (the second model refuted it → downgraded). The
header notes that cross-model verification ran and against which model.

**SARIF export (`--sarif <path>`, opt-in).** Independently of the prose report, the
same findings can be serialized to a SARIF 2.1.0 file via `detect.sh sarif` (SKILL.md
Stage 4c): `cat#<n>` → ruleId + CWE, default severity → SARIF `level`. The prose
report stays the source of truth; SARIF is a lossy export for GitHub code-scanning /
editor SARIF viewers, not a replacement.

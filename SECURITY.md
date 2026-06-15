# Security Policy

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately via **GitHub's private vulnerability reporting**: go to the
repository's **Security** tab → **Report a vulnerability** (or the **Advisories**
section). This keeps the report confidential between you and the maintainers until
a fix ships.

When reporting, include where you can: affected file/subcommand, a reproduction or
proof-of-concept, the impact, and any suggested remediation.

We aim to acknowledge a report within a few business days and will keep you updated
through the advisory.

## Scope — what we care about most

defect-scan runs analyzers and shells out to `git`/`gh` against code it scans, and
can file issues. The threat model that matters most here:

- **Command/argument injection from scanned content** (the plugin's own pattern P4).
  Findings and file paths flow into `gh` and shell helpers — they must never be able
  to inject flags or execute commands. See `skills/scan/lib/detect.sh` (argv is
  quoted; issue bodies are passed via file, never argv; no `eval`).
- **Origin-gated tool execution.** A *scanned* repo's user/project profile must never
  cause its declared analyzers to auto-run — built-in profiles auto-run, user/project
  profiles are confirmed first (`SKILL.md` Stage 2). A bypass of this gate is a
  vulnerability.
- **Unintended writes.** `--fix` and `--file-issues` are the only write paths; both
  are opt-in and gated. A scan that mutates files or the tracker without the
  corresponding flag + confirmation is a vulnerability.

## Supported versions

This is an actively developed plugin; security fixes target the latest released
version on the default branch.

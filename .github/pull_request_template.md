<!-- PR title must be a Conventional Commit: type(scope): description
     It becomes the changelog entry (release-please) — write it for a reader. -->

## Summary

<!-- What changed and why. 2–4 bullets. -->
-

## Type of change

- [ ] Bug fix (`fix:`)
- [ ] New feature (`feat:`)
- [ ] New / changed language profile or defect pattern
- [ ] Docs only (`docs:`)
- [ ] Other (chore / refactor / ci / test)

## Checklist

- [ ] `bats tests/detect.bats` passes locally (no build step — this is the gate)
- [ ] `sh -n` clean on any changed shell (`detect.sh` stays POSIX `sh`, no bashisms)
- [ ] Docs updated in lockstep (README / help.md / EXTENDING / SKILL as applicable)
- [ ] Conventional Commit PR title; targets `dev` (not `main`)
- [ ] No secrets, credentials, or PII added (gitleaks runs in CI)
- [ ] If a profile/pattern: fixture added + wired into the test lists (see CONTRIBUTING.md)

## Test plan

<!-- How you verified. Commands + outcomes. -->
-

<!-- If this closes an issue, add: Closes #N -->

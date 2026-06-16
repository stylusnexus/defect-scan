# Changelog

All notable changes to **defect-scan** are recorded here.

This file is **automated**. On deployment, [release-please](https://github.com/googleapis/release-please)
reads the [Conventional Commit](https://www.conventionalcommits.org/) history merged
to `main`, prepends a new version section, and bumps the version in
`.claude-plugin/plugin.json`. **Do not hand-edit released sections** — write good
commit messages instead (`feat:`, `fix:`, `perf:`, `docs:` … show up; `chore:`/`test:`
are hidden by default). The release commit and this file are back-merged `main → dev`
by the deploy flow so history stays aligned.

## [1.8.0](https://github.com/stylusnexus/defect-scan/compare/v1.7.0...v1.8.0) (2026-06-16)


### Features

* **eval:** eval-run shortcut + runner label injection, calibrated baselines, full eval docs ([#15](https://github.com/stylusnexus/defect-scan/issues/15)) ([bbe0343](https://github.com/stylusnexus/defect-scan/commit/bbe034377fb6e1d81f2db7ef1d34b73084186737))
* **eval:** scripts/eval-run wrapper (auto-selects runner) + docs ([#15](https://github.com/stylusnexus/defect-scan/issues/15)) ([#63](https://github.com/stylusnexus/defect-scan/issues/63)) ([b4551d9](https://github.com/stylusnexus/defect-scan/commit/b4551d90f5eb1a1c99da220f0aad8f56d2841877))


### Bug Fixes

* **eval:** runner label injection + measured baselines for rust/shell/yaml/swift ([#15](https://github.com/stylusnexus/defect-scan/issues/15)) ([#67](https://github.com/stylusnexus/defect-scan/issues/67)) ([272f773](https://github.com/stylusnexus/defect-scan/commit/272f773bf374a04b021dff8a0b51b47a54d2ab36))

## [1.7.0](https://github.com/stylusnexus/defect-scan/compare/v1.6.1...v1.7.0) (2026-06-16)


### Features

* **eval:** loop-closing harness + completeness critic ([#15](https://github.com/stylusnexus/defect-scan/issues/15) Phase 2) ([#52](https://github.com/stylusnexus/defect-scan/issues/52)) ([79592da](https://github.com/stylusnexus/defect-scan/commit/79592da6c17aec329d4f16386db2b998df972949))
* **eval:** self-improving eval harness — loop-closing runner, ±2-tolerance grader, completeness critic ([#15](https://github.com/stylusnexus/defect-scan/issues/15)) ([f3685fe](https://github.com/stylusnexus/defect-scan/commit/f3685fefee9a5018328894188f1a1e788b78fe55))


### Bug Fixes

* **eval:** ±2 line-tolerance grader + working runners ([#15](https://github.com/stylusnexus/defect-scan/issues/15)) ([#54](https://github.com/stylusnexus/defect-scan/issues/54)) ([3d60c6d](https://github.com/stylusnexus/defect-scan/commit/3d60c6dee18f680e00f4c3d4037356be6f3c4b85))

## [1.6.1](https://github.com/stylusnexus/defect-scan/compare/v1.6.0...v1.6.1) (2026-06-15)


### Bug Fixes

* **defect-scan:** gitleaks signal/noise — git-mode + value-level baseline ([79446f4](https://github.com/stylusnexus/defect-scan/commit/79446f406b51ef2668d7b75dc7612fed8a6152ea))
* **defect-scan:** gitleaks signal/noise — git-mode + value-level baseline ([#20](https://github.com/stylusnexus/defect-scan/issues/20)) ([#49](https://github.com/stylusnexus/defect-scan/issues/49)) ([0304490](https://github.com/stylusnexus/defect-scan/commit/030449042dda17cf69f722b5c1a26e5ca4cc40c7))

## [1.6.0](https://github.com/stylusnexus/defect-scan/compare/v1.5.0...v1.6.0) (2026-06-15)


### Features

* **defect-scan:** add Codex plugin manifest (display name 'Defect Scan') + sync guards ([#46](https://github.com/stylusnexus/defect-scan/issues/46)) ([3f10ab7](https://github.com/stylusnexus/defect-scan/commit/3f10ab77d10e592f10c3dd26a13cd0a562c5eb2f))
* **defect-scan:** Codex plugin display name + deepened dart/Flutter profile ([cd26647](https://github.com/stylusnexus/defect-scan/commit/cd2664716c5290f3a9ce2e86f80564b440834a62))
* **defect-scan:** deepen dart/Flutter profile + README language table ([#44](https://github.com/stylusnexus/defect-scan/issues/44)) ([b959340](https://github.com/stylusnexus/defect-scan/commit/b959340681637f67811a0347ee4958126d07d13a))

## [1.5.0](https://github.com/stylusnexus/defect-scan/compare/v1.4.0...v1.5.0) (2026-06-15)


### Features

* **defect-scan:** add kotlin and swift profiles (mobile) ([#39](https://github.com/stylusnexus/defect-scan/issues/39)) ([bef67e5](https://github.com/stylusnexus/defect-scan/commit/bef67e5dc2f6c742f02750c4b5149b952c112fd6))
* **defect-scan:** add php profile (PHPStan + Psalm taint + composer audit) ([#40](https://github.com/stylusnexus/defect-scan/issues/40)) ([ad86c19](https://github.com/stylusnexus/defect-scan/commit/ad86c195fc0780cd68a996c24570c63b5d5df8ab))
* **defect-scan:** add rust profile (clippy + cargo-audit + cargo-deny) ([#38](https://github.com/stylusnexus/defect-scan/issues/38)) ([c19b40b](https://github.com/stylusnexus/defect-scan/commit/c19b40bd5a491cdf02505a835a8bbd33fd9bb700))
* **defect-scan:** add yaml profile (yamllint + actionlint/zizmor/kube-linter) ([#37](https://github.com/stylusnexus/defect-scan/issues/37)) ([19c6431](https://github.com/stylusnexus/defect-scan/commit/19c6431b3732002c98567beb94464be86ff12bef))
* **defect-scan:** add yaml, rust, kotlin, swift, php, and shell profiles ([d99d84e](https://github.com/stylusnexus/defect-scan/commit/d99d84e66bcdda04ea502b574ef9350acefe8777))
* **defect-scan:** promote shell to a first-class profile (shellcheck) ([#41](https://github.com/stylusnexus/defect-scan/issues/41)) ([19f23e0](https://github.com/stylusnexus/defect-scan/commit/19f23e0f50f2e9300e282b0f3c8a65334d538285))

## [1.4.0](https://github.com/stylusnexus/defect-scan/compare/v1.3.0...v1.4.0) (2026-06-15)


### Features

* **defect-scan:** add csharp/.NET profile (Roslyn CAxxxx + Security Code Scan + roslynator) ([#27](https://github.com/stylusnexus/defect-scan/issues/27)) ([4a1075b](https://github.com/stylusnexus/defect-scan/commit/4a1075bcd990141f0d4c4bf92b6e2eed8f506b6a))
* **defect-scan:** add go profile (go vet + staticcheck + golangci-lint + govulncheck) ([#25](https://github.com/stylusnexus/defect-scan/issues/25)) ([be0c34b](https://github.com/stylusnexus/defect-scan/commit/be0c34b6ce42ab89c311995a8c4a56a93d76c90b))
* **defect-scan:** add go, csharp, and java language profiles ([daaddf3](https://github.com/stylusnexus/defect-scan/commit/daaddf347fa6be8c258f052878c33ebeb170697d))
* **defect-scan:** add java profile (Error Prone + SpotBugs/find-sec-bugs + PMD + dependency-check) ([#34](https://github.com/stylusnexus/defect-scan/issues/34)) ([8c7df7c](https://github.com/stylusnexus/defect-scan/commit/8c7df7c85947306e79eda2a80cfd6b68d348c99a))

## [1.3.0](https://github.com/stylusnexus/defect-scan/compare/v1.2.0...v1.3.0) (2026-06-15)


### Features

* **defect-scan:** --cross-model — second-opinion verification via Codex (refs [#7](https://github.com/stylusnexus/defect-scan/issues/7)) ([#17](https://github.com/stylusnexus/defect-scan/issues/17)) ([a240b74](https://github.com/stylusnexus/defect-scan/commit/a240b7447a0df0c286c12bfba5964df2ec06ed7c))
* **defect-scan:** add ruby profile (RuboCop + Brakeman + bundler-audit) ([#22](https://github.com/stylusnexus/defect-scan/issues/22)) ([8d09323](https://github.com/stylusnexus/defect-scan/commit/8d093236e84caceda76b535766f2967264d1cd51))
* **defect-scan:** Codex entrypoint — run the same scan under Codex (refs [#7](https://github.com/stylusnexus/defect-scan/issues/7)) ([#13](https://github.com/stylusnexus/defect-scan/issues/13)) ([1a238f5](https://github.com/stylusnexus/defect-scan/commit/1a238f520c129bb9c1b2e301ffaf0318169d6df8))
* **defect-scan:** Codex support, cross-platform/Windows, eval harness, cross-model, react-ts + ruby profiles ([295d7bb](https://github.com/stylusnexus/defect-scan/commit/295d7bbf4eeb1d9d32ea64fa45ad7383657a56ee))
* **defect-scan:** cross-platform hardening — BSD/GNU audit, preflight, Windows fallback ([#14](https://github.com/stylusnexus/defect-scan/issues/14)) ([36a113f](https://github.com/stylusnexus/defect-scan/commit/36a113f6b3afe0a42d5c3111e8df8895d6eec63c))
* **defect-scan:** enrich react-typescript profile with researched defect classes ([#18](https://github.com/stylusnexus/defect-scan/issues/18)) ([6c7fe78](https://github.com/stylusnexus/defect-scan/commit/6c7fe78477ab97968278d8005011f1b6e82f269a))
* **defect-scan:** per-language eval harness — measured, safe self-improvement (refs [#15](https://github.com/stylusnexus/defect-scan/issues/15)) ([#16](https://github.com/stylusnexus/defect-scan/issues/16)) ([86bcadd](https://github.com/stylusnexus/defect-scan/commit/86bcadd74df8edc0ad35242790f4a4d9d52dbd50))

## [1.2.0](https://github.com/stylusnexus/defect-scan/compare/v1.1.1...v1.2.0) (2026-06-15)


### Features

* **defect-scan:** --file-issues — file deduped, labeled tracker issues from findings ([#6](https://github.com/stylusnexus/defect-scan/issues/6)) ([4791805](https://github.com/stylusnexus/defect-scan/commit/4791805e86f72f72ce433d81dcf987188665d69f))
* **defect-scan:** --file-issues, scope-resolution fix, Dart profile, extensible profiles + public-readiness hardening ([83ebd16](https://github.com/stylusnexus/defect-scan/commit/83ebd16e543d17f13b3882cfe9a7529d07f04bdf))
* **defect-scan:** 3-layer profile discovery (cmd_profiles) ([518659f](https://github.com/stylusnexus/defect-scan/commit/518659f9b7d2c99d5185eab4f2bf306c58b8be7b))
* **defect-scan:** add Dart/Flutter profile + include .dart in triage source-filter ([2e70008](https://github.com/stylusnexus/defect-scan/commit/2e70008c33ad989acefc48c2d615599d84297f62))
* **defect-scan:** add frontmatter to built-in profiles ([f374cb2](https://github.com/stylusnexus/defect-scan/commit/f374cb2a54b785530c0540ded054e94997de55fc))
* **defect-scan:** add P10 — security response headers (CSP & friends) ([9a0ae0d](https://github.com/stylusnexus/defect-scan/commit/9a0ae0d70d09144b60a146bc4b7004406e8804f8))
* **defect-scan:** data-driven cmd_stacks (profile frontmatter) ([ebd159c](https://github.com/stylusnexus/defect-scan/commit/ebd159c6272ec5ffc50a60450de933fa91a313b4))
* **defect-scan:** data-driven triage source-filter (profile extensions) ([1ebb364](https://github.com/stylusnexus/defect-scan/commit/1ebb3648376659f99adccb9fa72112ab8f7b3dc4))
* **defect-scan:** field-by-field shadow-merge (fm_field) ([7682987](https://github.com/stylusnexus/defect-scan/commit/768298770d809d400bdaccad1dc350ebb96d287f))
* **defect-scan:** frontmatter-lite reader (fm_get) + skill_dir ([7c6f07d](https://github.com/stylusnexus/defect-scan/commit/7c6f07d8fe30114bb207dc94de5fd10080e7ebe0))
* **defect-scan:** pattern-pack discovery (cmd_patterns) ([1777b46](https://github.com/stylusnexus/defect-scan/commit/1777b46eeee10e0f3b35251a520d49fd2328384a))
* **defect-scan:** SKILL.md orchestration for layered profiles + origin gating ([159dad8](https://github.com/stylusnexus/defect-scan/commit/159dad84be02c5e535b6b3088c418cfdf44439ea))


### Bug Fixes

* **defect-scan:** guard fm_field calls in cmd_stacks so extensions-only profiles detect ([1401728](https://github.com/stylusnexus/defect-scan/commit/140172847fafb6dd8dff4facfe737d962fe5512b))
* **defect-scan:** resolve scan scope on clean/merge-HEAD trees; never dead-end silently ([#5](https://github.com/stylusnexus/defect-scan/issues/5)) ([22176cf](https://github.com/stylusnexus/defect-scan/commit/22176cff02c6b589f9633f4474c45add94d7b910))

## [1.1.1]

Baseline at the time changelog automation was introduced. For changes before this
point, see the git history. Subsequent versions are generated automatically.

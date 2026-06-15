# Changelog

All notable changes to **defect-scan** are recorded here.

This file is **automated**. On deployment, [release-please](https://github.com/googleapis/release-please)
reads the [Conventional Commit](https://www.conventionalcommits.org/) history merged
to `main`, prepends a new version section, and bumps the version in
`.claude-plugin/plugin.json`. **Do not hand-edit released sections** — write good
commit messages instead (`feat:`, `fix:`, `perf:`, `docs:` … show up; `chore:`/`test:`
are hidden by default). The release commit and this file are back-merged `main → dev`
by the deploy flow so history stays aligned.

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

---
name: yaml
detect_files:
extensions: yml yaml
tools: yamllint actionlint
---
# Profile: yaml

This is a **config-correctness** profile, not a code-logic one — the five baseline
categories mostly don't apply (no control flow). Its defects are **type-coercion
footguns** (silent-wrong-value) and **insecure declarative config**; the headline
defect is **GitHub Actions script injection** (cat#3). The toolchain is **role-branched**
(Actions vs k8s vs Ansible vs generic), chosen per file by path/shape.

## Detection
Any `*.yml`/`*.yaml`. There's no reliable literal sentinel file (YAML is everywhere),
so `detect_files` is empty and detection is **extension-only** (`detect.sh stacks`).
Consequence: because almost every repo has CI/config YAML, this profile **co-detects on
nearly every scan** and `yml`/`yaml` enter the triage source-filter — i.e. YAML is
effectively always-on. That's intended (Actions injection is worth catching everywhere),
but it does mean YAML files now get triaged where they were previously filtered out.
Decide each file's **role** in reasoning, by path/shape:
- `.github/workflows/*.{yml,yaml}` → GitHub Actions workflow (strongest signal).
- root `apiVersion:` + `kind:` → Kubernetes manifest.
- `playbook*.yml` / `roles/` / `tasks/` / top-level `hosts:` → Ansible.
- else → generic YAML config.

## Toolchain
Resolve each via `detect.sh tool <name>`. **All are source-only — no build/restore.**
Run generic-first, then role-specific only when the file's role matches; skip-with-hint.
- `yamllint -f parsable <files>` — generic: syntax, **duplicate keys** (`key-duplicates`),
  indentation/nesting, trailing spaces, **truthy ambiguity** (`truthy`), **octal values**
  (`octal-values`). Always run. Install: `pip install yamllint`.
Role-specific (run only when the file role matches):
- `actionlint -format '{{json .}}' <workflow-files>` — GitHub Actions: the **script-
  injection class** (untrusted `${{ github.event.* }}` into `run:`), auto-runs
  `shellcheck` on `run:` steps, expression errors, deprecated syntax. Install:
  `brew install actionlint` (+ `shellcheck` for run-step analysis).
- `zizmor --format json <workflow-files-or-dir>` — GH-Actions **security audit**:
  `template-injection`, `dangerous-triggers` (`pull_request_target`),
  `excessive-permissions`, `unpinned-uses`. Install: `pip install zizmor`.
- `kube-linter lint --format json <manifests>` (privileged/runAsRoot, missing
  limits, `:latest`) + `kubeconform -output json <manifests>` (schema). Install:
  `brew install kube-linter kubeconform`.
- `ansible-lint -f json <playbooks>` — Ansible playbooks/roles. Install:
  `pip install ansible-lint`.

## Reasoning checklist
- cat#3 (the headline): **GitHub Actions script injection** — untrusted
  `${{ github.event.issue.title }}` / `pull_request.title`/`.body` / `github.head_ref`
  interpolated into a `run:` shell step → arbitrary command execution; bind to an
  intermediate `env:` var and reference `"$VAR"` instead (actionlint / zizmor
  `template-injection`; CWE-94/CWE-78). **`pull_request_target` + checkout of the PR
  head** runs base-repo secrets against attacker code (zizmor `dangerous-triggers`).
  **Over-broad/missing `permissions:`** (least privilege; zizmor `excessive-permissions`).
  **Unpinned actions** `uses: foo/bar@main`/`@v4` vs a pinned SHA (supply chain; zizmor
  `unpinned-uses`). Inline **secrets** committed in config (cross-ref `gitleaks`).
- cat#3 (Kubernetes): `privileged: true`/run-as-root (no `runAsNonRoot`), missing
  CPU/memory requests+limits, `:latest` image tag, missing `securityContext`/
  `readOnlyRootFilesystem` (kube-linter); wrong/typo'd fields vs schema (kubeconform).
- cat#2 (silent failure): **duplicate mapping keys** — the last value silently wins,
  most loaders raise no error (yamllint `key-duplicates`).
YAML-specific (type-coercion — the silent-wrong-value class, no code category fits):
- **Norway problem**: unquoted `no`/`yes`/`on`/`off`/`y`/`n` resolve to booleans under
  YAML 1.1 (`country: NO` → `false`) — quote identifiers (yamllint `truthy`).
- **Number/version coercion**: unquoted `1.0`→float, `1.20`→`1.2`, leading-zero
  `0777`→octal, sexagesimal `22:22`→base-60, large ints losing precision, a `:` in an
  unquoted value breaking the parse — quote anything number-like that is really an
  identifier/version. (yamllint `octal-values` catches the octal case; float-truncation
  and sexagesimal are **reasoning-only** — no linter flags them.)
- **Null variants** (`null`/`~`/empty/absent are not equivalent across consumers);
  **anchors/aliases & merge-key (`<<`)** resolving to an unexpected value; **wrong
  nesting from mis-indentation** (parses clean, wrong shape — yamllint `indentation`);
  **tabs** in indentation (hard parse error).

## Auto-fix-safe
`yamllint` has no autofix. Only pure-reformat tools — `yamlfmt -w` / `prettier --write`
(whitespace, trailing spaces, document markers) — are safe, and **only** as formatting.
**Never auto-fix**: type-coercion (adding quotes changes the intended type — a human
decision), every Actions security finding (script injection, `pull_request_target`,
permissions, unpinned actions), all kube-linter/kubeconform findings, duplicate-key
resolution, and inline-secret findings. All report-only.

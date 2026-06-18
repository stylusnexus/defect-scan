# Supply-Chain / Dependency Integrity Patterns (cat#6)

Cross-cutting integrity and provenance defects that arise in the software supply
chain — the packages a project depends on, how they are resolved, and the scripts
that run at install time. These patterns map to **cat#6** (Supply-chain / dependency
integrity) from `baseline-categories.md` and are consulted in the reasoning pass
(SKILL.md Stage 3) alongside `recurring.md`. The patterns are npm-first in their
examples because npm's lifecycle system is the richest attack surface, but the
underlying invariants apply wherever a package manager resolves and executes
third-party code at build or install time (pip, gem, cargo, composer, nuget, etc.).

Detection data arrives from `detect.sh manifest` (sections: LIFECYCLE, DEPENDENCIES,
LOCKFILE, NPMRC, SCRIPT) and the `detect.sh supply-chain-config` allowlist
(`internal_scope`, `internal_registry`). Read those sections first; reason over them
using the invariants below.

**Default severities:**

| Pattern | Default severity | Category |
|---------|------------------|----------|
| P11 Malicious lifecycle script | High | cat#6 |
| P12 Typosquat / dependency confusion | Medium | cat#6 |
| P13 Lockfile tampering | Medium | cat#6 |
| P14 Install-time credential / env exfil | High | cat#6 |

*Severity above is impact-if-real — a separate axis from detection **confidence**. P12 is
Low–Medium **confidence** (see its section: the model's package-name knowledge can be wrong,
so adversarial verification is mandatory) despite its Medium severity.*

---

## P11 — Malicious lifecycle script

Category: cat#6 · Default severity: High

**Generic defect:** A `pre/postinstall`, `prepare`, or other npm lifecycle hook
runs a command — or invokes a local script surfaced as a `SCRIPT:` section by
`detect.sh manifest` — that performs network fetches (`curl`, `wget`,
`https.get`, `http.request`, `fetch`), spawns arbitrary shells or child processes
(`child_process.exec`, `child_process.spawn`, `eval`, `sh -c`), pipes fetched
content directly into a shell (`curl … | sh`, `bash <(curl …)`), or is
deliberately obfuscated (base64-encoded commands, hex-escaped strings, runtime
`eval` of decoded content). Any of these shapes in an install-time hook is the
signature of a supply-chain compromise or a backdoored dependency.

**Invariants to check:**
1. **Lifecycle scripts must be deterministic local build steps.** A legitimate
   `postinstall` compiles native bindings (`node-gyp rebuild`), transpiles source
   (`tsc --project tsconfig.build.json`), bundles assets (`webpack --config`), or
   sets up local hooks (`husky install`). These are idempotent, network-free, and
   inspect no external state.
2. **Any `SCRIPT:` content reachable from a lifecycle command is in scope.** If
   the lifecycle field invokes `node scripts/install.js` or `./scripts/setup.sh`,
   read the referenced script's content (the `SCRIPT:` section from the manifest)
   and apply the same analysis — the hook itself may be innocent while the
   delegated script is the payload.
3. **Obfuscation in an install path is presumed hostile.** A legitimate build step
   has no reason to hide what it does. Base64-decoded commands, `eval`'d hex
   strings, or runtime-assembled shell commands in a `postinstall` are a red flag
   regardless of whether the decoded payload itself is visible.

**Detection heuristic:** Read the LIFECYCLE section from `detect.sh manifest`;
for each lifecycle command, check whether it contains: a network tool (`curl`,
`wget`, `axios`, `node-fetch`, `https.get`, `http.get`), a shell-spawn pattern
(`exec`, `spawn`, `child_process`, `sh -c`, `bash -c`, `eval`), a piped-fetch
(`| sh`, `| bash`, `| python`), or an obfuscation marker (`Buffer.from(…,
'base64').toString`, `\x`-escaped strings, `atob`). Then follow any `SCRIPT:`
references and apply the same checks to the script body.

**Adversarial check (mandatory before flagging):** Is this a well-known legitimate
build tool? Common false-positive patterns:
- `node-gyp rebuild` → compiles native C++ bindings, no network, normal.
- `tsc`, `webpack`, `rollup`, `esbuild` → local transpile/bundle, no network.
- `husky install` → registers git hooks locally, no network.
- `patch-package` → applies local `.patch` files, no network.
Only flag when the behavior is clearly exfil- or RCE-shaped: a network call whose
destination is not a known registry/CDN, a pipe-to-shell, or clear obfuscation.
A `curl` to download a pre-built binary from the project's own GitHub release is
borderline — note it as Medium and let the reviewer decide.

**Confidence tier:** High when the network/exec/obfuscation pattern is clear.
Medium when a `curl` to a known-good host fetches a binary (common but still
elevated risk). Low when the script merely reads a remote config.

---

## P12 — Typosquat / dependency confusion

Category: cat#6 · Default severity: Medium

**Generic defect:** A declared dependency carries a name that is one or two edits
from a well-known popular package (typosquat — e.g., `expresss` vs `express`,
`lodahs` vs `lodash`, `crossenv` vs `cross-env`, `momnet` vs `moment`), or carries
an internal-looking scoped name (e.g., `@acme/utils`) that resolves to the
**public** registry rather than the project's private/internal registry (dependency
confusion). In either case, a malicious actor has registered a package under the
lookalike or the internal-sounding name on the public registry, and any developer
who runs `npm install` may pull down the attacker's code instead of (or in
addition to) the intended package.

**Invariants to check:**
1. **Reason over every name in DEPENDENCIES against known popular packages.** There
   is no bundled list — use the model's own knowledge of the npm ecosystem. A name
   that is one character substitution, one character deletion/insertion, or a
   word-boundary separator change (`-` vs `` vs `_`) from a top-1000 npm package
   is a typosquat candidate. Flag it; note the suspected intended package.
2. **Internal-looking scopes must resolve to the internal registry.** A scope
   matching a pattern in the `supply-chain-config` `internal_scope` allowlist that
   resolves (per NPMRC) to the configured `internal_registry` is **expected and
   correct** — do not flag it. An internal-looking scope (`@company/…`, `@org/…`)
   that is NOT in the allowlist, or that resolves to `registry.npmjs.org` (or any
   public registry) instead of the internal registry, is the dependency-confusion
   finding.
3. **Absence of an NPMRC entry for an internal scope is itself a signal.** If a
   scoped dependency exists but the NPMRC section shows no `@scope:registry=…` for
   that scope, npm will silently fall back to the public registry.

**Detection heuristic:** Read the DEPENDENCIES and NPMRC sections. For each name:
(a) compute edit distance mentally against well-known packages and flag one-or-two-
edit candidates; (b) for scoped names, cross-check the scope against the
`supply-chain-config` `internal_scope` list and verify the NPMRC routes it to the
`internal_registry`. Flag mismatches.

**Adversarial check (mandatory — precision-first, false positives are costly):**
Before flagging a typosquat, verify: is this name a real, popular, legitimate
package in its own right? Many packages have short, unusual, or acronym-heavy
names that superficially resemble popular ones but are entirely distinct projects
with large download counts. Only flag cases where the resemblance to a well-known
package is strong AND the suspected target package is the obvious intended
dependency given the project's context. When uncertain, do NOT flag — note it as
a low-confidence observation and let the reviewer check npm manually.

**Confidence tier:** Low–Medium by default. Adversarial verification is MANDATORY
here because false positives are costly (a legitimate dependency flagged as
malicious causes unnecessary churn). Only escalate to Medium-High when the
resemblance to a well-known package is unambiguous and the project context makes
the intended package obvious.

---

## P13 — Lockfile tampering

Category: cat#6 · Default severity: Medium

**Generic defect:** An entry in the lockfile (`package-lock.json`, `yarn.lock`,
`pnpm-lock.yaml`) carries a `resolved` URL that points at a host other than the
project's configured or default registry, or carries an `integrity` field that is
absent, empty, or malformed. Lockfiles are a security boundary: they pin
exact resolved URLs and cryptographic hashes so that `npm ci` is reproducible and
tamper-evident. A `resolved` pointing at an unexpected host means the package was
pulled from a different (potentially attacker-controlled) source; a missing or
invalid `integrity` means the content is unverifiable.

**Invariants to check:**
1. **`resolved` hosts must match the configured registry.** The expected host is
   `registry.npmjs.org` by default, or the `internal_registry` from
   `supply-chain-config` for internal scopes. Any `resolved` URL pointing at a
   different domain — a private CDN, a personal domain, an IP address — warrants
   investigation.
2. **Every resolved package must carry a well-formed `integrity` value.** The
   standard form is `sha512-<base64>`. A missing `integrity`, an empty string, or
   a non-standard hash prefix is suspicious, especially for pinned production
   dependencies.
3. **A missing or garbage integrity on a pinned dependency is suspicious.** If the
   lockfile pins an exact version (no semver range) but omits the integrity hash,
   the reproducibility guarantee is broken — a registry could serve different
   content for the same version specifier.

**Detection heuristic:** Read the LOCKFILE section from `detect.sh manifest`. For
each entry, extract the `resolved` URL and `integrity` value. Flag entries where
`resolved` contains a host other than `registry.npmjs.org` (or the configured
`internal_registry`), and entries where `integrity` is absent or does not match
the `sha512-…` format.

**Note — out of scope:** Semver-range-vs-manifest consistency (whether the locked
version satisfies the declared range in `package.json`) is not covered here — that
requires deterministic semver parsing and is better handled by `npm audit` or a
dedicated resolver. Leave that to model-only judgment at Low confidence if you
notice an obvious mismatch.

**Confidence tier:** Medium. A mismatched `resolved` host is a High-confidence
finding; a missing integrity is Medium. Registry-local `resolved` URLs with
well-formed `sha512-` hashes are clean.

---

## P14 — Install-time credential / environment exfil

Category: cat#6 · Default severity: High

**Generic defect:** Code that runs at install time — a lifecycle hook (LIFECYCLE
section) or a script it delegates to (SCRIPT section) — reads credentials or
secrets from the environment (`process.env.NPM_TOKEN`, `process.env.AWS_SECRET_ACCESS_KEY`,
`process.env.CI`, `process.env.GITHUB_TOKEN`, `~/.npmrc`, `~/.aws/credentials`)
and sends that data over the network to an attacker-controlled endpoint. This is
the canonical supply-chain exfil pattern: the malicious package is installed
(possibly as a transitive dependency), its `postinstall` hook fires, harvests
whatever secrets are in the shell environment of the developer or CI runner, and
beacons them to a remote host.

**Invariants to check:**
1. **Install-time code must not read credentials or authentication tokens.** Any
   `process.env` access to a key matching a known secret pattern (`*_TOKEN`,
   `*_KEY`, `*_SECRET`, `*_PASSWORD`, `AWS_*`, `GITHUB_*`, `NPM_*`, `CI_*`)
   inside a lifecycle hook or delegated script is a red flag.
2. **Reading env vars + a network sink in the same install-time path is the
   signature.** The exfil requires both ingredients: access to a secret value AND
   a way to send it out. Look for these co-occurring in the same lifecycle script
   or its immediate callees.
3. **The SCRIPT resolver surfaces referenced payloads — inspect them.** A lifecycle
   hook that delegates to `node scripts/collect.js` or `python setup.py` may hide
   the exfil in the delegated file. `detect.sh manifest` emits `SCRIPT:` blocks for
   referenced scripts; apply the same analysis.

**Detection heuristic:** Scan the LIFECYCLE and SCRIPT sections for (a) environment
variable reads matching known secret patterns and (b) a network send
(`http.request`, `https.get`, `fetch`, `axios.post`, `curl`, `wget`, `dns.lookup`
with an external domain) within the same code path. Flag the combination.

**Adversarial check (mandatory):** Legitimate tools sometimes read environment
variables at install time — for example, `process.env.NODE_ENV` to skip a
postinstall step in production, or `process.env.CI` to suppress interactive
prompts. These are normal and must NOT be flagged. Only flag when a
**secret-shaped** variable (`*_TOKEN`, `*_KEY`, `*_SECRET`, auth credentials) is
read AND a network call to a non-registry, non-CDN host appears in the same code
path. When the network destination is a known CDN or the project's own registry,
lower the severity to Medium and note it for human review.

**Confidence tier:** High when a secret-read and an outbound network call to an
unknown host co-occur in the same install-time code path. Medium when the network
destination is ambiguous or when only one of the two ingredients is confirmed.

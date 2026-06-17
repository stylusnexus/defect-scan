# Extending defect-scan

Add a language or your own defect rules **without editing core** — just drop files.

> **Which guide do I want?**
> - **This file** — extend defect-scan *privately*, for your own repo or machine, by
>   dropping files in `.defect-scan/` or `~/.config/defect-scan/`. No PR, no core edits.
> - **[CONTRIBUTING.md](./CONTRIBUTING.md)** — contribute a language/pattern *back* so
>   it ships as a built-in for everyone (add it under `skills/scan/`, wire tests, PR).
>
> The private path below is the right choice unless the language is broadly useful.

## Add a language (3 steps)
1. **Pick where it lives:**
   - Team-wide (committed with the repo): `.defect-scan/profiles/<name>.md`
   - Personal (all your repos): `~/.config/defect-scan/profiles/<name>.md`
2. **Copy the template** `skills/scan/profiles/TEMPLATE.md.example` to that path,
   rename it `<name>.md`.
3. **Fill the frontmatter** (4 fields) and the prose. Done — `/defect-scan:scan`
   now detects it, triages its files, and reasons with your checklist.

### Frontmatter field reference
| field | required | format | purpose |
|-------|----------|--------|---------|
| `name` | yes | one lowercase word | profile id; also the dedupe/shadow key |
| `detect_files` | no | space/comma list of filenames | repo matches if any is present |
| `extensions` | no | space/comma list, **no dots** | matches files; **enables triage scanning** |
| `tools` | no | space/comma list of command names | analyzers the Toolchain prose runs |

### Worked example — add Ruby
`.defect-scan/profiles/ruby.md`:
```markdown
---
name: ruby
detect_files: Gemfile
extensions: rb
tools: rubocop
---
# Profile: ruby
## Detection
A `Gemfile` or any `.rb` file.
## Toolchain
- `rubocop --format json <files>` — lint/correctness. Install: `gem install rubocop`.
## Reasoning checklist
- cat#2: rescue with empty body / `rescue => e` that swallows.
- cat#4: `File.open` without a block; unclosed connections.
- ruby-specific: `==` vs `eql?`, mutable default args via `||=`, monkey-patch hazards.
## Auto-fix-safe
Only `rubocop -a` autocorrectable cops in a safe set (layout/style).
```
Scan a Ruby repo → it's detected, `.rb` files are triaged, RuboCop runs.

## Add your own defect patterns
Drop `.md` files in `.defect-scan/patterns/` (team) or
`~/.config/defect-scan/patterns/` (personal). The reasoning pass reads them
alongside the built-in P1–P14 — encode your org's recurring bugs.

### Built-in pattern pack example: `supply-chain.md`

`skills/scan/patterns/supply-chain.md` is the reference example of a built-in pattern
pack. It defines four patterns (P11–P14) that all map to **cat#6** (Supply-chain /
dependency integrity), and shows the structure every pack should follow: a severity
table at the top, one `## P<N>` section per pattern, and mandatory `## Adversarial
check` sub-sections (supply-chain false positives are costly; the precision-first rule
applies). The pattern data is fed by `detect.sh manifest` and `detect.sh
supply-chain-config`; the patterns are pure reasoning instructions for the model.

### Supply-chain internal-scope allowlist (project-layer extension point)

For npm repos with an internal registry, add a project-layer allowlist so the
supply-chain reasoning pass knows which scoped package names are expected to resolve
to your private registry and does not flag them as dependency-confusion candidates:

`.defect-scan/supply-chain.conf`:
```
internal_scope=@acme
internal_registry=https://npm.acme.internal
```

Supported keys:
| Key | Format | Effect |
|-----|--------|--------|
| `internal_scope` | `@scope` (one scope per key, or repeat the line) | Declares a scope that should resolve to the internal registry; scoped deps matching this that are NOT routed to `internal_registry` in the lockfile/npmrc are flagged as P12 (dependency confusion). |
| `internal_registry` | full URL | The expected registry URL for internal scopes; `detect.sh supply-chain-config` surfaces this to the reasoning pass. |

`detect.sh supply-chain-config <repo>` reads this file and emits the values; set
`DEFECT_SCAN_NO_PROJECT=1` (or `--no-project-profiles`) to suppress it.

## Tweak a built-in profile for just your repo
You don't have to fork core to adjust a shipped profile. Create a drop-in with the
**same `name`** and set only the field(s) you want to change — everything you omit is
inherited from the built-in (field-by-field shadow-merge). Example: add one Python
reasoning rule and a house extension without losing the rest of the `python` profile:
```markdown
---
name: python
extensions: py pyi pyx        # adds .pyx; inherits tools/detect_files from built-in
---
# Profile: python
## Reasoning checklist
- house rule: flag `print(` left in shipped modules.
```
For changes that belong to *everyone*, enhance the built-in instead — see
[CONTRIBUTING.md](./CONTRIBUTING.md) ("Enhancing an existing language profile").

## Precedence & inheritance
Project (`.defect-scan/`) overrides user (`~/.config/defect-scan/`) overrides
built-in, **by `name`**. A field you leave out inherits from the profile you shadow
— so tweaking one field of a built-in is safe (you won't lose its `extensions`).

## Safety
Analyzers declared by **your own** project/user profiles are **confirmed before
running** (defect-scan never auto-executes a tool command from a scanned repo —
that would be the very RCE class it flags as pattern P4). Only built-in profiles
auto-run their analyzers.

## Toggle layers
`--no-project-profiles` / `--no-user-profiles` scan with built-ins only.

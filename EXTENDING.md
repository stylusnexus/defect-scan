# Extending defect-scan

Add a language or your own defect rules **without editing core** — just drop files.

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
alongside the built-in P1–P10 — encode your org's recurring bugs.

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

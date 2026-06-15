# defect-scan for Codex

Run defect-scan under the [Codex CLI](https://github.com/openai/codex) as well as
Claude Code. The scan logic, language profiles, and defect patterns are **shared** —
this directory only adds the Codex entrypoint. Single source of truth lives in
`../skills/scan/` (`SKILL.md`, `profiles/`, `patterns/`, `lib/detect.sh`).

## Install (one-time)

```sh
# 1. Clone defect-scan somewhere stable and point DEFECT_SCAN_HOME at it.
git clone https://github.com/stylusnexus/defect-scan ~/.defect-scan
echo 'export DEFECT_SCAN_HOME=~/.defect-scan' >> ~/.zshrc   # or ~/.bashrc

# 2. Install the Codex custom prompt.
mkdir -p ~/.codex/prompts
cp ~/.defect-scan/codex/defect-scan.md ~/.codex/prompts/defect-scan.md
```

Optional analyzers (richer coverage, all degrade gracefully) install the same way as
for the Claude plugin — see the top-level `README.md`.

## Use

In any git repo, from Codex:

```
/defect-scan              # scan recent changes
/defect-scan --full --depth 50
/defect-scan src/ --file-issues
```

(or just ask Codex to "run defect-scan on this repo".)

## How it works

`detect.sh` resolves its knowledge files from its own location, so it runs correctly
no matter your working directory — the prompt invokes it as
`$DEFECT_SCAN_HOME/skills/scan/lib/detect.sh` and scans your current repo. The Codex
prompt is a thin driver over the canonical `SKILL.md` pipeline; behavior (tiers,
correlation, `--file-issues` dedup/labels, `--fix` safety, origin-gating) is
**identical** to the Claude plugin by design.

## Keeping it current

`cd $DEFECT_SCAN_HOME && git pull` updates the shared logic and the prompt source;
re-copy `codex/defect-scan.md` into `~/.codex/prompts/` if the prompt itself changed.

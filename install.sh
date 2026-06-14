#!/usr/bin/env sh
# Local dev install: symlink the skill into ~/.claude/skills/ so it loads as
# `defect-scan` while you iterate. For team distribution use the plugin path
# instead (see README): `/plugin install defect-scan@agent-plugins`. Remove this
# symlink once the plugin is installed, to avoid a double-load.
set -eu
REPO="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO/skills/scan"          # the skill now lives under skills/scan/ (plugin layout)
DEST="$HOME/.claude/skills/defect-scan"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "refusing: $DEST exists and is not a symlink" >&2; exit 1
fi
ln -snf "$SRC" "$DEST"
echo "linked $DEST -> $SRC"

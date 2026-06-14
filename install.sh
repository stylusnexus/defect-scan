#!/usr/bin/env sh
# Install defect-scan globally by symlinking it into ~/.claude/skills/.
set -eu
REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills/defect-scan"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "refusing: $DEST exists and is not a symlink" >&2; exit 1
fi
ln -snf "$REPO" "$DEST"
echo "linked $DEST -> $REPO"

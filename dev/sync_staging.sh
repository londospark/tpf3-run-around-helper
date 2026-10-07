#!/usr/bin/env bash
# Installs the mod into the game's local staging area (where the Mod Hub finds it).
# Usage: dev/sync_staging.sh [staging_area_dir]
# Default: the first Steam user that has TpF3 (app 3493540).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-}"
if [ -z "$DEST" ]; then
	DEST=$(ls -d "$HOME"/.local/share/Steam/userdata/*/3493540/local/staging_area 2>/dev/null | head -1)
fi
[ -d "$DEST" ] || { echo "staging area not found; pass it as the first argument" >&2; exit 1; }
rsync -a --delete --exclude .git --exclude dev --exclude AGENTS.md --exclude CODE_REVIEW.md \
	"$ROOT"/ "$DEST/runaround_helper/"
echo "installed to $DEST/runaround_helper"

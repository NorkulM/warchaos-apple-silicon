#!/bin/bash
# ===========================================================================
# Launch WarChaos through the Game Porting Toolkit wine prefix.
#
# Override the install location if you installed elsewhere:
#   GAME_DIR="$HOME/Desktop/Warface/WarChaos" ./scripts/launch.sh
# ===========================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh"

# Where the WarChaos installer placed the game (its default).
GAME_DIR="${GAME_DIR:-$HOME/Desktop/Warface/WarChaos}"

if [ ! -d "$GAME_DIR" ]; then
  echo "Game folder not found: $GAME_DIR"
  echo "Set GAME_DIR to your install path and re-run."
  exit 1
fi

# Find the entry executable (the launcher / game client).
GAME_EXE="${GAME_EXE:-}"
if [ -z "$GAME_EXE" ]; then
  for cand in \
    "$GAME_DIR/Bin64Release/WarChaos Begins.exe" \
    "$GAME_DIR/WarChaos Begins.exe" \
    "$GAME_DIR/Bin64Release/pcnsl.exe"; do
    [ -f "$cand" ] && GAME_EXE="$cand" && break
  done
fi

if [ -z "$GAME_EXE" ] || [ ! -f "$GAME_EXE" ]; then
  echo "Could not find the game executable under: $GAME_DIR"
  echo "Set GAME_EXE to the full path of the .exe and re-run."
  exit 1
fi

echo "Launching: $GAME_EXE"
cd "$(dirname "$GAME_EXE")"
exec "$WINE" "$GAME_EXE"

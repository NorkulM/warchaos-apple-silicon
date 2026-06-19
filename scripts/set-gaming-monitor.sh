#!/bin/bash
# ===========================================================================
# Force the 144 Hz external monitor to be the macOS main display, so the
# Wine/WarChaos launcher and game client open on it (at 1920x1080@144)
# instead of on the built-in retina (1280x832@60).
#
# The Wine mac driver opens windows on the "primary" display = the screen
# at macOS origin (0,0) (the one with the menu bar). This script uses
# `displayplacer` to move the 144 Hz panel to (0,0) and tuck the retina to
# its left. The game then inherits the monitor's native mode.
#
# Usage:
#   scripts/set-gaming-monitor.sh        # apply (144 Hz becomes main)
#   scripts/set-gaming-monitor.sh -r     # restore previous layout
#
# Requires: brew install displayplacer
# Persistent screen IDs are stable per-display; update them if you swap
# monitors (run `displayplacer list` and edit the IDs below).
# ===========================================================================
set -euo pipefail

# --- Monitor IDs (from `displayplacer list`) -------------------------------
RETINA="37D8832A-2D66-02CA-B9F7-8F30A301B230"        # MacBook built-in, 1280x832@60
HZ144="33D41398-E748-4642-915A-441912C4A979"         # 24" external, 1920x1080@144
HZ60="7CF9D2C5-93C5-4E7A-94D2-E8DB8FCBA7D6"          # 23" external, 1920x1080@60

RESTORE_FILE="${WC_DISPLAY_RESTORE:-/tmp/wc-display-restore.txt}"

cmd="${1:-apply}"

case "$cmd" in
  apply)
    if ! command -v displayplacer >/dev/null; then
      echo "displayplacer not found. Install with: brew install displayplacer"
      exit 1
    fi
    # Save the current restore command (last line of `displayplacer list`).
    if [ ! -f "$RESTORE_FILE" ] || [ "${WC_DISPLAY_OVERWRITE_RESTORE:-0}" = "1" ]; then
      displayplacer list 2>/dev/null | grep '^displayplacer ' > "$RESTORE_FILE" || true
      echo "Saved current layout to $RESTORE_FILE"
    fi
    echo "==> Setting 144 Hz monitor ($HZ144) as main display (0,0)..."
    displayplacer \
      "id:$HZ144 res:1920x1080 hz:144 color_depth:8 enabled:true scaling:off origin:(0,0) degree:0" \
      "id:$RETINA res:1280x832 hz:60 color_depth:8 enabled:true scaling:on origin:(-1280,0) degree:0" \
      "id:$HZ60 res:1920x1080 hz:60 color_depth:8 enabled:true scaling:off origin:(1920,0) degree:0"
    echo "==> Done. 144 Hz is now primary. Launch the game with: ./scripts/launch.sh"
    ;;
  restore|-r|--restore)
    if [ ! -f "$RESTORE_FILE" ]; then
      echo "No saved layout at $RESTORE_FILE. Nothing to restore."
      exit 1
    fi
    echo "==> Restoring previous display layout..."
    bash -c "$(cat "$RESTORE_FILE")"
    echo "==> Restored."
    ;;
  *)
    echo "Usage: $0 [apply|restore|-r]"
    exit 2
    ;;
esac

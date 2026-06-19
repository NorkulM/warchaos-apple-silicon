#!/bin/bash
WATCH=/tmp/wc-mouse-watch.log
TRACE=/tmp/wc-trackpad2.log
GAME_LOG="$HOME/Desktop/Warface/WarChaos/Game.log"
: > "$WATCH"
echo "[watcher $(date '+%H:%M:%S')] tailing $TRACE + $GAME_LOG" >> "$WATCH"
tail -F -n0 "$TRACE" "$GAME_LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *ClipCursor*|*clip_cursor*|*clippingCursor*|*hideCursor*|*unhideCursor*|*clientWants*|\
    *MOUSE_MOVED*|*[Rr]elative*|*[Aa]bsolute*|*WM_INPUT*|*capture*display*|*CGCapture*|\
    *fullscreen*[01]*|*err:macdrv*|*fixme:macdrv*)
      printf '%s | %s\n' "$(date '+%H:%M:%S.%3N')" "$line" >> "$WATCH" ;;
  esac
done

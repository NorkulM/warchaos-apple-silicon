#!/bin/bash
WATCH=/tmp/wc-mouse-watch.log
GAME_LOG="$HOME/Desktop/Warface/WarChaos/Game.log"
TRACE_LOG=/tmp/wc-trace.log
: > "$WATCH"
echo "[watcher started $(date '+%H:%M:%S')] tailing: $GAME_LOG , $TRACE_LOG" >> "$WATCH"
tail -F -n0 "$GAME_LOG" "$TRACE_LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *[Mm]ouse*|*[Rr]aw*|*[Ii]nput*|*[Rr]elative*|WM_INPUT|*[Pp]ointer*|*[Cc]ursor*|*[Gg]rab*|*[Cc]lip*|*[Dd]elta*|\
    *err:*|*fixme:*|*warn:*|*abort*|*[Ee]xception*|*[Cc]rash*|*[Ff]ailed*|*use_raw_input*)
      printf '%s | %s\n' "$(date '+%H:%M:%S')" "$line" >> "$WATCH" ;;
  esac
done

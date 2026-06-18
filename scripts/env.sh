#!/bin/bash
# ---------------------------------------------------------------------------
# WarChaos on Apple Silicon - shared environment
# Source this before running any wine command:  source scripts/env.sh
# ---------------------------------------------------------------------------

# Path to the Game Porting Toolkit wine (Gcenx prebuilt, installed in /Applications)
export GPTK_APP="${GPTK_APP:-/Applications/Game Porting Toolkit.app}"
export WINE="$GPTK_APP/Contents/Resources/wine/bin/wine64"
export WINESERVER="$GPTK_APP/Contents/Resources/wine/bin/wineserver"

# Dedicated wine prefix for the game (keeps it isolated from other apps)
export WINEPREFIX="${WINEPREFIX:-$HOME/WarChaos-wine}"

# --- Performance / compatibility -------------------------------------------
export WINEESYNC=1                  # faster synchronization primitives
export ROSETTA_ADVERTISE_AVX=1      # expose AVX through Rosetta (CryEngine / many DX games need it)
export WINEDEBUG=-all               # silence wine debug spam (remove to debug)
export MTL_HUD_ENABLED=0            # set to 1 for an on-screen Metal FPS/perf overlay

# --- .NET installer fixes ---------------------------------------------------
# The WarChaos installer is a self-contained .NET 10 WPF app. Two problems under wine:
#  1) Globalization: .NET can't find ICU -> "culture is not supported" crash.
#     Fix: ship a real ICU (see setup.sh) and use app-local ICU mode below.
export DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU=72.1.0.3
#  2) WPF hardware rendering throws COMException 0x88980406 under wine.
#     Fix: DisableHWAcceleration=1 registry key (set by setup.sh) -> software render.

# Helper: run any windows program inside the prefix
wc-run() { "$WINE" "$@"; }
# Helper: hard-stop everything in the prefix
wc-kill() { "$WINESERVER" -k; }

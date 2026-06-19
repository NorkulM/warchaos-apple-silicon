#!/bin/bash
# ---------------------------------------------------------------------------
# WarChaos on Apple Silicon - shared environment
# Source this before running any wine command:  source scripts/env.sh
# ---------------------------------------------------------------------------

# Wine 11.10+ (Staging) required — the GPTK wine 7.7 is too old for Qt 6.
# Gcenx prebuilt: https://github.com/Gcenx/macOS_Wine_builds/releases
export WINE_APP="${WINE_APP:-/Applications/Wine Staging.app}"
export WINE="$WINE_APP/Contents/Resources/wine/bin/wine"
export WINESERVER="$WINE_APP/Contents/Resources/wine/bin/wineserver"

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
#     Fix: ship a real ICU (see install.sh) and use app-local ICU mode below.
export DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU=72.1.0.3
#  2) WPF hardware rendering throws COMException 0x88980406 under wine.
#     Fix: DisableHWAcceleration=1 registry key (set by install.sh) -> software render.

# --- Qt 6 launcher fixes ----------------------------------------------------
# The launcher (WarChaos Begins.exe) is a Qt 6 QML app. Under Wine:
#  1) darkmode detection crashes (COM/UISettings) -> disable it.
#  2) DPI awareness fails (SetProcessDpiAwarenessContext) -> disable scaling.
#  3) Software & D3D11 RHI backends fail -> force OpenGL (the only one Wine implements well).
export QT_QPA_PLATFORM="windows:darkmode=0"
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_ENABLE_HIGHDPI_SCALING=0
export QSG_RHI_BACKEND=opengl
export QT_OPENGL=desktop

# --- Wine registry fixes (applied by install.sh) ------------------------------
# HKCU\Software\Wine\Direct3D: OffscreenRenderingMode=backbuffer
#   (fixes GL_INVALID_FRAMEBUFFER_OPERATION on macOS)
# HKCU\Software\Wine\Mac Driver: Decorated=Y
#   (forces native window decorations so winemac presents the window on macOS 27)
# HKCU\Software\Microsoft\Avalon.Graphics: DisableHWAcceleration=1
#   (forces WPF software rendering, fixes COMException 0x88980406)

# Helper: run any windows program inside the prefix
wc-run() { "$WINE" "$@"; }
# Helper: hard-stop everything in the prefix
wc-kill() { "$WINESERVER" -k; }

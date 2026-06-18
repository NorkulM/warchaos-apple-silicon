#!/bin/bash
# ===========================================================================
# WarChaos on Apple Silicon - one-shot setup
# Installs: Rosetta 2, Game Porting Toolkit (Gcenx prebuilt), a wine prefix,
# a real ICU for .NET, and the WPF software-render fix.
#
# Usage:   ./setup.sh
# Safe to re-run (idempotent-ish): it skips steps already done.
# ===========================================================================
set -euo pipefail

# --- Versions (bump if upstream changes) -----------------------------------
GPTK_VER="3.0-2"
GPTK_URL="https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-${GPTK_VER}/game-porting-toolkit-${GPTK_VER}.tar.xz"
ICU_VER="72.1.0.3"
ICU_MAJOR="72"
ICU_URL="https://api.nuget.org/v3-flatcontainer/microsoft.icu.icu4c.runtime.win-x64/${ICU_VER}/microsoft.icu.icu4c.runtime.win-x64.${ICU_VER}.nupkg"

GPTK_APP="/Applications/Game Porting Toolkit.app"
WINE="$GPTK_APP/Contents/Resources/wine/bin/wine64"
export WINEPREFIX="${WINEPREFIX:-$HOME/WarChaos-wine}"

say() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

# --- 0. Sanity -------------------------------------------------------------
[ "$(uname -m)" = "arm64" ] || { echo "This guide is for Apple Silicon (arm64) Macs."; exit 1; }

# --- 1. Rosetta 2 ----------------------------------------------------------
say "Step 1/5: Rosetta 2 (run x86-64 binaries on Apple Silicon)"
if arch -x86_64 /bin/bash -c 'exit 0' 2>/dev/null; then
  echo "Rosetta 2 already working."
else
  echo "Installing Rosetta 2 (may ask for your password / take a minute)..."
  softwareupdate --install-rosetta --agree-to-license
fi

# --- 2. Game Porting Toolkit (Gcenx prebuilt) ------------------------------
# NOTE: We deliberately do NOT use `brew install apple/apple/game-porting-toolkit`.
# On macOS 26 (Tahoe) / 27 the Command Line Tools no longer ship an x86_64 slice
# of libxcrun, so x86_64 git/Homebrew can't run and that formula fails to build.
# Gcenx ships a prebuilt GPTK (wine + D3DMetal) that just runs under Rosetta.
say "Step 2/5: Game Porting Toolkit (wine + D3DMetal)"
if [ -x "$WINE" ]; then
  echo "GPTK already installed: $("$WINE" --version 2>/dev/null | head -1)"
else
  echo "Downloading GPTK ${GPTK_VER} (~248 MB)..."
  curl -fL --retry 3 -o /tmp/gptk.tar.xz "$GPTK_URL"
  rm -rf /tmp/gptk && mkdir -p /tmp/gptk
  tar -xJf /tmp/gptk.tar.xz -C /tmp/gptk
  rm -rf "$GPTK_APP"
  mv "/tmp/gptk/Game Porting Toolkit.app" /Applications/
  echo "Removing quarantine and ad-hoc signing (required to run)..."
  /usr/bin/xattr -drs com.apple.quarantine "$GPTK_APP"
  /usr/bin/codesign --force --deep -s - "$GPTK_APP"
  echo "GPTK ready: $("$WINE" --version 2>/dev/null | head -1)"
fi

export WINEESYNC=1 ROSETTA_ADVERTISE_AVX=1 WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="   # skip mono/gecko prompts during init

# --- 3. Wine prefix --------------------------------------------------------
say "Step 3/5: Wine prefix at $WINEPREFIX"
if [ -f "$WINEPREFIX/system.reg" ]; then
  echo "Prefix already exists."
else
  "$WINE" wineboot --init
  echo "Prefix created."
fi

# --- 4. Real ICU for .NET globalization ------------------------------------
# The installer is a .NET 10 WPF app. Without ICU it crashes with
# "culture is not supported" / "'en' is an invalid culture identifier".
say "Step 4/5: ICU ${ICU_VER} for .NET (app-local)"
SYS32="$WINEPREFIX/drive_c/windows/system32"
if [ -f "$SYS32/icuuc${ICU_MAJOR}.dll" ]; then
  echo "ICU already present."
else
  echo "Downloading Microsoft.ICU.ICU4C ${ICU_VER} (~14 MB)..."
  curl -fL --retry 3 -o /tmp/icu.nupkg "$ICU_URL"
  rm -rf /tmp/icuout && mkdir -p /tmp/icuout
  unzip -o -j /tmp/icu.nupkg \
    "runtimes/win-x64/native/icuuc${ICU_MAJOR}.dll" \
    "runtimes/win-x64/native/icuin${ICU_MAJOR}.dll" \
    "runtimes/win-x64/native/icudt${ICU_MAJOR}.dll" -d /tmp/icuout >/dev/null
  cp /tmp/icuout/icu*${ICU_MAJOR}.dll "$SYS32/"
  echo "ICU installed into the prefix."
fi

# --- 5. WPF software rendering ---------------------------------------------
# WPF hardware rendering throws COMException 0x88980406 under wine.
say "Step 5/5: Force WPF software rendering (fix 0x88980406)"
"$WINE" reg add "HKCU\\Software\\Microsoft\\Avalon.Graphics" \
  /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
echo "Done."

cat <<EOF

\033[1;32mSetup complete.\033[0m

Next:
  1) Put WarChaosInstaller.exe somewhere and run it:
       source scripts/env.sh
       "\$WINE" /path/to/WarChaosInstaller.exe
     Complete the install (default target is ~/Desktop/Warface/WarChaos).

  2) Launch the game:
       ./scripts/launch.sh

See README.md for details and troubleshooting.
EOF

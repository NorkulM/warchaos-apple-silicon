#!/bin/bash
# ===========================================================================
# WarChaos on Apple Silicon - one-shot setup
#
# Installs: Rosetta 2, Wine 11.10+ (Gcenx prebuilt), a wine prefix,
# a real ICU for .NET, and all required registry fixes.
#
# Usage:   ./setup.sh
# Safe to re-run (idempotent-ish): it skips steps already done.
# ===========================================================================
set -euo pipefail

# --- Versions (bump if upstream changes) -----------------------------------
WINE_VER="11.10"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VER}/wine-staging-${WINE_VER}-osx64.tar.xz"
ICU_VER="72.1.0.3"
ICU_MAJOR="72"
ICU_URL="https://api.nuget.org/v3-flatcontainer/microsoft.icu.icu4c.runtime.win-x64/${ICU_VER}/microsoft.icu.icu4c.runtime.win-x64.${ICU_VER}.nupkg"

WINE_APP="/Applications/Wine Staging.app"
WINE="$WINE_APP/Contents/Resources/wine/bin/wine"
export WINEPREFIX="${WINEPREFIX:-$HOME/WarChaos-wine}"

say() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

# --- 0. Sanity -------------------------------------------------------------
[ "$(uname -m)" = "arm64" ] || { echo "This guide is for Apple Silicon (arm64) Macs."; exit 1; }

# --- 1. Rosetta 2 ----------------------------------------------------------
say "Step 1/6: Rosetta 2 (run x86-64 binaries on Apple Silicon)"
if arch -x86_64 /bin/bash -c 'exit 0' 2>/dev/null; then
  echo "Rosetta 2 already working."
else
  echo "Installing Rosetta 2 (may ask for your password / take a minute)..."
  softwareupdate --install-rosetta --agree-to-license
fi

# --- 2. Wine 11 (Gcenx prebuilt) -------------------------------------------
# NOTE: The "official" GPTK route (brew install apple/apple/game-porting-toolkit)
# is broken on macOS 26/27 because the CLT no longer ship an x86_64 libxcrun.
# Gcenx ships prebuilt Wine that just runs under Rosetta.
# We use Wine 11 (Staging) because the GPTK's Wine 7.7 is too old for Qt 6.
say "Step 2/6: Wine ${WINE_VER} Staging (Gcenx prebuilt)"
if [ -x "$WINE" ]; then
  echo "Wine already installed: $("$WINE" --version 2>/dev/null | head -1)"
else
  echo "Downloading Wine ${WINE_VER} (~181 MB)..."
  curl -fL --retry 3 -o /tmp/wine.tar.xz "$WINE_URL"
  rm -rf /tmp/wine-extract && mkdir -p /tmp/wine-extract
  tar -xJf /tmp/wine.tar.xz -C /tmp/wine-extract
  rm -rf "$WINE_APP"
  mv "/tmp/wine-extract/Wine Staging.app" /Applications/
  echo "Removing quarantine and ad-hoc signing (required to run)..."
  /usr/bin/xattr -drs com.apple.quarantine "$WINE_APP"
  /usr/bin/codesign --force --deep -s - "$WINE_APP"
  echo "Wine ready: $("$WINE" --version 2>/dev/null | head -1)"
fi

export WINEESYNC=1 ROSETTA_ADVERTISE_AVX=1 WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="   # skip mono/gecko prompts during init

# --- 3. Wine prefix --------------------------------------------------------
say "Step 3/6: Wine prefix at $WINEPREFIX"
if [ -f "$WINEPREFIX/system.reg" ]; then
  echo "Prefix already exists."
else
  "$WINE" wineboot --init
  echo "Prefix created."
fi

# --- 4. Real ICU for .NET globalization ------------------------------------
say "Step 4/6: ICU ${ICU_VER} for .NET (app-local)"
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

# --- 5. ICU forwarder shim (game needs unversioned icu.dll) ----------------
say "Step 5/6: ICU forwarder shim (icu.dll -> icuuc72/icuin72)"
if [ -f "$SYS32/icu.dll" ]; then
  echo "icu.dll already present."
else
  echo "Building icu.dll forwarder..."
  bash "$(dirname "$0")/scripts/build-icu-shim.sh"
fi

# --- 6. Registry fixes -----------------------------------------------------
say "Step 6/6: Registry fixes"

# WPF software rendering (fixes COMException 0x88980406 in .NET installer)
"$WINE" reg add "HKCU\\Software\\Microsoft\\Avalon.Graphics" \
  /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
echo "  WPF software rendering: done"

# Direct3D backbuffer (fixes GL_INVALID_FRAMEBUFFER_OPERATION on macOS)
"$WINE" reg add "HKCU\\Software\\Wine\\Direct3D" \
  /v OffscreenRenderingMode /t REG_SZ /d backbuffer /f >/dev/null 2>&1 || true
echo "  Direct3D backbuffer: done"

# Force native window decorations (winemac presents decorated windows on macOS 27)
"$WINE" reg add "HKCU\\Software\\Wine\\Mac Driver" \
  /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
echo "  Mac Driver decorated: done"

# Enable relative mouse / raw input for FPS pointer grabs (winemac.drv).
# Harmless no-op on an unpatched Wine (the key is simply ignored). Takes effect
# only after you build & install the patched driver: scripts/build-wine-mac-rawinput.sh
# Condition: cursor hidden + ClipCursor active (the FPS grab). See
# WARCHAOS_MACOS_FULL_GUIDE.md > The Mouse Problem.
"$WINE" reg add "HKCU\\Software\\Wine\\Mac Driver" \
  /v RawInput /t REG_SZ /d Y /f >/dev/null 2>&1 || true
echo "  Mac Driver RawInput: done (needs patched winemac.drv to take effect)"

cat <<EOF

\033[1;32mSetup complete.\033[0m

Next:
  1) Run the WarChaos installer:
       source scripts/env.sh
       "\$WINE" /path/to/WarChaosInstaller.exe
     Default install target: ~/Desktop/Warface/WarChaos

  2) Launch the game:
       ./scripts/launch.sh

See README.md for details and troubleshooting.
EOF

#!/bin/bash
# ===========================================================================
# Build a patched winemac.drv with relative mouse (raw input) support and
# install it into the Gcenx Wine Staging.app.
#
# What this does
#   1. Shallow-clones Wine at the tag matching the installed Gcenx build.
#   2. Applies patches/winemac-rawinput.patch (ports winewayland.drv relative
#      pointer behavior to winemac.drv; see the patch header for the full
#      rationale and the real root cause of the FPS mouselook lag).
#   3. Configures + builds JUST dlls/winemac.drv for x86_64 (the Gcenx Wine is
#      an x86_64 binary running under Rosetta, so the unix .so must be x86_64).
#   4. Backs up and replaces winemac.drv.so inside /Applications/Wine Staging.app,
#      then re-signs the bundle ad-hoc.
#
# Why x86_64: WarChaos is an x86_64 PE; Wine does not translate instruction
# sets, it re-implements the ABI, so the Wine process (and its unix .so) must
# be x86_64 and run under Rosetta. We cannot use an arm64 Wine here.
#
# macOS 27 note: the CLT no longer ship an x86_64 libxcrun, so `xcrun` fails
# when invoked under `arch -x86_64`. This script installs a tiny xcrun shim
# that honors $SDKROOT and forwards -find calls to the universal /usr/bin
# tools, which sidesteps the issue. (clang/ld/ar are universal binaries and
# still work under Rosetta.)
#
# Opt-in: after installing, enable the new behavior with the registry key
#   HKCU\Software\Wine\Mac Driver\RawInput = Y
# (set by ./install.sh). Without it the driver behaves exactly as upstream.
#
# Requirements: Xcode CLT, Homebrew, `brew install mingw-w64` (for the PE
# stub), ~3 GB free disk, ~20-40 min on an M4 (configure + one driver).
# Untested on your exact OS; read the messages and adjust if configure fails.
# ===========================================================================
set -euo pipefail

# --- Config -----------------------------------------------------------------
WINE_APP="${WINE_APP:-/Applications/Wine Staging.app}"
WINE_BIN="${WINE_BIN:-$WINE_APP/Contents/Resources/wine/bin/wine}"
WINE_TAG="${WINE_TAG:-wine-11.10}"        # bump to match the Gcenx release you installed
WINE_SRC="${WINE_SRC:-$HOME/Developer/wine-rawinput-src}"
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu)}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$REPO_ROOT/patches/winemac-rawinput.patch"

say()  { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die()  { printf "\n\033[1;31mError: %s\033[0m\n" "$*" >&2; exit 1; }

# --- 0. Preflight -----------------------------------------------------------
say "Step 0/5: Preflight"
[ "$(uname -m)" = "arm64" ] || die "This script is for Apple Silicon (arm64)."
[ -x "$WINE_BIN" ] || die "Wine not found at $WINE_BIN. Run ./install.sh first."
command -v brew    >/dev/null || die "Homebrew not found (https://brew.sh)."
command -v x86_64-w64-mingw32-gcc >/dev/null || {
  say "Installing mingw-w64 (needed to build Wine PE DLL stubs)..."
  brew install mingw-w64
}
command -v git    >/dev/null || brew install git
command -v patch  >/dev/null || brew install patch
# macOS ships ancient bison (2.x); Wine needs >= 3.0. Homebrew's is keg-only
# (not linked into /usr/local), so put it on PATH explicitly.
if ! bison --version 2>/dev/null | awk 'NR==1{exit !($2>="3.0")}'; then
  brew install bison 2>/dev/null || true
fi
[ -x /opt/homebrew/opt/bison/bin/bison ] && export PATH="/opt/homebrew/opt/bison/bin:$PATH"
[ -x /opt/homebrew/opt/flex/bin/flex  ] && export PATH="/opt/homebrew/opt/flex/bin:$PATH"
# Resolve an SDK path using the (working, arm64) default xcrun.
SDKROOT_RESOLVED="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
[ -n "$SDKROOT_RESOLVED" ] || die "Could not resolve macOS SDK. Install Xcode Command Line Tools."
echo "  SDK:            $SDKROOT_RESOLVED"
echo "  Wine version:   $("$WINE_BIN" --version 2>/dev/null | head -1)  (tag $WINE_TAG)"
echo "  Source dir:     $WINE_SRC"
echo "  Jobs:           $BUILD_JOBS"

# --- 1. Fetch Wine source ---------------------------------------------------
say "Step 1/5: Fetch Wine source ($WINE_TAG)"
if [ -d "$WINE_SRC/.git" ]; then
  echo "  Existing clone at $WINE_SRC; resetting to $WINE_TAG..."
  git -C "$WINE_SRC" fetch --depth 1 origin "refs/tags/$WINE_TAG:refs/tags/$WINE_TAG" || true
  git -C "$WINE_SRC" checkout -q "$WINE_TAG"
  git -C "$WINE_SRC" reset --hard "$WINE_TAG"
  git -C "$WINE_SRC" clean -fdq
else
  mkdir -p "$(dirname "$WINE_SRC")"
  git clone --depth 1 --branch "$WINE_TAG" https://github.com/wine-mirror/wine.git "$WINE_SRC"
fi

# --- 2. Apply patch ---------------------------------------------------------
say "Step 2/5: Apply winemac-rawinput.patch"
( cd "$WINE_SRC" && patch -p1 --fuzz=3 < "$PATCH" )
echo "  Patch applied."

# --- 3. Configure (x86_64, minimal) -----------------------------------------
say "Step 3/5: Configure Wine (x86_64 cross-compile, minimal — only winemac.drv needs to link)"

# macOS 27 note: under `arch -x86_64`, clang's x86_64 slice dlopens libxcrun,
# which is arm64-only on macOS 27 -> "unable to load libxcrun". So we DON'T run
# under arch -x86_64. Instead we run configure natively (arm64, where xcrun
# works) and make the compiler emit x86_64 object code via `-target`. Rosetta
# transparently executes the x86_64 test binaries configure produces, so the
# "compiler can create executables" probe passes. The resulting .so is x86_64,
# which is what the Gcenx Wine process (x86_64 under Rosetta) can load.
export SDKROOT="$SDKROOT_RESOLVED"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
TARGET_TRIPLE="x86_64-apple-darwin"
export CC="clang -target $TARGET_TRIPLE -isysroot $SDKROOT_RESOLVED"
export CXX="clang++ -target $TARGET_TRIPLE -isysroot $SDKROOT_RESOLVED"
# Let autoconf's link tests find the right arch; -arch is redundant with -target
# but harmless and makes libtool happy.
export LDFLAGS="${LDFLAGS:-} -arch x86_64"

cd "$WINE_SRC"
./configure --build=x86_64-apple-darwin --enable-archs=x86_64 \
    --disable-win16 --disable-tests \
    --without-alsa --without-capi --without-cups --without-dbus --without-ffmpeg \
    --without-freetype --without-gettext --without-gettextpo --without-gphoto \
    --without-gnutls --without-gssapi --without-gstreamer --without-inotify \
    --without-krb5 --without-netapi --without-opencl --without-pcap --without-pcsclite \
    --without-pulse --without-sane --without-sdl --without-udev --without-usb \
    --without-v4l2 --without-vulkan --without-wayland --without-x \
  || die "configure failed. Read $WINE_SRC/config.log; common fixes: brew install mingw-w64, or set WINE_TAG to match your installed Wine."

echo "  Configure OK."

# --- 4. Build just winemac.drv ----------------------------------------------
say "Step 4/5: Build dlls/winemac.drv"
make -j"$BUILD_JOBS" -C dlls/winemac.drv \
  || die "build failed. Try: cd $WINE_SRC && make -j$BUILD_JOBS -C dlls/winemac.drv V=1"

# Find the produced unix .so. Wine builds it as dlls/winemac.drv/winemac.so
# (the "winemac.drv" PE stub is separate, under x86_64-windows/).
BUILT_SO="$WINE_SRC/dlls/winemac.drv/winemac.so"
[ -f "$BUILT_SO" ] || BUILT_SO="$(find "$WINE_SRC/dlls/winemac.drv" -type f -name 'winemac.so' | head -1)"
[ -n "$BUILT_SO" ] || die "winemac.so was not produced. Check $WINE_SRC/dlls/winemac.drv/"
echo "  Built: $BUILT_SO"
file "$BUILT_SO" | sed 's/^/  /'

# --- 5. Install into Wine Staging.app ---------------------------------------
say "Step 5/5: Install into $WINE_APP (original backed up)"
# The unix shared object lives under lib/wine/x86_64-unix/winemac.so
INSTALLED_SO="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"
[ -f "$INSTALLED_SO" ] || INSTALLED_SO="$(find "$WINE_APP" -type f -name 'winemac.so' -path '*x86_64-unix*' 2>/dev/null | head -1)"
[ -n "$INSTALLED_SO" ] || die "Could not find existing winemac.so inside $WINE_APP to replace."
echo "  Target:  $INSTALLED_SO"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$INSTALLED_SO.orig-$STAMP"
cp -p "$INSTALLED_SO" "$BACKUP"
echo "  Backup:  $BACKUP"
cp -p "$BUILT_SO" "$INSTALLED_SO"

# Re-sign ad-hoc (Gcenx bundle is ad-hoc signed; replacing a .so breaks it
# until re-signed). --deep walks the bundle.
/usr/bin/codesign --force --deep -s - "$WINE_APP" 2>/dev/null || \
  echo "  warn: codesign --deep failed; if macOS refuses to run Wine, run:
      sudo /usr/bin/codesign --force --deep -s - \"$WINE_APP\""

cat <<EOF

\033[1;32mBuild + install complete.\033[0m

Enable raw input (FPS mouselook fix) in the prefix:
    source scripts/env.sh
    "\$WINE" reg add "HKCU\\Software\\Wine\\Mac Driver" /v RawInput /t REG_SZ /d Y /f

Then launch the game:
    ./scripts/launch.sh

To revert:
    cp "$BACKUP" "$INSTALLED_SO"
    /usr/bin/codesign --force --deep -s - "$WINE_APP"

EOF

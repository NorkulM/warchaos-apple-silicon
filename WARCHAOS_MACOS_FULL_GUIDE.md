# WarChaos on Apple Silicon — Complete Technical Guide

**Date:** 2026-06-18  
**Tested on:** MacBook Air M4, macOS 27 Golden Gate Developer Beta  
**Status:** 🟡 **PLAYABLE** — Launcher 100% functional, game reaches lobby, mouse input needs raw input delta support

---

## Table of Contents
1. [Overview](#overview)
2. [What Works](#what-works)
3. [What Doesn't Work Yet](#what-doesnt-work-yet)
4. [Setup Guide](#setup-guide)
5. [Technical Deep Dive](#technical-deep-dive)
6. [All Errors Encountered & Fixes](#all-errors-encountered--fixes)
7. [The Mouse Problem](#the-mouse-problem)
8. [Repository Files](#repository-files)
9. [Next Steps for the Community](#next-steps-for-the-community)

---

## Overview

WarChaos is a CryEngine-based online FPS (Warface private server). There is no native macOS build. This guide documents how to run it on Apple Silicon Macs using Wine + Rosetta 2.

**Architecture:**
```
WarChaos Begins.exe (Qt 6 QML launcher)
  → login (Discord OAuth2)
  → launches game client (CryEngine)
    → DirectX 11 → D3DMetal (or DXVK → MoltenVK → Metal)
    → Rosetta 2 (x86-64 → ARM)
    → macOS 27
```

---

## What Works

| Component | Status | Details |
|-----------|--------|---------|
| Rosetta 2 | ✅ | x86-64 binaries run on M4 |
| Wine 11.10 Staging (Gcenx) | ✅ | Prebuilt, no Homebrew x86 needed |
| .NET 10 WPF Installer | ✅ | Downloads & installs full 29 GB game |
| ICU Globalization | ✅ | Custom `icu.dll` forwarder shim |
| Qt 6 Launcher UI | ✅ | Login, Discord, videos, all QML screens |
| Anti-cheat (ClientProtection) | ✅ | Does NOT block Wine |
| Game client launch | ✅ | CryEngine initializes, reaches lobby |
| Server connectivity | ✅ | `cdn.warchaos.xyz` + `game.warchaos.xyz` respond |
| In-game lobby | ✅ | Inventory, HUD, weapon customization load |
| In-game audio | ✅ | Music theme plays (OGG decoder) |
| Mouse in menus | ✅ | Clicks work perfectly |
| Mouse in FPS camera | ❌ | See [The Mouse Problem](#the-mouse-problem) |

---

## What Doesn't Work Yet

### Mouse FPS Camera (CRITICAL)
The in-game mouselook has ~2 second delay on fast movements. The root cause is that `winemac.drv` does not implement **relative mouse input** (Raw Input Device / RID). It only delivers absolute cursor positions. FPS games need `WM_INPUT` messages with relative deltas.

**What we tried:**
- `MouseWarpOverride=force` — worse
- `DisableExclusiveMode=Y` — no change
- `UseConfinementCursorClipping=N` — no change
- `EnableRawInput=Y` + `UseRawInput=Y` — no change
- macOS Input Monitoring permission — minor improvement, not enough
- `i_mouse=3` / `i_mouse_raw=1` in CryEngine autoexec — no change

**What would fix it:**
- A Wine build with RID support in `winemac.drv` (CrossOver has this)
- Or: a CGEventTap shim that captures `kCGMouseEventDeltaX/Y` and injects `WM_INPUT`
- Or: the WarChaos team adding a `+i_mouse_accel 0` / raw input bypass in the engine

### Other minor issues
- **Multi-monitor:** macOS 27 beta has window management bugs with 3 monitors
- **Fullscreen:** Captures all monitors (Windows-style), use windowed mode
- **Steam API:** `SteamAPI_Init() failed` (normal, no Steam runtime)
- **Discord SDK:** `Failed to create Discord SDK. Error code: 4` (non-critical)
- **Battle Pass:** Some endpoints timeout (server-side)

---

## Setup Guide

### Prerequisites
- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 14+ (tested on 27 beta)
- ~65 GB free disk
- Admin account

### Quick Start
```bash
git clone <this-repo>
cd warchaos-apple-silicon
./setup.sh
```

`setup.sh` does:
1. Installs Rosetta 2
2. Downloads Wine 11.10 Staging (Gcenx prebuilt, ~181 MB)
3. Creates a dedicated Wine prefix at `~/WarChaos-wine`
4. Downloads Microsoft ICU 72 and builds the `icu.dll` forwarder shim
5. Applies all required registry fixes

### Running the Game
```bash
source scripts/env.sh
cd ~/Desktop/Warface/WarChaos
"$WINE" "Bin64Release/WarChaos Begins.exe"
```

### Environment Variables (scripts/env.sh)
```bash
export WINE="/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/WarChaos-wine"
export WINEESYNC=1
export ROSETTA_ADVERTISE_AVX=1
export WINEDEBUG=-all

# Qt 6 launcher fixes
export QT_QPA_PLATFORM="windows:darkmode=0"     # Avoids UISettings COM crash
export QT_AUTO_SCREEN_SCALE_FACTOR=0             # Avoids DPI awareness failure
export QT_ENABLE_HIGHDPI_SCALING=0
export QSG_RHI_BACKEND=opengl                    # Software & D3D11 backends fail under Wine
export QT_OPENGL=desktop

# .NET installer fixes
export DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU=72.1.0.3
```

### Registry Keys Applied
```
HKCU\Software\Wine\Direct3D: OffscreenRenderingMode = backbuffer
HKCU\Software\Wine\Mac Driver: Decorated = Y
HKCU\Software\Microsoft\Avalon.Graphics: DisableHWAcceleration = 1
```

---

## Technical Deep Dive

### Why GPTK Wine 7.7 doesn't work
The official Game Porting Toolkit ships Wine 7.7 (2022). This is too old for Qt 6:
- Qt 6's `qwindows.dll` platform plugin crashes during COM/UIAutomation init
- `Windows.UI.ViewManagement.UISettings` activation fails (dark mode detection)
- Repeated `0x6BA` (RPC_S_SERVER_UNAVAILABLE) exceptions → C++ abort

### Why Homebrew x86_64 doesn't work on macOS 27
The Command Line Tools on macOS 27 removed the x86_64 slice of `libxcrun`:
```
xcrun: error: unable to load libxcrun
  (have 'arm64,arm64e', need 'x86_64')
```
This breaks `git` under Rosetta, which breaks Homebrew x86_64 installation.
**Solution:** Use Gcenx prebuilt Wine (no compilation needed).

### Why the launcher was invisible
The Qt 6 launcher creates a **borderless window** (`WS_EX_LAYERED`). On macOS 27 beta,
`winemac.drv` doesn't composite borderless windows on screen (they exist in Mission Control
but not on the desktop).

**Fix:** `Decorated=Y` forces native macOS window decorations, which winemac presents reliably.

### Why the launcher content was white/empty
The Qt Quick scenegraph tried multiple render backends:
1. **Software (backend 3):** `Failed to create RHI`
2. **D3D11:** `D3D11 smoke test: Failed to create vertex shader`
3. **OpenGL (backend 2):** ✅ Works — Wine implements OpenGL well

**Fix:** `QSG_RHI_BACKEND=opengl`

### Why the game had GL_INVALID_FRAMEBUFFER_OPERATION
Wine's default offscreen rendering mode uses FBOs that fail on macOS:
```
err:d3d:wined3d_check_gl_call >>>>>>> GL_INVALID_FRAMEBUFFER_OPERATION (0x506) from glClear
```

**Fix:** `OffscreenRenderingMode=backbuffer`

### The ICU Forwarder Shim
The game ships `Bin64Release/icuuc.dll` — a **forwarder** that redirects all ICU calls to
a combined `icu.dll` (which exists on real Windows but not in Wine).

We built a custom `icu.dll` that re-exports all 542 function names (unversioned) and
forwards them to the versioned exports in Microsoft's ICU 72 (`icuuc72.dll`/`icuin72.dll`).

Built with: `lld-link /DLL /NOENTRY /MACHINE:X64 /DEF:icu.def stub.obj /OUT:icu.dll`

---

## All Errors Encountered & Fixes

| # | Error | Cause | Fix |
|---|-------|-------|-----|
| 1 | `arch: Bad CPU type in executable` | Rosetta 2 not installed | `softwareupdate --install-rosetta` |
| 2 | `xcrun: missing compatible architecture (have 'arm64,arm64e', need 'x86_64')` | macOS 27 CLT no x86_64 slice | Use Gcenx prebuilt Wine (skip Homebrew x86) |
| 3 | `CultureNotFoundException: 'en' is an invalid culture identifier` | .NET can't find ICU | Install real ICU + `DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU` |
| 4 | `Cannot find non-neutral culture related to 'en-us'` | Used invariant mode; WPF binding needs real cultures | Use real ICU (not invariant) |
| 5 | `COMException (0x88980406)` in WPF | WPF hardware rendering fails under Wine | `DisableHWAcceleration=1` |
| 6 | `find_forwarded_export module not found for forward 'icu.ucnv_open'` | Game's `icuuc.dll` forwards to missing `icu.dll` | Build `icu.dll` forwarder shim |
| 7 | `Wine C++ Runtime Library` abort after `qwindows.dll` | Qt 6 dark mode detection crashes (UISettings COM) | `QT_QPA_PLATFORM=windows:darkmode=0` |
| 8 | `SetProcessDpiAwarenessContext() failed: Acesso negado` | Qt DPI awareness fails under Wine | `QT_AUTO_SCREEN_SCALE_FACTOR=0` |
| 9 | `Failed to create RHI (backend 3)` | Qt software render backend fails | `QSG_RHI_BACKEND=opengl` |
| 10 | `D3D11 smoke test: Failed to create vertex shader` | Qt D3D11 backend fails under Wine | `QSG_RHI_BACKEND=opengl` |
| 11 | `GL_INVALID_FRAMEBUFFER_OPERATION (0x506) from glClear` | Wine FBO offscreen rendering broken on macOS | `OffscreenRenderingMode=backbuffer` |
| 12 | Window exists but invisible (Mission Control shows it) | Borderless windows not composited on macOS 27 beta | `Decorated=Y` |
| 13 | Game client doesn't launch via `open`/app bundle | App bundle environment restricts child process | Launch directly from terminal |
| 14 | Mouse FPS camera unresponsive (2s delay on flicks) | winemac.drv doesn't implement relative mouse input (RID) | **UNRESOLVED** — see below |

---

## The Mouse Problem

### Symptom
In FPS mouselook: slow movements work, fast movements (flicks) are ignored. The cursor
feels like it has ~2 seconds of latency before responding to direction changes.

### Root Cause
`winemac.drv` only delivers `WM_MOUSEMOVE` with **absolute cursor position**. FPS games
call `RegisterRawInputDevices` expecting `WM_INPUT` messages with **relative deltas**
(`RAWMOUSE.lLastX`/`lLastY`). The Wine `user32` has all the RID API stubs, but the macOS
backend never generates the actual delta events.

On real Windows, the mouse driver reports raw deltas via HID. On macOS, the Core Graphics
events DO contain delta fields (`kCGMouseEventDeltaX`/`kCGMouseEventDeltaY`), but
`winemac.drv` ignores them and only reads `CGEventGetLocation`.

### What We Tried
| Attempt | Result |
|---------|--------|
| `MouseWarpOverride=force` | Worse — warp suppression eats events |
| `DisableExclusiveMode=Y` | No change |
| `UseConfinementCursorClipping=N` | No change |
| `EnableRawInput=Y` + `UseRawInput=Y` | No change (user32 has stubs but driver doesn't feed them) |
| macOS Input Monitoring permission | Minor improvement, not enough |
| `i_mouse=3` / `i_mouse_raw=1` in CryEngine autoexec | No change (engine calls RID, driver still doesn't deliver) |
| `GrabFullscreen=Y` | No change |

### Possible Solutions (for the community)

**Option A: CrossOver (paid, trial available)**
CrossOver has a proprietary `winemac.drv` with full RID support. FPS games work natively.
This is what most Mac gamers use for competitive FPS titles.

**Option B: CGEventTap Shim**
A `DYLD_INSERT_LIBRARIES` dylib that:
1. Creates a CGEventTap capturing `kCGEventMouseMoved`
2. Reads `kCGMouseEventDeltaX`/`kCGMouseEventDeltaY`
3. Posts `WM_INPUT` messages to the focused Wine window
Requires Accessibility permission. The challenge is that the shim runs in the host process
(arm64) while Wine runs x86_64 under Rosetta — they can't share memory directly.

**Option C: Patch winemac.drv**
Modify `dlls/winemac.drv/mouse.c` in Wine source to:
1. Read `CGEventGetIntegerValueField(event, kCGMouseEventDeltaX/Y)` in the mouse moved handler
2. Accumulate deltas
3. Generate `WM_INPUT` messages via `NtUserSendHardwareInput` with `RIM_TYPEMOUSE`
Requires compiling Wine from source (~2 hours on M4).

**Option D: WarChaos engine patch**
If the WarChaos team can add a cvar like `i_mouse_raw_input 0` that falls back to
`GetCursorPos`-based mouselook (bypassing `RegisterRawInputDevices`), the game would
work on all Wine versions without RID support.

---

## Repository Files

```
warchaos-apple-silicon/
├── README.md                          # Quick start guide
├── WARCHAOS_MACOS_FULL_GUIDE.md       # This document
├── setup.sh                           # One-shot automated setup
├── LICENSE                            # MIT
├── .gitignore
├── artifacts/
│   ├── icu.def                        # ICU forwarder definitions (542 exports)
│   └── icu.dll                        # Prebuilt ICU forwarder shim
└── scripts/
    ├── env.sh                         # Environment variables (source before running)
    ├── launch.sh                      # Launch the game
    └── build-icu-shim.sh              # Rebuild the ICU forwarder DLL
```

### Key Paths
| Path | Purpose |
|------|---------|
| `~/WarChaos-wine/` | Wine prefix |
| `~/Desktop/Warface/WarChaos/` | Game installation |
| `~/Desktop/WarChaosLauncher.app/` | Standalone launcher (for TCC permissions) |
| `/Applications/Wine Staging.app/` | Wine 11.10 Staging |
| `/tmp/wc-*.log` | Debug logs from various sessions |

---

## Next Steps for the Community

1. **Mouse fix is the #1 priority.** Without it, the game is not competitively playable.
   Options ranked by feasibility:
   - CrossOver trial (5 minutes, guaranteed to work)
   - CGEventTap shim (a few hours of dev)
   - Patch winemac.drv (compile Wine, ~2 hours)
   - WarChaos engine patch (ask the devs)

2. **Test on macOS 26 (stable).** macOS 27 beta has window management bugs that may not
   exist on stable releases. The `Decorated=Y` workaround may not be needed.

3. **Performance benchmarking.** Once mouse works, test FPS with `MTL_HUD_ENABLED=1`.
   CryEngine → D3DMetal performance on M4 should be good but needs measurement.

4. **Anti-cheat verification.** The `ClientProtection` system did not block us, but
   confirm with WarChaos staff that playing via Wine is allowed.

5. **Share this guide.** The repo is ready to push to GitHub. Let the WarChaos Discord
   know so other Mac users can benefit.

---

## Credits
- [Wine](https://www.winehq.org/) — Windows API translation
- [Gcenx macOS Wine Builds](https://github.com/Gcenx/macOS_Wine_builds) — Prebuilt Wine for macOS
- [Microsoft ICU](https://www.nuget.org/packages/Microsoft.ICU.ICU4C.Runtime) — ICU for .NET
- [Apple Game Porting Toolkit](https://developer.apple.com/games/) — D3DMetal
- WarChaos team — the game

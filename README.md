# WarChaos on Apple Silicon (macOS)

Community guide + scripts to run **WarChaos** (a CryEngine / Warface-based game, Windows-only)
on **Apple Silicon Macs (M1–M4)** using Apple's **Game Porting Toolkit (D3DMetal)** + **Wine**.

There is no native macOS build. This works by stacking three translation layers:

| Layer | What it translates |
|-------|--------------------|
| **Wine** | Windows `.exe` / `.dll` → macOS (API translation, *not* emulation) |
| **Rosetta 2** | x86-64 instructions → Apple ARM |
| **D3DMetal** (Game Porting Toolkit) | DirectX 11/12 → Metal |

> **Status:** ⚠️ Partial. The Windows installer runs and the **full game downloads &
> installs (~29 GB)** on Apple Silicon. The **game launcher (`WarChaos Begins.exe`,
> Qt 6) currently crashes during start-up** under the Game Porting Toolkit's Wine 7.7.
> See [Status & limitations](#status--limitations) for the exact blocker — this is the
> part where help from the WarChaos team would unlock everything.

---

## ⚠️ Disclaimer

- Unofficial, community-made guide. **Not affiliated** with the WarChaos team, Crytek or MY.GAMES.
- WarChaos is an **online game**. Online titles often run anti-cheat that may flag or ban
  Wine / translation layers. **Ask the WarChaos staff whether playing via Wine is allowed
  before going online.** Use at your own risk.
- Tested on: **Mac (Apple M4), macOS 27.0**. Should also work on macOS 14 (Sonoma) and newer.

---

## Requirements

- Apple Silicon Mac (M1 / M2 / M3 / M4)
- macOS 14 (Sonoma) or newer
- **~65 GB free disk** (the game download is ~31 GB; allow headroom for temp files)
- An admin account (needed for Rosetta and copying the toolkit into `/Applications`)

---

## Quick start

```bash
git clone <this-repo>
cd warchaos-apple-silicon
./setup.sh
```

`setup.sh` installs Rosetta 2, the Game Porting Toolkit, a dedicated Wine prefix, a real
ICU for .NET, and the WPF software-render fix. Then:

```bash
# 1) run the WarChaos installer inside the prefix
source scripts/env.sh
"$WINE" /path/to/WarChaosInstaller.exe      # default install target: ~/Desktop/Warface/WarChaos

# 2) after the game is installed, build the icu.dll shim the native client needs
./scripts/build-icu-shim.sh

# 3) launch (NOTE: the Qt 6 launcher currently crashes at start-up — see Status below)
./scripts/launch.sh
```

---

## What `setup.sh` does (and why)

### 1. Rosetta 2
The toolkit's wine is an x86-64 binary, so Rosetta 2 must be present:
```bash
softwareupdate --install-rosetta --agree-to-license
```

### 2. Game Porting Toolkit — the *prebuilt* (Gcenx) way
The "official" route is `brew install apple/apple/game-porting-toolkit`, which builds a
custom wine under an **x86-64 Homebrew**. **On macOS 26 (Tahoe) / 27 this no longer works:**
the Command Line Tools stopped shipping an **x86-64 slice of `libxcrun`**, so `git`/Homebrew
can't run under Rosetta and the formula fails with:

```
xcrun: error: unable to load libxcrun (... missing compatible architecture (have 'arm64,arm64e', need 'x86_64'))
```

Instead we use **[Gcenx's prebuilt Game Porting Toolkit](https://github.com/Gcenx/game-porting-toolkit)**
— a ready-made `Game Porting Toolkit.app` (wine 7.7 + D3DMetal) that just runs under Rosetta.
We download it, move it to `/Applications`, strip quarantine and ad-hoc re-sign it.

### 3. Wine prefix
A dedicated prefix at `~/WarChaos-wine` keeps everything isolated. Initialized with
`ROSETTA_ADVERTISE_AVX=1` (CryEngine needs AVX) and `WINEESYNC=1`.
> The GPTK wine is **64-bit only** — fine here, because both the installer and the game
> executables are 64-bit (PE32+).

### 4. Real ICU for .NET globalization
The WarChaos **installer is a self-contained .NET 10 WPF app**. .NET needs ICU for culture
data; under Wine it isn't found, so we drop a real ICU (Microsoft's `Microsoft.ICU.ICU4C`
72) into the prefix and enable **app-local ICU** via
`DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU=72.1.0.3`.

### 5. WPF software rendering
WPF's hardware (Direct3D) renderer throws `COMException 0x88980406` under Wine. We force
software rendering with the registry key
`HKCU\Software\Microsoft\Avalon.Graphics\DisableHWAcceleration = 1`.

---

## Troubleshooting

Every error we actually hit, and the fix:

| Symptom | Cause | Fix |
|--------|-------|-----|
| `arch: Bad CPU type in executable` | Rosetta 2 not installed | `softwareupdate --install-rosetta --agree-to-license` |
| Homebrew x86-64 install dies: `xcrun ... missing ... x86_64` | macOS 26/27 CLT has no x86-64 `libxcrun` | Don't build via Homebrew — use the **Gcenx prebuilt GPTK** (step 2) |
| Whisky won't download its wine (`data.getwhisky.app` 404) | Whisky was discontinued; its CDN is offline | Use GPTK (Gcenx) instead of Whisky |
| Installer: `CultureNotFoundException: 'en' is an invalid culture identifier` | .NET can't find ICU | Install ICU + `DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU` (step 4) |
| Installer: `Cannot find non-neutral culture related to 'en-us'` | You used `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`; WPF binding needs real cultures | Use **real ICU** instead of invariant mode |
| Installer: `COMException (0x88980406)` in `HwndTarget` / `DUCE.Channel` | WPF hardware rendering fails under Wine | `DisableHWAcceleration=1` (step 5) |
| `preloader: Warning: failed to reserve range ...` | Benign Rosetta/GPTK memory warnings | Ignore |
| `wine: failed to start ...syswow64...` | 64-bit-only wine has no 32-bit (WoW64) | Ignore (installer & game are 64-bit) |
| Game exits instantly, code 3, log shows `find_forwarded_export ... icuuc.dll` | Native client needs a Windows `icu.dll` | Run `scripts/build-icu-shim.sh` |
| Launcher shows **"Wine C++ Runtime Library"** abort after `qwindows.dll` | Qt 6 platform-plugin / COM init fails on Wine 7.7 | **Open blocker** — needs newer Wine (CrossOver/newer GPTK). See Status |

Handy commands:
```bash
source scripts/env.sh
"$WINESERVER" -k          # hard-stop everything in the prefix
MTL_HUD_ENABLED=1 ./scripts/launch.sh   # show a Metal FPS/perf overlay
```

---

## Status & limitations

What works on Apple Silicon (verified on M4 / macOS 27):

- ✅ Rosetta 2 + Game Porting Toolkit (Gcenx, Wine 7.7 + D3DMetal) + Wine prefix.
- ✅ The `.NET 10` WPF installer runs (after the **real-ICU** + **WPF software-render** fixes).
- ✅ It downloads & assembles the **full ~29 GB game** into `~/Desktop/Warface/WarChaos`.
- ✅ The native game's ICU dependency is solved with a generated `icu.dll` shim
  (`scripts/build-icu-shim.sh`) → `Qt6Core` loads and `WarChaos Begins.exe` starts.

### ❌ Current blocker: the Qt 6 launcher crashes during start-up

After the ICU fix, `WarChaos Begins.exe` (the Qt 6 / QML login launcher — class
`LauncherBackend`, with account + Discord login) gets a bit further and then dies with a
**"Wine C++ Runtime Library"** abort. Module load order before the crash:

```
Qt6Core → Qt6Gui → Qt6Network → Qt6Qml → Qt6Quick → Qt6Multimedia → qwindows.dll → 💥
```

- It crashes **right after `qwindows.dll`** (the Qt Windows platform plugin) initializes,
  which pulls in `opengl32` / `wined3d` / `d3d9`.
- `WINEDEBUG=+seh` shows repeated **`0x6BA` (RPC_S_SERVER_UNAVAILABLE)** exceptions plus a
  failed `Windows.UI.ViewManagement.UISettings` COM activation (Qt's COM/UIAutomation /
  accessibility bridge) before the abort.
- It is **independent of the Qt render backend** — `QT_QUICK_BACKEND=software`,
  `QSG_RHI_BACKEND=d3d11`, and `QT_ACCESSIBILITY=0` all crash identically.

**Most likely cause:** the Game Porting Toolkit ships **Wine 7.7 (2022)**, which is too old
for this modern Qt 6 build's `qwindows` platform plugin / COM init.

**Things that would unlock it (help wanted):**
- A **newer Wine** with D3DMetal — e.g. **CrossOver 24+** or a newer GPTK build. This is the
  single most promising next step.
- From the **WarChaos team**: a launcher flag to skip the Qt UI and run the client directly,
  a Wine-compatible launcher build, or guidance on the start-up COM/RPC calls.

### Other unknowns
- **Anti-cheat:** the client contains a **`ClientProtection`** system. Even once the launcher
  runs, online play may be flagged/blocked under Wine. **Confirm with WarChaos staff.**
- **In-game rendering / FPS (CryEngine → D3DMetal):** not reached yet (gated by the launcher).

If you get past the launcher (or hit new errors/fixes), please open an issue or PR so we can
keep this guide accurate for the whole Apple Silicon community. 🙌

---

## Credits

- [Apple Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) (D3DMetal)
- [Gcenx](https://github.com/Gcenx/game-porting-toolkit) — prebuilt GPTK for Apple Silicon
- [Wine](https://www.winehq.org/)
- [Microsoft.ICU.ICU4C](https://www.nuget.org/packages/Microsoft.ICU.ICU4C.Runtime) — ICU for .NET

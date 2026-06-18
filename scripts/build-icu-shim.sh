#!/bin/bash
# ===========================================================================
# Build the combined `icu.dll` that the native game/launcher needs.
#
# The game ships Bin64Release/icuuc.dll as a *forwarder* to a Windows-style
# combined `icu.dll` (which only exists on real Windows). Wine has no icu.dll,
# so Qt6Core fails to load and "WarChaos Begins.exe" exits (code 3).
#
# This script builds a tiny `icu.dll` that re-exports every name the game's
# icuuc.dll forwards, pointing each UNVERSIONED name to the VERSIONED export
# in Microsoft's ICU 72 (icuuc72/icuin72). It is installed into the prefix's
# system32. The game folder is left untouched.
#
# Requires: python3, Homebrew `lld` (lld-link), clang (Xcode CLT).
# ===========================================================================
set -euo pipefail

ICU_VER="72.1.0.3"; ICU_MAJOR="72"
ICU_URL="https://api.nuget.org/v3-flatcontainer/microsoft.icu.icu4c.runtime.win-x64/${ICU_VER}/microsoft.icu.icu4c.runtime.win-x64.${ICU_VER}.nupkg"

export WINEPREFIX="${WINEPREFIX:-$HOME/WarChaos-wine}"
GAME_DIR="${GAME_DIR:-$HOME/Desktop/Warface/WarChaos}"
GAME_ICUUC="$GAME_DIR/Bin64Release/icuuc.dll"
SYS32="$WINEPREFIX/drive_c/windows/system32"
WORK="$(mktemp -d)"

command -v lld-link >/dev/null || { echo "Installing lld (provides lld-link)..."; brew install lld; }
command -v lld-link >/dev/null || export PATH="/opt/homebrew/opt/lld/bin:$PATH"
[ -f "$GAME_ICUUC" ] || { echo "Game icuuc.dll not found at $GAME_ICUUC (install the game first)."; exit 1; }

echo "==> Fetching real ICU $ICU_VER"
curl -fL --retry 3 -o "$WORK/icu.nupkg" "$ICU_URL"
unzip -o -j "$WORK/icu.nupkg" \
  "runtimes/win-x64/native/icuuc${ICU_MAJOR}.dll" \
  "runtimes/win-x64/native/icuin${ICU_MAJOR}.dll" \
  "runtimes/win-x64/native/icudt${ICU_MAJOR}.dll" -d "$WORK" >/dev/null
cp "$WORK"/icu*${ICU_MAJOR}.dll "$SYS32/"     # real impls + data (forward targets)

echo "==> Generating forwarder .def from the game's icuuc.dll export table"
python3 - "$GAME_ICUUC" "$WORK/icuuc${ICU_MAJOR}.dll" "$WORK/icuin${ICU_MAJOR}.dll" "$WORK/icu.def" <<'PY'
import struct, sys
def export_names(path):
    d=open(path,'rb').read(); e=struct.unpack_from('<I',d,0x3C)[0]; coff=e+4
    nsec,=struct.unpack_from('<H',d,coff+2); opt=coff+20; magic,=struct.unpack_from('<H',d,opt)
    edir_rva,_=struct.unpack_from('<II',d,opt+112); sh=opt+(240 if magic==0x20b else 224); secs=[]
    for i in range(nsec):
        o=sh+i*40; vsz,vaddr,rsz,raddr=struct.unpack_from('<IIII',d,o+8); secs.append((vaddr,vsz,raddr,rsz))
    def r2o(rva):
        for vaddr,vsz,raddr,rsz in secs:
            if vaddr<=rva<vaddr+max(vsz,rsz): return raddr+(rva-vaddr)
    o=r2o(edir_rva); n,=struct.unpack_from('<I',d,o+24); nr,=struct.unpack_from('<I',d,o+32)
    no=r2o(nr); out=[]
    for i in range(n):
        a,=struct.unpack_from('<I',d,no+i*4); so=r2o(a); out.append(d[so:d.index(b'\0',so)].decode('latin1'))
    return out
game, uc_p, in_p, defout = sys.argv[1:5]
needed=export_names(game); uc=set(export_names(uc_p)); inn=set(export_names(in_p))
lines=["LIBRARY icu","EXPORTS"]; miss=[]
for nm in needed:
    if nm+"_72" in uc: lines.append(f"    {nm}=icuuc72.{nm}_72")
    elif nm+"_72" in inn: lines.append(f"    {nm}=icuin72.{nm}_72")
    elif nm in uc: lines.append(f"    {nm}=icuuc72.{nm}")
    else: miss.append(nm)
open(defout,'w').write("\n".join(lines)+"\n")
print(f"   mapped {len(lines)-2}/{len(needed)} exports; unmapped: {miss}")
PY

echo "==> Linking icu.dll forwarder (lld-link)"
printf 'int _stub(void){return 0;}\n' > "$WORK/stub.c"
clang --target=x86_64-pc-windows-msvc -c "$WORK/stub.c" -o "$WORK/stub.obj"
lld-link /DLL /NOENTRY /MACHINE:X64 /DEF:"$WORK/icu.def" "$WORK/stub.obj" /OUT:"$WORK/icu.dll"
cp "$WORK/icu.dll" "$SYS32/icu.dll"
echo "==> Installed: $SYS32/icu.dll  (forwards to icuuc72/icuin72)"
rm -rf "$WORK"

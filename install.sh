#!/bin/bash
# ===========================================================================
# WarChaos no Apple Silicon — Installer interativo
#
# Uso: ./install.sh
#
# Pede sudo no início, verifica/pergunta cada passo, e no final cria um
# lançador executável na Área de Trabalho com tudo configurado:
#   - Rosetta 2
#   - Wine 11.10 Staging (Gcenx prebuilt)
#   - Wine prefix dedicado
#   - ICU real + shim forwarder icu.dll
#   - Registry fixes (Direct3D, Decorated, WPF, RawInput)
#   - winemac.drv patcheado (fix do mouse FPS) — compilado e instalado
#   - Monitor 144hz como principal (opcional, se detectar monitor externo)
#   - Download + instalação do jogo (launcher baixa ~29 GB do CDN)
#   - Lançador ~/Desktop/WarChaos.command (double-clickable)
# ===========================================================================
set -euo pipefail

# --- Cores ------------------------------------------------------------------
C="\033[1;36m"   # cyan = step
G="\033[1;32m"   # green = done/ok
Y="\033[1;33m"   # yellow = pergunta
R="\033[1;31m"   # red = erro
B="\033[0;90m"   # gray = info
N="\033[0m"      # reset

say()  { printf "\n${C}==> %s${N}\n" "$*"; }
ok()   { printf "  ${G}✓${N} %s\n" "$*"; }
info() { printf "  ${B}%s${N}\n" "$*"; }
err()  { printf "  ${R}✗ %s${N}\n" "$*"; }
ask()  { printf "${Y}%s${N} " "$*"; read -r ans; }

# --- Sudo upfront -----------------------------------------------------------
say "Solicitando sudo (necessário para Rosetta, codesign, /Applications)"
sudo -v || { err "sudo necessário. Execute novamente."; exit 1; }
# Mantém sudo vivo em background
( while true; do sudo -n true; sleep 60; done 2>/dev/null ) &
SUDO_KEEPER=$!
trap 'kill $SUDO_KEEPER 2>/dev/null || true' EXIT

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# --- Helpers ----------------------------------------------------------------
has()  { command -v "$1" >/dev/null 2>&1; }
check_arch() {
  [ "$(uname -m)" = "arm64" ] || { err "Este installer é para Apple Silicon (arm64)."; exit 1; }
}

# --- 1. Rosetta 2 -----------------------------------------------------------
say "Passo 1/9: Rosetta 2"
if arch -x86_64 /bin/bash -c 'exit 0' 2>/dev/null; then
  ok "Rosetta 2 já instalado"
else
  info "Instalando Rosetta 2..."
  sudo softwareupdate --install-rosetta --agree-to-license
  ok "Rosetta 2 instalado"
fi

# --- 2. Homebrew ------------------------------------------------------------
say "Passo 2/9: Homebrew"
if has brew; then
  ok "Homebrew presente ($(brew --version | head -1))"
else
  ask "Homebrew não encontrado. Instalar agora? [S/n]"
  [ "${ans:-s}" != "n" ] || { err "Homebrew é necessário. Instale manualmente: https://brew.sh"; exit 1; }
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew instalado"
fi

# Deps que vamos precisar (instalar silenciosamente se faltarem)
BREW_DEPS=""
has git      || BREW_DEPS="$BREW_DEPS git"
has patch    || BREW_DEPS="$BREW_DEPS patch"
has lld-link || BREW_DEPS="$BREW_DEPS lld"
[ -x /opt/homebrew/opt/bison/bin/bison ] || BREW_DEPS="$BREW_DEPS bison"
has x86_64-w64-mingw32-gcc || BREW_DEPS="$BREW_DEPS mingw-w64"
has displayplacer || BREW_DEPS="$BREW_DEPS displayplacer"
if [ -n "$BREW_DEPS" ]; then
  say "Instalando dependências via Homebrew:${BREW_DEPS}"
  brew install $BREW_DEPS 2>&1 | tail -3 || true
  ok "Dependências instaladas"
fi

# --- 3. Wine 11.10 Staging (Gcenx) ------------------------------------------
say "Passo 3/9: Wine 11.10 Staging (Gcenx prebuilt)"
WINE_APP="/Applications/Wine Staging.app"
WINE="$WINE_APP/Contents/Resources/wine/bin/wine"
WINESERVER="$WINE_APP/Contents/Resources/wine/bin/wineserver"
WINE_VER="11.10"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VER}/wine-staging-${WINE_VER}-osx64.tar.xz"

if [ -x "$WINE" ]; then
  ok "Wine já instalado ($("$WINE" --version 2>/dev/null | head -1))"
else
  info "Baixando Wine ${WINE_VER} (~181 MB)..."
  curl -fL --retry 3 -o /tmp/wine.tar.xz "$WINE_URL"
  rm -rf /tmp/wine-extract && mkdir -p /tmp/wine-extract
  tar -xJf /tmp/wine.tar.xz -C /tmp/wine-extract
  sudo rm -rf "$WINE_APP"
  sudo mv "/tmp/wine-extract/Wine Staging.app" /Applications/
  sudo xattr -drs com.apple.quarantine "$WINE_APP"
  sudo codesign --force --deep -s - "$WINE_APP"
  ok "Wine ${WINE_VER} instalado"
fi

export WINEPREFIX="${WINEPREFIX:-$HOME/WarChaos-wine}"
export WINEESYNC=1 ROSETTA_ADVERTISE_AVX=1 WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="

# --- 4. Wine prefix ---------------------------------------------------------
say "Passo 4/9: Wine prefix em $WINEPREFIX"
if [ -f "$WINEPREFIX/system.reg" ]; then
  ok "Prefix já existe"
else
  info "Criando prefix..."
  "$WINE" wineboot --init 2>&1 | tail -3
  ok "Prefix criado"
fi

# --- 5. ICU + shim ----------------------------------------------------------
say "Passo 5/9: ICU 72 + shim forwarder icu.dll"
SYS32="$WINEPREFIX/drive_c/windows/system32"
ICU_MAJOR="72"
if [ -f "$SYS32/icuuc${ICU_MAJOR}.dll" ]; then
  ok "ICU já presente"
else
  info "Baixando Microsoft ICU 72..."
  ICU_URL="https://api.nuget.org/v3-flatcontainer/microsoft.icu.icu4c.runtime.win-x64/72.1.0.3/microsoft.icu.icu4c.runtime.win-x64.72.1.0.3.nupkg"
  curl -fL --retry 3 -o /tmp/icu.nupkg "$ICU_URL"
  rm -rf /tmp/icuout && mkdir -p /tmp/icuout
  unzip -o -j /tmp/icu.nupkg \
    "runtimes/win-x64/native/icuuc${ICU_MAJOR}.dll" \
    "runtimes/win-x64/native/icuin${ICU_MAJOR}.dll" \
    "runtimes/win-x64/native/icudt${ICU_MAJOR}.dll" -d /tmp/icuout >/dev/null
  cp /tmp/icuout/icu*${ICU_MAJOR}.dll "$SYS32/"
  ok "ICU instalado"
fi

if [ -f "$SYS32/icu.dll" ]; then
  ok "Shim icu.dll já presente"
else
  info "Construindo shim icu.dll..."
  bash "$REPO_ROOT/scripts/build-icu-shim.sh" 2>&1 | tail -3
  ok "Shim icu.dll construído"
fi

# --- 6. Registry fixes ------------------------------------------------------
say "Passo 6/9: Registry fixes"
"$WINE" reg add "HKCU\\Software\\Wine\\Direct3D" \
  /v OffscreenRenderingMode /t REG_SZ /d backbuffer /f >/dev/null 2>&1
"$WINE" reg add "HKCU\\Software\\Wine\\Mac Driver" \
  /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1
"$WINE" reg add "HKCU\\Software\\Wine\\Mac Driver" \
  /v RawInput /t REG_SZ /d Y /f >/dev/null 2>&1
"$WINE" reg add "HKCU\\Software\\Microsoft\\Avalon.Graphics" \
  /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1
ok "Registry configurado (Direct3D, Decorated, RawInput, WPF)"

# --- 7. Patch do mouse (winemac.drv raw input) ------------------------------
say "Passo 7/9: Patch do mouse FPS (winemac.drv raw input)"
WINEMAC_SO="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"

if nm "$WINEMAC_SO" 2>/dev/null | grep -q use_raw_input; then
  ok "winemac.so já está patcheado (símbolo use_raw_input presente)"
else
  ask "Compilar e instalar o patch do mouse? Recomendado — resolve o lag no mouselook FPS. [S/n]"
  if [ "${ans:-s}" != "n" ]; then
    info "Compilando winemac.drv patcheado (~20-40 min no M4)..."
    bash "$REPO_ROOT/scripts/build-wine-mac-rawinput.sh" 2>&1 | tail -20
    if nm "$WINEMAC_SO" 2>/dev/null | grep -q use_raw_input; then
      ok "Patch instalado e ativo"
    else
      err "Build falhou ou não instalou. Veja o log acima."
      info "O jogo funciona sem o patch, mas o mouselook FPS terá lag."
      info "Você pode rodar ./scripts/build-wine-mac-rawinput.sh depois."
    fi
  else
    info "Patch pulado. Mouse FPS terá lag sem ele."
    info "Para instalar depois: ./scripts/build-wine-mac-rawinput.sh"
  fi
fi

# --- 8. Monitor 144hz + lançador --------------------------------------------
say "Passo 8/9: Monitor e lançador"

# Detectar monitores externos
if has displayplacer; then
  EXTERNAL_COUNT=$(displayplacer list 2>/dev/null | grep -c 'external screen')
  if [ "$EXTERNAL_COUNT" -gt 0 ]; then
    info "Monitores detectados:"
    displayplacer list 2>/dev/null | grep -E 'Type:|Resolution:|Hertz:|Origin:' | sed 's/^/    /'

    HIGH_HZ_ID=$(displayplacer list 2>/dev/null | awk '
      /^Persistent screen id:/{id=$4}
      /^Hertz:/{hz=$2}
      /^Type:/{type=$0}
      /^Origin:/{if(hz+0>60 && type !~ /built/) print id}
    ' | head -1)

    if [ -n "$HIGH_HZ_ID" ]; then
      HIGH_HZ=$(displayplacer list 2>/dev/null | awk -v id="$HIGH_HZ_ID" '
        /^Persistent screen id:/{cur=$4}
        /^Hertz:/{if(cur==id) print $2}
      ')
      ask "Monitor ${HIGH_HZ}hz detectado (id ${HIGH_HZ_ID:0:8}...). Configurar como principal para o jogo? [S/n]"
      if [ "${ans:-s}" != "n" ]; then
        # Salvar config atual e aplicar
        displayplacer list 2>/dev/null | grep '^displayplacer ' > /tmp/wc-display-restore.txt
        # Reescrever set-gaming-monitor.sh com o ID detectado
        "$REPO_ROOT/scripts/set-gaming-monitor.sh" 2>/dev/null || true
        # Aplicar diretamente: colocar o high-hz em (0,0)
        info "Aplicando layout..."
        # Construir comando displayplacer com o monitor high-hz em (0,0)
        displayplacer list 2>/dev/null | awk -v target="$HIGH_HZ_ID" '
          BEGIN { cmd="displayplacer" }
          /^Persistent screen id:/{id=$4; spec=""}
          /^Resolution:/{res=$2}
          /^Hertz:/{hz=$2}
          /^Color Depth:/{cd=$3}
          /^Scaling:/{sc=$2}
          /^Origin:/{split($2,a,/[(,)]/); ox=a[2]; oy=a[3]}
          /^Enabled:/{en=$2}
          /^Rotation:/{rot=$2}
          /^Type:/{
            if(id==target){ nx=0; ny=0 } else { nx=ox; ny=oy }
            # lowercase scaling
            gsub(/.*/,tolower(sc),sc)
            cmd=sprintf("%s \"id:%s res:%s hz:%s color_depth:%s enabled:%s scaling:%s origin:(%s,%s) degree:%s\"", cmd, id, res, hz, cd, tolower(en), sc, nx, ny, rot)
          }
          END{ print cmd }
        ' | bash 2>/dev/null || true
        ok "Monitor ${HIGH_HZ}hz configurado como principal"
        info "Para reverter: $REPO_ROOT/scripts/set-gaming-monitor.sh -r"
      fi
    else
      info "Nenhum monitor >60hz detectado. Pulando configuração de monitor."
    fi
  else
    info "Nenhum monitor externo detectado. Pulando."
  fi
else
  info "displayplacer não disponível. Pulando configuração de monitor."
fi

# --- 9. Download e instalação do jogo ---------------------------------------
say "Passo 9/9: Instalação do jogo WarChaos"
DESKTOP="$HOME/Desktop"
LAUNCHER="$DESKTOP/WarChaos.command"
GAME_DIR="${GAME_DIR:-$HOME/Desktop/Warface/WarChaos}"
LAUNCHER_EXE="$GAME_DIR/Bin64Release/WarChaos Begins.exe"
CDN_LAUNCHER_URL="https://cdn.warchaos.xyz/files/Bin64Release/WarChaos%20Begins.exe"
MANIFEST_LAUNCHER_URL="https://cdn.warchaos.xyz/manifest/manifest-launcher.xml"
INSTALL_DIR_PARENT="$(dirname "$GAME_DIR")"

if [ -f "$LAUNCHER_EXE" ]; then
  ok "Jogo já instalado em $GAME_DIR"
else
  ask "O jogo não está instalado. Baixar e instalar agora? (~3 MB launcher + ~29 GB dados via CDN) [S/n]"
  if [ "${ans:-s}" != "n" ]; then
    # Criar a pasta do jogo
    mkdir -p "$GAME_DIR/Bin64Release"

    # Baixar o launcher (3 MB) — ele próprio faz o download dos 29 GB quando rodado
    info "Baixando launcher WarChaos Begins.exe (~3 MB)..."
    curl -fL --retry 3 -o "$LAUNCHER_EXE" "$CDN_LAUNCHER_URL"
    chmod +x "$LAUNCHER_EXE"
    ok "Launcher baixado"

    # Baixar arquivos do launcher (Launcher.pak, News.pak, QtRuntime.pak) do manifest
    info "Baixando arquivos do launcher (paks) do CDN..."
    mkdir -p "$GAME_DIR/Launcher"
    curl -sL "$MANIFEST_LAUNCHER_URL" 2>/dev/null | tr '>' '\n' | grep -oE 'url="https://cdn[^"]*"' | sed 's/url="//;s/"$//' | while read -r url; do
      # Extrair o path relativo do URL
      rel="${url#https://cdn.warchaos.xyz/files/}"
      dest="$GAME_DIR/$rel"
      mkdir -p "$(dirname "$dest")"
      info "  baixando $rel..."
      curl -fsL --retry 2 -o "$dest" "$url" 2>/dev/null || info "  (falhou, launcher vai baixar depois)"
    done
    ok "Arquivos do launcher baixados"

    # Rodar o launcher dentro do Wine — ele faz o download dos ~29 GB do jogo
    say "Abrindo launcher no Wine para download do jogo"
    info "O launcher vai abrir e baixar os ~29 GB do jogo do CDN."
    info "Faça login (Discord), escolha o diretório de instalação se pedir,"
    info "e aguarde o download completar. Pode demorar (depende da sua internet)."
    info "Quando terminar, feche o launcher."
    ask "Pressione Enter para abrir o launcher..."

    # Garantir que env.sh está sourced
    source "$REPO_ROOT/scripts/env.sh"
    cd "$GAME_DIR/Bin64Release"
    "$WINE" "./WarChaos Begins.exe" 2>&1 | tee /tmp/wc-installer.log &
    WINE_PID=$!
    info "Launcher aberto (PID $WINE_PID). Aguarde o download completar."
    info "Quando terminar, volte aqui e pressione Enter."
    wait $WINE_PID 2>/dev/null || true

    # Verificar se o jogo foi instalado
    if [ -f "$LAUNCHER_EXE" ] && [ -d "$GAME_DIR/Game" ]; then
      ok "Jogo instalado em $GAME_DIR"
    else
      info "O launcher pode não ter completado o download."
      info "Você pode reabrir com: ~/Desktop/WarChaos.command (depois de criar o atalho)"
      info "Ou: source scripts/env.sh && \"\$WINE\" \"$LAUNCHER_EXE\""
    fi
  else
    info "Download pulado."
    info "Para instalar depois, baixe o launcher de:"
    info "  $CDN_LAUNCHER_URL"
    info "Coloque em $GAME_DIR/Bin64Release/ e rode com:"
    info "  source scripts/env.sh && \"\$WINE\" \"$LAUNCHER_EXE\""
  fi
fi

# --- Lançador na Área de Trabalho -------------------------------------------
ask "Criar lançador na Área de Trabalho? [S/n]"
if [ "${ans:-s}" != "n" ]; then
  cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Lançador WarChaos — criado por install.sh
# Duplo-clique para jogar.

REPO_ROOT="$REPO_ROOT"
source "\$REPO_ROOT/scripts/env.sh"

# Monitor 144hz como principal (se configurado)
if [ -x "\$REPO_ROOT/scripts/set-gaming-monitor.sh" ]; then
  "\$REPO_ROOT/scripts/set-gaming-monitor.sh" 2>/dev/null || true
fi

GAME_DIR="${GAME_DIR}"
if [ ! -d "\$GAME_DIR" ]; then
  echo "Pasta do jogo não encontrada: \$GAME_DIR"
  echo "Execute ./install.sh novamente para baixar o jogo."
  read -p "Pressione Enter para fechar..."
  exit 1
fi

cd "\$GAME_DIR/Bin64Release"
"\$WINE" "./WarChaos Begins.exe"
EOF
  chmod +x "$LAUNCHER"
  xattr -d com.apple.quarantine "$LAUNCHER" 2>/dev/null || true
  ok "Lançador criado: $LAUNCHER"
  info "Duplo-clique para jogar."
fi

# --- Resumo -----------------------------------------------------------------
say "Instalação completa"
echo
printf "  ${G}Rosetta 2${N}          ✓\n"
printf "  ${G}Wine 11.10${N}          ✓\n"
printf "  ${G}Prefix${N}              ✓\n"
printf "  ${G}ICU + shim${N}          ✓\n"
printf "  ${G}Registry${N}            ✓\n"
if nm "$WINEMAC_SO" 2>/dev/null | grep -q use_raw_input; then
  printf "  ${G}Patch do mouse${N}     ✓\n"
else
  printf "  ${Y}Patch do mouse${N}     ⚠ não instalado (rodar build-wine-mac-rawinput.sh)\n"
fi
if [ -f "$LAUNCHER_EXE" ]; then
  printf "  ${G}Jogo${N}               ✓ $GAME_DIR\n"
else
  printf "  ${Y}Jogo${N}               ⚠ não baixado (use o launcher)\n"
fi
[ -x "$LAUNCHER" ] && printf "  ${G}Lançador${N}            ✓ $LAUNCHER\n"
echo
printf "  ${C}Para jogar:${N} duplo-clique em ~/Desktop/WarChaos.command\n"
echo

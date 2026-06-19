# WarChaos no Apple Silicon — Guia Técnico Completo

**Data:** 2026-06-18  
**Testado em:** MacBook Air M4, macOS 27 Golden Gate Developer Beta  
**Status:** 🟢 **JOGÁVEL** — Launcher 100% funcional, jogo chega ao lobby, mouselook FPS funcionando com patch de raw input (mouse USB + trackpad, monitor externo + nativo).

---

## Sumário
1. [Visão Geral](#visão-geral)
2. [O que funciona](#o-que-funciona)
3. [O que não funciona](#o-que-não-funciona)
4. [Instalação](#instalação)
5. [Mergulho Técnico](#mergulho-técnico)
6. [Erros Encontrados e Correções](#erros-encontrados-e-correções)
7. [O Problema do Mouse](#o-problema-do-mouse)
8. [Monitor 144hz](#monitor-144hz)
9. [Arquivos do Repositório](#arquivos-do-repositório)
10. [Próximos Passos](#próximos-passos)

---

## Visão Geral

WarChaos é um FPS online baseado em CryEngine (servidor privado de Warface). Não há build nativa para macOS. Este guia documenta como rodar em Apple Silicon via Wine + Rosetta 2.

**Arquitetura:**
```
WarChaos Begins.exe (launcher Qt 6 QML)
  → login (Discord OAuth2)
  → game client (CryEngine)
    → DirectX 11 → D3DMetal (ou DXVK → MoltenVK → Metal)
    → Rosetta 2 (x86-64 → ARM)
    → macOS 27
```

---

## O que funciona

| Componente | Status | Detalhe |
|------------|--------|---------|
| Rosetta 2 | ✅ | binários x86-64 rodam no M4 |
| Wine 11.10 Staging (Gcenx) | ✅ | prebuilt, não precisa de Homebrew x86 |
| Installer .NET 10 WPF | ✅ | baixa e instala os 29 GB do jogo |
| ICU Globalization | ✅ | shim forwarder `icu.dll` customizado |
| Launcher Qt 6 | ✅ | login, Discord, vídeos, todas as telas QML |
| Anti-cheat (ClientProtection) | ✅ | não bloqueia Wine |
| Game client | ✅ | CryEngine inicializa, chega ao lobby, partidas |
| Conectividade servidor | ✅ | `cdn.warchaos.xyz` + `game.warchaos.xyz` respondem |
| Lobby | ✅ | inventário, HUD, customização de armas carregam |
| Áudio | ✅ | música tema toca (decoder OGG) |
| Mouse nos menus | ✅ | cliques funcionam perfeitamente |
| Mouse no FPS (mouselook) | ✅ | com o patch de raw input (ver [O Problema do Mouse](#o-problema-do-mouse)) |

---

## O que não funciona

### Mouse FPS — residual
O patch de raw input resolveu o problema principal (~2s de lag em flicks). Funciona em:
- Monitor externo 144hz com mouse USB
- Monitor nativo (retina) com trackpad

Falhas residuais ocorrem **só durante quedas de FPS** (frame spikes) — o game loop do CryEngine não processa `WM_INPUT` a tempo e deltas se acumulam/perdem. É gargalo de render, não do patch.

### Issues menores
- **Multi-monitor:** macOS 27 beta tem bugs de window management com 3 monitores
- **Fullscreen:** captura todos os monitores (estilo Windows) — usar modo janela
- **Steam API:** `SteamAPI_Init() failed` (normal, sem runtime Steam)
- **Discord SDK:** `Failed to create Discord SDK. Error code: 4` (não-crítico)
- **Crash ao trocar de mapa:** timer do CryEngine estoura UINT32 (`2026-06-20T4294967269:26:35`) — bug do engine, não do Wine

---

## Instalação

### Pré-requisitos
- Mac Apple Silicon (M1/M2/M3/M4/M5)
- macOS 14+ (testado no 27 beta)
- ~65 GB livres em disco
- Conta admin

### Installer interativo (recomendado)
```bash
git clone <este-repo>
cd warchaos-apple-silicon
./install.sh
```

O `install.sh` é interativo: pede sudo, verifica cada passo, pergunta antes de instalar, baixa o launcher do WarChaos do CDN oficial e abre no Wine para baixar os ~29 GB do jogo, e no final cria um lançador executável na Área de Trabalho.

Fluxo completo (do zero ao jogo rodando):
1. Rosetta 2
2. Homebrew + deps
3. Wine 11.10 Staging (Gcenx)
4. Wine prefix
5. ICU + shim icu.dll
6. Registry fixes
7. Patch do mouse (compila winemac.drv)
8. Monitor 144hz (opcional)
9. Download do jogo: baixa `WarChaos Begins.exe` de `https://cdn.warchaos.xyz/files/Bin64Release/WarChaos%20Begins.exe` + paks do launcher, abre no Wine — o launcher faz o download dos ~29 GB do CDN
10. Lançador `~/Desktop/WarChaos.app`

O launcher (`WarChaos Begins.exe`) é um bootstrap Qt 6 que baixa os arquivos do jogo do CDN (`cdn.warchaos.xyz/files/`) usando dois manifests:
- `https://cdn.warchaos.xyz/manifest/manifest-launcher.xml` — arquivos do launcher (paks)
- `https://cdn.warchaos.xyz/manifest/manifest.xml` — arquivos do jogo (29 GB)

### Setup não-interativo (legado)
```bash
./install.sh                             # Installer interativo (Rosetta + Wine + tudo)
./scripts/build-wine-mac-rawinput.sh    # compila e instala o patch do mouse
./scripts/set-gaming-monitor.sh         # (opcional) monitor 144hz como principal
```

### Rodar o jogo
```bash
source scripts/env.sh
cd ~/Desktop/Warface/WarChaos
"$WINE" "Bin64Release/WarChaos Begins.exe"
```

Ou pelo lançador na Área de Trabalho (criado pelo `install.sh`).

### Variáveis de ambiente (scripts/env.sh)
```bash
export WINE="/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/WarChaos-wine"
export WINEESYNC=1
export ROSETTA_ADVERTISE_AVX=1
export WINEDEBUG=-all

# Launcher Qt 6
export QT_QPA_PLATFORM="windows:darkmode=0"     # evita crash COM/UISettings
export QT_AUTO_SCREEN_SCALE_FACTOR=0             # evita falha de DPI awareness
export QT_ENABLE_HIGHDPI_SCALING=0
export QSG_RHI_BACKEND=opengl                    # software & D3D11 backends falham no Wine
export QT_OPENGL=desktop

# Installer .NET
export DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU=72.1.0.3
```

### Registry keys
```
HKCU\Software\Wine\Direct3D: OffscreenRenderingMode = backbuffer
HKCU\Software\Wine\Mac Driver: Decorated = Y
HKCU\Software\Wine\Mac Driver: RawInput = Y          # ativa mouse relativo (precisa do patch)
HKCU\Software\Microsoft\Avalon.Graphics: DisableHWAcceleration = 1
```

---

## Mergulho Técnico

### Por que o GPTK Wine 7.7 não funciona
O Game Porting Toolkit oficial traz Wine 7.7 (2022). Velho demais para Qt 6:
- `qwindows.dll` crasha na init COM/UIAutomation
- `Windows.UI.ViewManagement.UISettings` falha (detecção de dark mode)
- Exceções `0x6BA` (RPC_S_SERVER_UNAVAILABLE) repetidas → C++ abort

### Por que Homebrew x86_64 não funciona no macOS 27
As Command Line Tools do macOS 27 removeram o slice x86_64 do `libxcrun`:
```
xcrun: error: unable to load libxcrun
  (have 'arm64,arm64e', need 'x86_64')
```
Isso quebra `git` sob Rosetta, quebra a instalação do Homebrew x86_64.
**Solução:** usar Wine prebuilt do Gcenx (sem compilação).

### Por que o launcher era invisível
O launcher Qt 6 cria uma janela **borderless** (`WS_EX_LAYERED`). No macOS 27 beta, `winemac.drv` não compõe janelas borderless na tela (existem no Mission Control mas não no desktop).

**Fix:** `Decorated=Y` força decoração nativa macOS, que o winemac apresenta corretamente.

### Por que o conteúdo do launcher era branco/vazio
O Qt Quick scenegraph tentou vários backends:
1. **Software (backend 3):** `Failed to create RHI`
2. **D3D11:** `D3D11 smoke test: Failed to create vertex shader`
3. **OpenGL (backend 2):** ✅ funciona — Wine implementa OpenGL bem

**Fix:** `QSG_RHI_BACKEND=opengl`

### Por que o jogo tinha GL_INVALID_FRAMEBUFFER_OPERATION
O modo offscreen default do Wine usa FBOs que falham no macOS:
```
err:d3d:wined3d_check_gl_call >>>>>>> GL_INVALID_FRAMEBUFFER_OPERATION (0x506) from glClear
```
**Fix:** `OffscreenRenderingMode=backbuffer`

### O shim forwarder de ICU
O jogo traz `Bin64Release/icuuc.dll` — um **forwarder** que redireciona chamadas ICU para um `icu.dll` combinado (existe no Windows real mas não no Wine).

Construímos um `icu.dll` customizado que re-exporta os 542 nomes de função (sem versão) e encaminha para os exports versionados do ICU 72 da Microsoft (`icuuc72.dll`/`icuin72.dll`).

Build: `lld-link /DLL /NOENTRY /MACHINE:X64 /DEF:icu.def stub.obj /OUT:icu.dll`

---

## Erros Encontrados e Correções

| # | Erro | Causa | Fix |
|---|------|-------|-----|
| 1 | `arch: Bad CPU type in executable` | Rosetta 2 não instalado | `softwareupdate --install-rosetta` |
| 2 | `xcrun: missing compatible architecture` | macOS 27 CLT sem slice x86_64 | usar Wine prebuilt Gcenx |
| 3 | `CultureNotFoundException: 'en'` | .NET não acha ICU | instalar ICU real + `APPLOCALICU` |
| 4 | `Cannot find non-neutral culture 'en-us'` | modo invariant; WPF precisa de culturas reais | usar ICU real |
| 5 | `COMException (0x88980406)` no WPF | HW rendering do WPF falha no Wine | `DisableHWAcceleration=1` |
| 6 | `find_forwarded_export ... icu.ucnv_open` | `icuuc.dll` do jogo encaminha para `icu.dll` inexistente | build do shim `icu.dll` |
| 7 | abort C++ após `qwindows.dll` | Qt 6 dark mode crasha (UISettings COM) | `QT_QPA_PLATFORM=windows:darkmode=0` |
| 8 | `SetProcessDpiAwarenessContext() failed` | DPI awareness do Qt falha no Wine | `QT_AUTO_SCREEN_SCALE_FACTOR=0` |
| 9 | `Failed to create RHI (backend 3)` | backend software do Qt falha | `QSG_RHI_BACKEND=opengl` |
| 10 | `D3D11 smoke test: Failed to create vertex shader` | backend D3D11 do Qt falha no Wine | `QSG_RHI_BACKEND=opengl` |
| 11 | `GL_INVALID_FRAMEBUFFER_OPERATION (0x506)` | FBO offscreen do Wine quebrado no macOS | `OffscreenRenderingMode=backbuffer` |
| 12 | janela existe mas invisível | borderless não é composto no macOS 27 beta | `Decorated=Y` |
| 13 | game client não abre via `open`/app bundle | app bundle restringe env do child process | lançar direto do terminal |
| 14 | mouse FPS com ~2s de lag em flicks | heurística `handleMouseMove:` só emite relativo na borda do clip | **patch winemac-rawinput** (ver abaixo) |
| 15 | `configure: C compiler cannot create executables` (build Wine) | `arch -x86_64` → `xcrun` dlopena `libxcrun` arm64-only | cross-compile nativo: `clang -target x86_64-apple-darwin` |
| 16 | `bison version is too old` (build Wine) | bison da Apple é 2.x; Wine precisa ≥3.0 | `brew install bison` + PATH |

---

## O Problema do Mouse

### Sintoma
No mouselook FPS: movimentos lentos funcionavam, flicks rápidos eram ignorados. ~2s de latência antes de responder a mudanças de direção.

### Causa-raiz (confirmada no fonte do Wine)
O diagnóstico anterior ("winemac.drv só entrega posição absoluta e ignora `kCGMouseEventDeltaX/Y`") era **impreciso**. Lendo o fonte do driver (`dlls/winemac.drv/cocoa_app.m`, `WineApplicationController -handleMouseMove:`):

- O driver **lê** `[NSEvent deltaX]/deltaY` (== `kCGMouseEventDeltaX/Y`)
- O driver **emite** eventos `MOUSE_MOVED_RELATIVE`
- `macdrv_mouse_moved()` em `mouse.c` **encaminha** como `MOUSEEVENTF_MOVE` relativo via `NtUserSendHardwareInput`
- O plumbing RID no `user32`/`win32u` **está completo** (patchset do Bernon, 2019, merged — `NtUserSendHardwareInput` sintetiza `WM_INPUT` para dispositivos raw input registrados)

O bug real é uma **heurística em `handleMouseMove:`**: ela só emite `MOUSE_MOVED_RELATIVE` quando o cursor está "pinned" contra a borda do clip/desktop (computa um ponto um passo à frente na direção do movimento e checa se está fora dos limites). No interior do range, emite `MOUSE_MOVED_ABSOLUTE` via `CGEventGetLocation`. Um FPS que faz `ClipCursor` + `ShowCursor(FALSE)` + `RegisterRawInputDevices` mantém o cursor no interior quase sempre → dispositivos raw input registrados nunca recebem deltas relativos usáveis em `WM_INPUT` → flicks rápidos são descartados/lagados.

Isso também explica por que `UseConfinementCursorClipping=N` (o handler de clip via CGEventTap) não ajudou: o event tap reescreve `CGEventGetLocation` para a posição pinada sintetizada, então o "ponto um passo à frente" continua in-bounds e a heurística ainda força absoluto.

### O Fix

**Não criamos RID novo** — a roda já existe no Wine. Portamos o comportamento de relative-pointer do `winewayland.drv` (GitLab MR !5869, `dlls/winewayland.drv/wayland_pointer.c`) para o `winemac.drv`. O driver wayland é irmão do mac com a mesma arquitetura, e seu path de relative-pointer é exatamente o padrão necessário.

**Patch:** `patches/winemac-rawinput.patch` — 3 arquivos, ~25 linhas:
- `macdrv_cocoa.h` / `macdrv_main.c`: adiciona registry key opt-in `HKCU\Software\Wine\Mac Driver\RawInput` (mesmo padrão da key `rawinput` do MR do Wayland).
- `cocoa_app.m` `handleMouseMove:`: quando `RawInput=Y`, **sempre** toma o branch relativo e alimenta os deltas reais do CGEvent (`kCGMouseEventDeltaX/Y`). Não exige `ClipCursor` ou cursor oculto — o jogo registra raw input via `RegisterRawInputDevices` mas pode não fazer o grab (ex: quando acha que está em fullscreen e o SO cuida do cursor). `macdrv_mouse_moved()` + `NtUserSendHardwareInput` + win32u fazem o resto (síntese de `WM_INPUT`). Sem mudança no `mouse.c`.

**Por que a condição foi afrouxada (aprendizado do trackpad):** a primeira versão do patch exigia `clientWantsCursorHidden && clippingCursor` (o grab clássico de FPS). Trace do Wine revelou que no monitor nativo com trackpad, o CryEngine **nunca** chamava `ClipCursor` nem `hideCursor` — acha que está em fullscreen (`Game.log: "Fullscreen: True"`) mas o winemac trata como janela (`fullscreen 0` no trace) → dessincronia → sem grab → patch nunca ativava → flicks caíam na heurística border-pinned bugada. A versão final ativa relativo sempre que `RawInput=Y`, cobrindo ambos os cenários.

**Build & install:** `scripts/build-wine-mac-rawinput.sh`:
- shallow-clone do Wine no tag matching o Gcenx instalado
- aplica o patch
- configura e compila só `dlls/winemac.drv` em x86_64 via cross-compile nativo (`clang -target x86_64-apple-darwin`, contornando o bug do `xcrun`/libxcrun do macOS 27)
- backup do `winemac.so` original, troca pelo patcheado, re-assina o bundle ad-hoc

### Falhas residuais
O mouse ainda falha **durante quedas de FPS** (frame spikes do CryEngine). Causa: o game loop não processa `WM_INPUT` a tempo → deltas se acumulam ou são descartados. É gargalo de render, não do patch. Investigar performance (D3DMetal vs DXVK, shaders, v-sync) para resolver.

### Outras soluções (para a comunidade)

**CrossOver (pago, trial disponível):** tem `winemac.drv` proprietário com RID completo. FPS rodam nativo. Caminho mais rápido se não quiser compilar Wine.

**Upstream do patch:** o patch é estruturado como patch Wine upstream-style (opt-in via registry, segue o precedente do winewayland.drv). Submeter ao wine-devel faria builds futuras do Gcenx já trazerem e removeria o passo de build local.

---

## Monitor 144hz

O Wine/jogo abre na "main display" do macOS (a com a menu bar = origin (0,0)). Para forçar o monitor 144hz externo como principal:

```bash
brew install displayplacer
./scripts/set-gaming-monitor.sh         # 144hz vira main (0,0)
./scripts/set-gaming-monitor.sh -r      # restaura layout anterior
```

O `install.sh` detecta monitores e pergunta qual é o 144hz automaticamente.

---

## Arquivos do Repositório

```
warchaos-apple-silicon/
├── README.md                          # Guia rápido
├── WARCHAOS_MACOS_FULL_GUIDE.md       # Este documento
├── install.sh                         # Installer interativo (sudo, step-by-step, launcher na Área de Trabalho)

├── LICENSE                            # MIT
├── .gitignore
├── patches/
│   └── winemac-rawinput.patch         # Patch Wine: mouse relativo (raw input) para winemac.drv
├── artifacts/
│   ├── icu.def                        # Definições do forwarder ICU (542 exports)
│   └── icu.dll                        # Shim forwarder ICU prebuilt
└── scripts/
    ├── env.sh                         # Variáveis de ambiente (source antes de rodar)
    ├── launch.sh                      # Lança o jogo
    ├── build-icu-shim.sh              # Reconstrói o shim ICU
    ├── build-wine-mac-rawinput.sh     # Compila winemac.drv patcheado e instala no Wine Staging.app
    └── set-gaming-monitor.sh          # Configura monitor 144hz como principal
```

### Paths importantes
| Path | Propósito |
|------|-----------|
| `~/WarChaos-wine/` | Wine prefix |
| `~/Desktop/Warface/WarChaos/` | Instalação do jogo |
| `/Applications/Wine Staging.app/` | Wine 11.10 Staging |
| `~/Desktop/WarChaos.app` | Lançador (criado pelo install.sh) |

---

## Próximos Passos

1. **Performance.** As falhas residuais de mouse correlacionam com quedas de FPS. Investigar: D3DMetal vs DXVK/MoltenVK, cache de shaders, v-sync. Usar `MTL_HUD_ENABLED=1` para medir.

2. **Testar no macOS 26 (stable).** O macOS 27 beta tem bugs de window management que podem não existir no stable. O workaround `Decorated=Y` pode ser dispensável.

3. **Anti-cheat.** O `ClientProtection` não bloqueou, mas confirmar com a staff do WarChaos que jogar via Wine é permitido.

4. **Upstream do patch.** Submeter ao wine-devel — faria builds futuras do Gcenx já trazerem o fix.

5. **Compartilhar.** O repo está pronto para push no GitHub. Avisar no Discord do WarChaos.

---

## Créditos
- [Wine](https://www.winehq.org/) — tradução de API Windows
- [Gcenx macOS Wine Builds](https://github.com/Gcenx/macOS_Wine_builds) — Wine prebuilt para macOS
- [Microsoft ICU](https://www.nuget.org/packages/Microsoft.ICU.ICU4C.Runtime) — ICU para .NET
- [Apple Game Porting Toolkit](https://developer.apple.com/games/) — D3DMetal
- [displayplacer](https://github.com/jakehilborn/displayplacer) — gerenciamento de monitores via CLI
- WarChaos team — o jogo

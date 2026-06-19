# WarChaos no Apple Silicon (macOS)

Guia + scripts para rodar **WarChaos** (FPS CryEngine/Warface, Windows-only) em
**Macs Apple Silicon (M1–M5)** via **Wine + Rosetta 2 + D3DMetal**.

Não há build nativa para macOS. Funciona empilhando três camadas de tradução:

| Camada | Traduz |
|--------|--------|
| **Wine** | `.exe`/`.dll` Windows → macOS (tradução de API, *não* emulação) |
| **Rosetta 2** | instruções x86-64 → ARM Apple |
| **D3DMetal** (GPTK) | DirectX 11/12 → Metal |

> **Status:** 🟢 **JOGÁVEL** no Apple Silicon (M4 / macOS 27 beta). Launcher funcional,
> jogo abre, partidas rodam, mouselook FPS com patch de raw input.

---

## Disclaimer

- Guia não-oficial, feito pela comunidade. **Não afiliado** ao WarChaos, Crytek ou MY.GAMES.
- WarChaos é online. Anti-cheat pode flaggear/banir Wine. **Pergunte à staff do WarChaos**
  se jogar via Wine é permitido antes de ir online. Use por sua conta e risco.
- Testado em: **Mac M4, macOS 27.0**. Deve funcionar em macOS 14+.

---

## Requisitos

- Mac Apple Silicon (M1/M2/M3/M4/M5)
- macOS 14 (Sonoma) ou superior
- **~65 GB livres** em disco
- Conta admin

---

## Instalação rápida

```bash
git clone <este-repo>
cd warchaos-apple-silicon
./install.sh
```

O `install.sh` é interativo: pede sudo, verifica cada passo, pergunta antes de instalar
deps, compila o patch do mouse, configura o monitor 144hz, **baixa o launcher do WarChaos
do CDN oficial e abre no Wine para baixar os ~29 GB do jogo**, e cria um lançador
executável na Área de Trabalho.

Seus amigos só precisam rodar `./install.sh` e seguir as perguntas — do zero ao jogo
rodando, incluindo o download do próprio jogo.

Para detalhes técnicos completos (causa-raiz de cada erro, o patch do mouse, etc.):
**[WARCHAOS_MACOS_FULL_GUIDE.md](WARCHAOS_MACOS_FULL_GUIDE.md)**

---

## O que o install.sh faz

1. **Rosetta 2** — roda binários x86-64 no Apple Silicon
2. **Homebrew** + deps (git, mingw-w64, bison, lld, displayplacer)
3. **Wine 11.10 Staging** (Gcenx prebuilt) — GPTK Wine 7.7 é velho demais para Qt 6
4. **Wine prefix** dedicado em `~/WarChaos-wine`
5. **ICU 72** + shim forwarder `icu.dll` — .NET/CryEngine precisam de ICU real
6. **Registry fixes** — Direct3D backbuffer, Decorated, RawInput, WPF software render
7. **Patch do mouse** — compila `winemac.drv` com raw input relativo (porta do `winewayland.drv` MR !5869), resolve o lag de ~2s no mouselook FPS
8. **Monitor 144hz** — detecta e configura monitor externo high-hz como principal
9. **Download do jogo** — baixa o launcher (`WarChaos Begins.exe`) do CDN oficial (`cdn.warchaos.xyz`) e abre no Wine; o launcher faz o download dos ~29 GB
10. **Lançador** — `~/Desktop/WarChaos.app` (double-clickable)

---

## O problema do mouse (resumo)

O `winemac.drv` tem uma heurística em `handleMouseMove:` (cocoa_app.m) que só emite
`MOUSE_MOVED_RELATIVE` quando o cursor está "pinned" na borda do clip. No interior do
range, emite `MOUSE_MOVED_ABSOLUTE`. Um FPS com `ClipCursor` + `ShowCursor(FALSE)` +
`RegisterRawInputDevices` mantém o cursor no interior → `WM_INPUT` nunca recebe deltas
relativos → flicks lagados.

O patch (`patches/winemac-rawinput.patch`) porta o padrão do `winewayland.drv` para o
`winemac.drv`: quando `RawInput=Y` + cursor oculto + clip ativo (grab de FPS), sempre
emite relativo com os deltas reais do CGEvent. ~16 linhas, opt-in via registry.

Ver o guia completo para detalhes técnicos.

---

## Comandos úteis

```bash
source scripts/env.sh
"$WINESERVER" -k                          # mata tudo no prefix
MTL_HUD_ENABLED=1 ./scripts/launch.sh     # overlay de FPS do Metal
./scripts/set-gaming-monitor.sh -r        # restaura layout de monitores
```

---

## Créditos

- [Wine](https://www.winehq.org/) — tradução de API Windows
- [Gcenx macOS Wine Builds](https://github.com/Gcenx/macOS_Wine_builds) — Wine prebuilt
- [Microsoft ICU](https://www.nuget.org/packages/Microsoft.ICU.ICU4C.Runtime) — ICU para .NET
- [Apple Game Porting Toolkit](https://developer.apple.com/games/) — D3DMetal
- [displayplacer](https://github.com/jakehilborn/displayplacer) — CLI de monitores
- WarChaos team — o jogo

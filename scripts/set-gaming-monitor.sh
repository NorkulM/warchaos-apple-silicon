#!/bin/bash
# ===========================================================================
# Configura qual monitor será a "main display" do macOS (origin 0,0), onde o
# Wine/WarChaos abre por padrão.
#
# Uso:
#   scripts/set-gaming-monitor.sh          # interativo: escolhe o monitor e salva
#   scripts/set-gaming-monitor.sh --apply  # re-aplica silenciosamente a escolha salva
#   scripts/set-gaming-monitor.sh -r       # restaura o layout anterior
#
# Requer: brew install displayplacer
# ===========================================================================
set -euo pipefail

RESTORE_FILE="${WC_DISPLAY_RESTORE:-/tmp/wc-display-restore.txt}"
SAVED_FILE="${WC_DISPLAY_SAVED:-$HOME/.config/warchaos/display-config.txt}"
cmd="${1:-apply-interactive}"

# Modo --apply (silencioso, re-aplica escolha salva) — usado pelo launcher .app
if [ "$cmd" = "--apply" ]; then
  if [ ! -f "$SAVED_FILE" ]; then
    exit 0  # nada salvo, pular silenciosamente
  fi
  command -v displayplacer >/dev/null || exit 0
  # Fallback: se o monitor alvo não estiver plugado, não aplicar a config
  # (deixa o macOS no estado natural — ex: retina vira main sozinho).
  # O monitor alvo é o que está em origin:(0,0) na config salva.
  TARGET_ID=$(grep -oE 'id:[A-F0-9-]+ res:[0-9]+x[0-9]+ [^"]*origin:\(0,0\)' "$SAVED_FILE" \
              | head -1 | grep -oE 'id:[A-F0-9-]+' | sed 's/id://')
  if [ -n "$TARGET_ID" ]; then
    if ! displayplacer list 2>/dev/null | grep -q "Persistent screen id: $TARGET_ID"; then
      exit 0  # monitor alvo ausente — fallback: não mexer, macOS cuida
    fi
  fi
  bash -c "$(cat "$SAVED_FILE")" 2>/dev/null || true
  exit 0
fi

# Modos interativos precisam de terminal
if [ "$cmd" = "apply-interactive" ] || [ "$cmd" = "apply" ]; then
  if ! command -v displayplacer >/dev/null; then
    echo "displayplacer não encontrado. Instale com: brew install displayplacer"
    exit 1
  fi

  mapfile -t IDS < <(displayplacer list 2>/dev/null | awk '/^Persistent screen id:/{print $4}')
  mapfile -t DESCS < <(displayplacer list 2>/dev/null | awk '
    /^Persistent screen id:/{id=$4}
    /^Type:/{type=$0; sub(/Type: /,"",type); gsub(/^[ \t]+/,"",type)}
    /^Resolution:/{res=$2}
    /^Hertz:/{hz=$2}
    /^Origin:/{
      if(type ~ /built/) printf "Built-in (%s @ %shz)\n", res, hz
      else               printf "Externo (%s @ %shz) — %s\n", res, hz, type
    }
  ')

  COUNT=${#IDS[@]}
  [ "$COUNT" -gt 0 ] || { echo "Nenhum monitor detectado."; exit 1; }

  echo "Monitores detectados:"
  for i in "${!DESCS[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${DESCS[$i]}"
  done
  echo
  read -p "Qual monitor usar como principal para o jogo? [1-$COUNT, Enter para pular] " choice
  [ -n "$choice" ] || { echo "Pulado."; exit 0; }
  [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$COUNT" ] \
    || { echo "Escolha inválida."; exit 2; }

  idx=$((choice-1))
  TARGET_ID="${IDS[$idx]}"
  echo "Selecionado: ${DESCS[$idx]}"

  # Salvar layout atual (para reverter)
  displayplacer list 2>/dev/null | grep '^displayplacer ' > "$RESTORE_FILE" || true

  # Construir e executar o comando
  CMD=$(displayplacer list 2>/dev/null | awk -v target="$TARGET_ID" '
    BEGIN { cmd="displayplacer"; placed=0; cur_right=0 }
    /^Persistent screen id:/{id=$4}
    /^Resolution:/{res=$2}
    /^Hertz:/{hz=$2}
    /^Color Depth:/{cd=$3}
    /^Scaling:/{sc=$2}
    /^Origin:/{split($2,a,/[(,)]/); ox=a[2]; oy=a[3]}
    /^Enabled:/{en=$2}
    /^Rotation:/{rot=$2}
    /^Type:/{
      if(id==target){ nx=0; ny=0; placed=1; w=res; sub(/x.*/,"",w); cur_right=w }
      else if(placed){ nx=cur_right; ny=0 }
      else { nx=ox; ny=oy }
      gsub(/.*/,tolower(sc),sc); gsub(/^[ \t]+/,"",en)
      cmd=sprintf("%s \"id:%s res:%s hz:%s color_depth:%s enabled:%s scaling:%s origin:(%d,%d) degree:%s\"",
                  cmd, id, res, hz, cd, tolower(en), sc, nx, ny, rot)
    }
    END{ print cmd }
  ')
  bash -c "$CMD" 2>/dev/null

  # Salvar a config escolhida para re-aplicar silenciosamente no launcher
  mkdir -p "$(dirname "$SAVED_FILE")"
  echo "$CMD" > "$SAVED_FILE"
  echo "Pronto. ${DESCS[$idx]} agora é a main display."
  echo "Configuração salva em $SAVED_FILE (re-aplicada automaticamente ao abrir o jogo)."
  echo "Para reverter: $0 -r"
  exit 0
fi

# Restaurar
if [ "$cmd" = "restore" ] || [ "$cmd" = "-r" ] || [ "$cmd" = "--restore" ]; then
  if [ ! -f "$RESTORE_FILE" ]; then
    echo "Nenhum layout salvo em $RESTORE_FILE. Nada para reverter."
    exit 1
  fi
  echo "Restaurando layout anterior..."
  bash -c "$(cat "$RESTORE_FILE")"
  echo "Restaurado."
  exit 0
fi

echo "Uso: $0 [apply|--apply|restore|-r]"
exit 2

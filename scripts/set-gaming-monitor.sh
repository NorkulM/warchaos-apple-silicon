#!/bin/bash
# ===========================================================================
# Configura qual monitor será a "main display" do macOS (origin 0,0), onde o
# Wine/WarChaos abre por padrão. Interativo: lista os monitores e pergunta
# qual usar. Funciona com qualquer monitor (60hz, 120hz, 144hz, 240hz, ...).
#
# Uso:
#   scripts/set-gaming-monitor.sh          # interativo: escolhe o monitor
#   scripts/set-gaming-monitor.sh -r       # restaura o layout anterior
#
# Requer: brew install displayplacer
# ===========================================================================
set -euo pipefail

RESTORE_FILE="${WC_DISPLAY_RESTORE:-/tmp/wc-display-restore.txt}"
cmd="${1:-apply}"

case "$cmd" in
  apply)
    if ! command -v displayplacer >/dev/null; then
      echo "displayplacer não encontrado. Instale com: brew install displayplacer"
      exit 1
    fi

    # Coletar monitores
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
    read -p "Qual monitor usar como principal? [1-$COUNT, Enter para cancelar] " choice
    [ -n "$choice" ] || { echo "Cancelado."; exit 0; }
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$COUNT" ] \
      || { echo "Escolha inválida."; exit 2; }

    idx=$((choice-1))
    TARGET_ID="${IDS[$idx]}"
    echo "Selecionado: ${DESCS[$idx]} (id ${TARGET_ID:0:8}...)"

    # Salvar layout atual
    displayplacer list 2>/dev/null | grep '^displayplacer ' > "$RESTORE_FILE" || true
    echo "Layout atual salvo em $RESTORE_FILE"

    # Aplicar: target em (0,0), outros reposicionados à direita
    echo "Aplicando..."
    displayplacer list 2>/dev/null | awk -v target="$TARGET_ID" '
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
    ' | bash 2>/dev/null
    echo "Pronto. ${DESCS[$idx]} agora é a main display."
    echo "Para reverter: $0 -r"
    ;;

  restore|-r|--restore)
    if [ ! -f "$RESTORE_FILE" ]; then
      echo "Nenhum layout salvo em $RESTORE_FILE. Nada para reverter."
      exit 1
    fi
    echo "Restaurando layout anterior..."
    bash -c "$(cat "$RESTORE_FILE")"
    echo "Restaurado."
    ;;

  *)
    echo "Uso: $0 [apply|restore|-r]"
    exit 2
    ;;
esac

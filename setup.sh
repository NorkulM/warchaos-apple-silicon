#!/bin/bash
# ===========================================================================
# Wrapper legado — chama install.sh (que faz tudo isto e mais).
# Mantido para compatibilidade com quem já usa ./setup.sh.
# ===========================================================================
exec "$(dirname "$0")/install.sh" "$@"

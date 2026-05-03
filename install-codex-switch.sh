#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
DEFAULT_BASE_URL="https://raw.githubusercontent.com/liut-coder/openbox/main"
INSTALL_BASE_URL="${OPENBOX_INSTALL_BASE_URL:-${CODEX_INSTALL_BASE_URL:-$DEFAULT_BASE_URL}}"

if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
    exec "$SCRIPT_DIR/install.sh" codex-switch "$@"
fi

exec bash -c "$(curl -fsSL "$INSTALL_BASE_URL/install.sh")" bash codex-switch "$@"

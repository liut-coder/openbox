#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BASE_URL="https://sh.misk.cc"
INSTALL_URL="${OPENBOX_ENTRY_BASE_URL:-$DEFAULT_BASE_URL}/install.sh"

log() {
    printf "%s\n" "$1"
}

die() {
    printf "错误: %s\n" "$1" >&2
    exit 1
}

run_install() {
    local target="${1:-}"
    shift || true

    if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
        exec "$SCRIPT_DIR/install.sh" "$target" "$@"
    fi

    exec bash -c "$(curl -fsSL "$INSTALL_URL")" bash "$target" "$@"
}

show_help() {
    cat <<EOF
openbox 统一入口

用法:
  bash <(curl -fsSL $DEFAULT_BASE_URL)
  bash <(curl -fsSL $DEFAULT_BASE_URL) <target>
  bash <(curl -fsSL $DEFAULT_BASE_URL) --list

目标:
  codex-switch
  claude-switch
  caddy-manager
  all

示例:
  bash <(curl -fsSL $DEFAULT_BASE_URL) codex-switch
  bash <(curl -fsSL $DEFAULT_BASE_URL) claude-switch
  bash <(curl -fsSL $DEFAULT_BASE_URL) caddy-manager
  bash <(curl -fsSL $DEFAULT_BASE_URL) all

说明:
  - 根入口默认显示本帮助
  - 传入目标后会转交给 install.sh
  - 也可以直接使用: bash <(curl -fsSL $DEFAULT_BASE_URL/install.sh) <target>
EOF
}

show_menu() {
    cat <<'EOF'
请选择要安装的脚本:
  1) codex-switch
  2) claude-switch
  3) caddy-manager
  4) all
  0) 退出
EOF

    local choice
    read -r -p "输入编号: " choice
    case "$choice" in
        1) run_install codex-switch ;;
        2) run_install claude-switch ;;
        3) run_install caddy-manager ;;
        4) run_install all ;;
        0) exit 0 ;;
        *) die "无效选择: $choice" ;;
    esac
}

main() {
    case "${1:-}" in
        "")
            if [[ -t 0 && -t 1 ]]; then
                show_menu
            else
                show_help
            fi
            ;;
        --help|-h)
            show_help
            ;;
        --list|-l)
            run_install --list
            ;;
        codex-switch|codex|sw|claude-switch|claude|cw|caddy-manager|caddy|cm|all)
            run_install "$@"
            ;;
        *)
            die "未知目标: $1。使用 --list 查看可安装目标。"
            ;;
    esac
}

main "$@"

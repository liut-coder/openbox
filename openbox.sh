#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
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
openbox 中文工具箱入口

用法:
  bash <(curl -fsSL $DEFAULT_BASE_URL)
  bash <(curl -fsSL $DEFAULT_BASE_URL) <工具名>
  bash <(curl -fsSL $DEFAULT_BASE_URL) --list

工具分类:
  AI 类
    codex-switch   Codex 中转 / 配置切换工具
    claude-switch  Claude Code / 网关切换工具

  转发 / 反代类
    caddy-manager  Caddy 反代管理工具
    forward        安全转发工具（支持交互菜单，命令: forward / fw）

  其他
    proxy-setup    下载代理配置工具（命令: proxy-setup / proxy）
    all            安装全部工具

示例:
  bash <(curl -fsSL $DEFAULT_BASE_URL) codex-switch
  bash <(curl -fsSL $DEFAULT_BASE_URL) claude-switch
  bash <(curl -fsSL $DEFAULT_BASE_URL) caddy-manager
  bash <(curl -fsSL $DEFAULT_BASE_URL) forward
  bash <(curl -fsSL $DEFAULT_BASE_URL) proxy-setup
  bash <(curl -fsSL $DEFAULT_BASE_URL) all

说明:
  - 交互式终端下，不带参数会显示中文分类菜单
  - 非交互环境下，不带参数会显示本帮助
  - 传入工具名后会转交给 install.sh
  - 也可以直接使用: bash <(curl -fsSL $DEFAULT_BASE_URL/install.sh) <工具名>
EOF
}

show_menu() {
    cat <<'EOF'
================================================
                openbox 中文工具箱
================================================
 AI 类
  1. Codex 配置切换           codex-switch / sw
  2. Claude 配置切换          claude-switch / cw

 转发 / 反代类
  3. Caddy 反代管理           caddy-manager / cm
  4. 安全端口转发             forward / fw

 其他
  5. 代理配置工具           proxy-setup / proxy
  9. 安装全部工具             all
------------------------------------------------
  0. 退出
================================================
EOF

    local choice
    read -r -p "请输入编号或工具名: " choice
    case "$choice" in
        1|codex-switch|codex|sw) run_install codex-switch ;;
        2|claude-switch|claude|cw) run_install claude-switch ;;
        3|caddy-manager|caddy|cm) run_install caddy-manager ;;
        4|forward|fw) run_install forward ;;
        5|proxy-setup|proxy) run_install proxy-setup ;;
        9|all) run_install all ;;
        0|q|quit|exit) exit 0 ;;
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
        codex-switch|codex|sw|claude-switch|claude|cw|caddy-manager|caddy|cm|forward|fw|proxy-setup|proxy|all)
            run_install "$@"
            ;;
        *)
            die "未知目标: $1。使用 --list 查看可安装目标。"
            ;;
    esac
}

main "$@"

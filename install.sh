#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-/usr/local/bin}"
DEFAULT_BASE_URL="https://raw.githubusercontent.com/liut-coder/openbox/main"
DOWNLOAD_BASE_URL="${OPENBOX_INSTALL_BASE_URL:-${CODEX_INSTALL_BASE_URL:-$DEFAULT_BASE_URL}}"
TMP_FILES=()

log() {
    printf "%s\n" "$1"
}

die() {
    printf "错误: %s\n" "$1" >&2
    exit 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

run_privileged() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    else
        has_cmd sudo || die "当前不是 root，且未找到 sudo"
        sudo "$@"
    fi
}

install_packages() {
    local packages=("$@")
    [[ ${#packages[@]} -gt 0 ]] || return 0

    log "安装依赖: ${packages[*]}"

    if has_cmd apt-get; then
        run_privileged apt-get update
        run_privileged apt-get install -y "${packages[@]}"
    elif has_cmd dnf; then
        run_privileged dnf install -y "${packages[@]}"
    elif has_cmd yum; then
        run_privileged yum install -y "${packages[@]}"
    elif has_cmd pacman; then
        run_privileged pacman -Sy --noconfirm "${packages[@]}"
    elif has_cmd apk; then
        run_privileged apk add --no-cache "${packages[@]}"
    else
        die "无法自动安装依赖，请手动安装: ${packages[*]}"
    fi
}

ensure_commands() {
    local missing=()
    local cmd

    for cmd in "$@"; do
        has_cmd "$cmd" || missing+=("$cmd")
    done

    install_packages "${missing[@]}"
}

install_file() {
    local src="$1"
    local dst="$2"

    run_privileged mkdir -p "$TARGET_DIR"
    run_privileged install -m 755 "$src" "$dst"
}

cleanup() {
    local file
    for file in "${TMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

resolve_source() {
    local source_name="$1"
    local local_source="$SCRIPT_DIR/$source_name"
    local tmp_source

    if [[ -f "$local_source" ]]; then
        printf "%s\n" "$local_source"
        return 0
    fi

    ensure_commands curl
    tmp_source="$(mktemp "/tmp/openbox.XXXXXX")"
    TMP_FILES+=("$tmp_source")
    curl -fsSL "$DOWNLOAD_BASE_URL/$source_name" -o "$tmp_source"
    chmod +x "$tmp_source"
    printf "%s\n" "$tmp_source"
}

install_codex_switch() {
    local source_script

    ensure_commands curl jq
    source_script="$(resolve_source "codex-switch.sh")"

    log "安装 Codex Switch..."
    install_file "$source_script" "$TARGET_DIR/codex-switch"
    install_file "$source_script" "$TARGET_DIR/sw"

    log "安装完成:"
    log "  $TARGET_DIR/codex-switch"
    log "  $TARGET_DIR/sw"
    log ""
    log "启动: sw"
}

install_claude_switch() {
    local source_script

    ensure_commands curl jq
    source_script="$(resolve_source "claude-switch.sh")"

    log "安装 Claude Switch..."
    install_file "$source_script" "$TARGET_DIR/claude-switch"
    install_file "$source_script" "$TARGET_DIR/cw"

    log "安装完成:"
    log "  $TARGET_DIR/claude-switch"
    log "  $TARGET_DIR/cw"
    log ""
    log "启动: cw"
}

install_caddy_manager() {
    local source_script

    ensure_commands curl
    source_script="$(resolve_source "caddy_manager.sh")"

    log "安装 Caddy Manager..."
    install_file "$source_script" "$TARGET_DIR/caddy-manager"
    install_file "$source_script" "$TARGET_DIR/cm"

    log "安装完成:"
    log "  $TARGET_DIR/caddy-manager"
    log "  $TARGET_DIR/cm"
    log ""
    log "启动: cm"
}

install_all() {
    install_codex_switch
    echo ""
    install_claude_switch
    echo ""
    install_caddy_manager
}

uninstall_target() {
    case "$1" in
        codex-switch)
            run_privileged rm -f "$TARGET_DIR/codex-switch" "$TARGET_DIR/sw"
            log "已卸载 codex-switch"
            ;;
        claude-switch)
            run_privileged rm -f "$TARGET_DIR/claude-switch" "$TARGET_DIR/cw"
            log "已卸载 claude-switch"
            ;;
        caddy-manager)
            run_privileged rm -f "$TARGET_DIR/caddy-manager" "$TARGET_DIR/cm"
            log "已卸载 caddy-manager"
            ;;
        all)
            uninstall_target codex-switch
            uninstall_target claude-switch
            uninstall_target caddy-manager
            ;;
        *)
            die "未知卸载目标: $1"
            ;;
    esac
}

show_list() {
    cat <<EOF
可用工具:
  codex-switch   安装 Codex 配置切换工具（命令: codex-switch / sw）
  claude-switch  安装 Claude 配置切换工具（命令: claude-switch / cw）
  caddy-manager  安装 Caddy 反代管理工具（命令: caddy-manager / cm）
  all            安装全部工具
EOF
}

show_help() {
    cat <<EOF
openbox 中文工具箱安装器

用法:
  bash install.sh <工具名>
  bash install.sh --list
  bash install.sh --uninstall <工具名>

可用工具:
  codex-switch   Codex 中转 / 配置切换工具
  claude-switch  Claude Code / 网关切换工具
  caddy-manager  Caddy 反代管理工具
  all            安装全部工具

环境变量:
  TARGET_DIR               安装目录，默认 /usr/local/bin
  OPENBOX_INSTALL_BASE_URL 下载地址，默认 $DEFAULT_BASE_URL

示例:
  bash <(curl -fsSL $DEFAULT_BASE_URL/install.sh) codex-switch
  bash <(curl -fsSL $DEFAULT_BASE_URL/install.sh) claude-switch
  bash <(curl -fsSL $DEFAULT_BASE_URL/install.sh) caddy-manager
  bash <(curl -fsSL $DEFAULT_BASE_URL/install.sh) all
EOF
}

show_menu() {
    cat <<'EOF'
========================================
        openbox 中文工具箱安装器
========================================
  1. 安装 Codex 配置切换      codex-switch / sw
  2. 安装 Claude 配置切换     claude-switch / cw
  3. 安装 Caddy 反代管理      caddy-manager / cm
  4. 安装全部工具             all
----------------------------------------
  0. 退出
========================================
EOF

    local choice
    read -r -p "请输入编号或工具名: " choice
    case "$choice" in
        1|codex-switch|codex|sw) install_codex_switch ;;
        2|claude-switch|claude|cw) install_claude_switch ;;
        3|caddy-manager|caddy|cm) install_caddy_manager ;;
        4|all) install_all ;;
        0|q|quit|exit) exit 0 ;;
        *) die "无效选择: $choice" ;;
    esac
}

main() {
    trap cleanup EXIT

    case "${1:-}" in
        codex-switch|codex|sw)
            install_codex_switch
            ;;
        claude-switch|claude|cw)
            install_claude_switch
            ;;
        caddy-manager|caddy|cm)
            install_caddy_manager
            ;;
        all)
            install_all
            ;;
        --list|-l)
            show_list
            ;;
        --uninstall)
            [[ $# -ge 2 ]] || die "用法: $0 --uninstall <target>"
            uninstall_target "$2"
            ;;
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
        *)
            die "未知目标: $1。使用 --list 查看可安装目标。"
            ;;
    esac
}

main "$@"

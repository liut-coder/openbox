#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-/usr/local/bin}"
TARGET_MAIN="$TARGET_DIR/codex-switch"
TARGET_ALIAS="$TARGET_DIR/sw"
DEFAULT_BASE_URL="https://raw.githubusercontent.com/liut-coder/openbox/main"
DOWNLOAD_BASE_URL="${CODEX_INSTALL_BASE_URL:-$DEFAULT_BASE_URL}"
TMP_SOURCE=""

log() {
    printf "%s\n" "$1"
}

require_file() {
    [[ -f "$1" ]] || {
        printf "缺少文件: %s\n" "$1" >&2
        exit 1
    }
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

run_privileged() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_dependencies() {
    local missing=()

    has_cmd curl || missing+=("curl")
    has_cmd jq || missing+=("jq")

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    log "安装依赖: ${missing[*]}"

    if has_cmd apt-get; then
        run_privileged apt-get update
        run_privileged apt-get install -y "${missing[@]}"
    elif has_cmd dnf; then
        run_privileged dnf install -y "${missing[@]}"
    elif has_cmd yum; then
        run_privileged yum install -y "${missing[@]}"
    elif has_cmd pacman; then
        run_privileged pacman -Sy --noconfirm "${missing[@]}"
    elif has_cmd apk; then
        run_privileged apk add --no-cache "${missing[@]}"
    else
        printf "无法自动安装依赖，请手动安装: %s\n" "${missing[*]}" >&2
        exit 1
    fi
}

install_file() {
    local src="$1"
    local dst="$2"

    if install -m 755 "$src" "$dst" 2>/dev/null; then
        return 0
    fi

    sudo install -m 755 "$src" "$dst"
}

cleanup() {
    if [[ -n "$TMP_SOURCE" && -f "$TMP_SOURCE" ]]; then
        rm -f "$TMP_SOURCE"
    fi
}

resolve_source_script() {
    local local_source="$SCRIPT_DIR/codex-switch.sh"

    if [[ -f "$local_source" ]]; then
        printf "%s\n" "$local_source"
        return 0
    fi

    TMP_SOURCE="$(mktemp /tmp/codex-switch.XXXXXX)"
    curl -fsSL "$DOWNLOAD_BASE_URL/codex-switch.sh" -o "$TMP_SOURCE"
    chmod +x "$TMP_SOURCE"
    printf "%s\n" "$TMP_SOURCE"
}

main() {
    trap cleanup EXIT
    local source_script
    install_dependencies
    source_script="$(resolve_source_script)"
    require_file "$source_script"
    mkdir -p "$TARGET_DIR"

    log "安装 Codex 配置管理脚本..."
    install_file "$source_script" "$TARGET_MAIN"
    install_file "$source_script" "$TARGET_ALIAS"

    log "安装完成:"
    log "  $TARGET_MAIN"
    log "  $TARGET_ALIAS"
    log ""
    log "可用命令:"
    log "  codex-switch"
    log "  sw"
}

main "$@"

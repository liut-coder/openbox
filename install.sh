#!/usr/bin/env bash
# openbox install.sh — 统一脚本安装器 v2
# 支持：分类安装、按名搜索、一键全部安装

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
TARGET_DIR="${TARGET_DIR:-/usr/local/bin}"
DEFAULT_BASE_URL="https://raw.githubusercontent.com/liut-coder/openbox/main"
DOWNLOAD_BASE_URL="${OPENBOX_INSTALL_BASE_URL:-${CODEX_INSTALL_BASE_URL:-$DEFAULT_BASE_URL}}"
TMP_FILES=()

# ── Script Registry ──────────────────────────────────────────────
# 格式: name|category|description|source_path|target_name|alias
# alias 为空表示无别名
SCRIPTS=(
  # proxy
  "caddy-manager|proxy|Caddy 交互式反代管理|proxy/caddy_manager.sh|caddy-manager|cm"
  "forward|proxy|iptables 安全端口转发|proxy/forward.sh|forward|fw"
  # tools
  "codex-switch|tools|Codex CLI 多配置切换|tools/codex-switch.sh|codex-switch|sw"
  "claude-switch|tools|Claude Code 网关切换|tools/claude-switch.sh|claude-switch|cw"
  "proxy-setup|tools|代理环境一键配置|tools/proxy-setup.sh|proxy-setup|proxy"
  # agent
  "agent-status|agent|常用状态面板|agent/agent-status.sh|agent-status|ast"
  "agent-restart|agent|常用服务重启入口|agent/agent-restart.sh|agent-restart|ars"
  "agent-sync|agent|常用刷新同步入口|agent/agent-sync.sh|agent-sync|asg"
)
# ──────────────────────────────────────────────────────────────────

CATEGORIES=($(printf '%s\n' "${SCRIPTS[@]}" | cut -d'|' -f2 | sort -u))

log()    { printf "%s\n" "$1"; }
warn()   { printf "⚠ %s\n" "$1" >&2; }
die()    { printf "✗ %s\n" "$1" >&2; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

run_privileged() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"
    else has_cmd sudo && sudo "$@" || die "需要 root 或 sudo"; fi
}

install_packages() {
    local pkgs=("$@"); [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log "安装依赖: ${pkgs[*]}"
    if      has_cmd apt-get; then run_privileged apt-get update -qq && run_privileged apt-get install -y "${pkgs[@]}"
    elif    has_cmd dnf;     then run_privileged dnf install -y "${pkgs[@]}"
    elif    has_cmd yum;     then run_privileged yum install -y "${pkgs[@]}"
    elif    has_cmd pacman;  then run_privileged pacman -Sy --noconfirm "${pkgs[@]}"
    elif    has_cmd apk;     then run_privileged apk add --no-cache "${pkgs[@]}"
    else die "无法自动安装依赖: ${pkgs[*]}"; fi
}

ensure_commands() {
    local missing=(); for cmd in "$@"; do has_cmd "$cmd" || missing+=("$cmd"); done
    install_packages "${missing[@]}"
}

install_file() {
    run_privileged mkdir -p "$TARGET_DIR"
    run_privileged install -m 755 "$1" "$2"
}

cleanup() { for f in "${TMP_FILES[@]}"; do [[ -f "$f" ]] && rm -f "$f"; done; }

resolve_source() {
    local src="$1"
    local local_path="$SCRIPT_DIR/$src"
    if [[ -f "$local_path" ]]; then
        printf '%s\n' "$local_path"; return 0
    fi
    ensure_commands curl
    local tmp; tmp="$(mktemp "/tmp/openbox.XXXXXX")"
    TMP_FILES+=("$tmp")
    curl -fsSL "$DOWNLOAD_BASE_URL/$src" -o "$tmp"
    chmod +x "$tmp"
    printf '%s\n' "$tmp"
}

# ── Registry helpers ─────────────────────────────────────────────

get_field() { printf '%s\n' "$1" | cut -d'|' -f"$2"; }

find_script() {
    # 输入: name 或 category/name 或 alias
    local q="${1,,}"
    local entry
    for entry in "${SCRIPTS[@]}"; do
        local name;   name="$(get_field "$entry" 1)"
        local cat;    cat="$(get_field "$entry" 2)"
        local alias;  alias="$(get_field "$entry" 6)"
        # 精确匹配: category/name
        [[ "${cat}/${name}" == "$q" ]] && { printf '%s\n' "$entry"; return 0; }
        # 精确匹配: name
        [[ "${name}" == "$q" ]] && { printf '%s\n' "$entry"; return 0; }
        # 别名匹配
        [[ -n "$alias" && "${alias,,}" == "$q" ]] && { printf '%s\n' "$entry"; return 0; }
    done
    return 1
}

list_scripts() {
    local current_cat=""
    for entry in "${SCRIPTS[@]}"; do
        local cat;  cat="$(get_field "$entry" 2)"
        local name; name="$(get_field "$entry" 1)"
        local desc; desc="$(get_field "$entry" 3)"
        local alias; alias="$(get_field "$entry" 6)"
        if [[ "$cat" != "$current_cat" ]]; then
            printf '\n## %s\n' "$cat"
            current_cat="$cat"
        fi
        local alias_str=""; [[ -n "$alias" ]] && alias_str=" (别名: $alias)"
        printf '  %-20s %s%s\n' "$name" "$desc" "$alias_str"
    done
    echo
}

install_one() {
    local entry="$1"
    local name;   name="$(get_field "$entry" 1)"
    local cat;    cat="$(get_field "$entry" 2)"
    local desc;   desc="$(get_field "$entry" 3)"
    local src;    src="$(get_field "$entry" 4)"
    local target; target="$(get_field "$entry" 5)"
    local alias;  alias="$(get_field "$entry" 6)"

    log "安装 [$cat] $desc ..."
    local file; file="$(resolve_source "$src")"
    ensure_commands curl jq
    install_file "$file" "$TARGET_DIR/$target"
    if [[ -n "$alias" ]]; then
        install_file "$file" "$TARGET_DIR/$alias"
    fi
    log " ✓ $TARGET_DIR/$target"
    [[ -n "$alias" ]] && log " ✓ $TARGET_DIR/$alias"
}

install_category() {
    local cat="$1"; local found=0
    for entry in "${SCRIPTS[@]}"; do
        [[ "$(get_field "$entry" 2)" == "$cat" ]] || continue
        install_one "$entry"; found=1
    done
    [[ $found -eq 0 ]] && die "没有找到分类: $cat"
    return 0
}

install_all() {
    for entry in "${SCRIPTS[@]}"; do install_one "$entry"; done
}

uninstall_target() {
    local q="$1"
    if [[ "$q" == "all" ]]; then
        for entry in "${SCRIPTS[@]}"; do
            local target; target="$(get_field "$entry" 5)"
            local alias;  alias="$(get_field "$entry" 6)"
            run_privileged rm -f "$TARGET_DIR/$target"
            [[ -n "$alias" ]] && run_privileged rm -f "$TARGET_DIR/$alias"
            log "已删除: $target"
        done
        return
    fi

    # 查分类名
    for cat in "${CATEGORIES[@]}"; do
        if [[ "${cat,,}" == "${q,,}" ]]; then
            for entry in "${SCRIPTS[@]}"; do
                [[ "$(get_field "$entry" 2)" == "$cat" ]] || continue
                run_privileged rm -f "$TARGET_DIR/$(get_field "$entry" 5)"
            done
            log "已删除分类: $cat"
            return
        fi
    done

    local entry; entry="$(find_script "$q")" || die "未找到: $q"
    local target; target="$(get_field "$entry" 5)"
    local alias;  alias="$(get_field "$entry" 6)"
    run_privileged rm -f "$TARGET_DIR/$target"
    [[ -n "$alias" ]] && run_privileged rm -f "$TARGET_DIR/$alias"
    log "已删除: $target"
}

show_help() {
    cat <<EOF
用法: install.sh [选项] <目标>

目标:
  <脚本名>        安装单个脚本（如 codex-switch）
  <分类>          安装整类（如 proxy, tools）
  all             安装全部

选项:
  --list, -l      列出所有可用脚本
  --uninstall <目标>  卸载
  --help, -h      显示此帮助

分类: ${CATEGORIES[*]}

示例:
  bash install.sh proxy          # 安装 proxy 类全部
  bash install.sh codex-switch   # 安装单个
  bash install.sh all            # 安装全部
  bash install.sh --list         # 查看列表

远程安装:
  bash <(curl -fsSL $DOWNLOAD_BASE_URL/install.sh) proxy
EOF
}

# ── Main ─────────────────────────────────────────────────────────
trap cleanup EXIT

case "${1:-}" in
    --list|-l)
        list_scripts; exit 0 ;;
    --uninstall)
        [[ -n "${2:-}" ]] || die "用法: install.sh --uninstall <目标>"
        uninstall_target "$2"; exit 0 ;;
    --help|-h|help)
        show_help; exit 0 ;;
    "")
        show_help
        echo
        list_scripts
        ;;
    *)
        Q="${1,,}"
        # all
        [[ "$Q" == "all" ]] && { install_all; exit 0; }
        # category?
        for cat in "${CATEGORIES[@]}"; do
            [[ "${cat,,}" == "$Q" ]] && { install_category "$cat"; exit 0; }
        done
        # single script (by name / alias / category/name)
        ENTRY="$(find_script "$Q")" || die "未找到: $1（用 --list 查看可用脚本）"
        install_one "$ENTRY"
        ;;
esac

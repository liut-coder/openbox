#!/usr/bin/env bash

set -euo pipefail

VERSION="1.1.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_NAME="claude-switch"
OFFICIAL_PROFILE="official"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/claude-switch"
PROFILES_FILE="$CONFIG_ROOT/profiles.json"
STATE_FILE="$CONFIG_ROOT/state.json"
ENV_FILE="$CONFIG_ROOT/current.env"

print_color() {
    local color="$1"
    local message="$2"
    printf "%b%s%b\n" "$color" "$message" "$NC"
}

info() {
    print_color "$BLUE" "$1"
}

success() {
    print_color "$GREEN" "$1"
}

warn() {
    print_color "$YELLOW" "$1"
}

error() {
    print_color "$RED" "$1" >&2
}

die() {
    error "$1"
    exit 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

require_cmd() {
    local cmd="$1"
    local hint="${2:-Install '$cmd' first.}"
    has_cmd "$cmd" || die "$hint"
}

run_privileged() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        "$@"
    else
        has_cmd sudo || die "当前不是 root，且未找到 sudo"
        sudo "$@"
    fi
}

shell_quote() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

init_store() {
    local tmp_file

    mkdir -p "$CONFIG_ROOT"
    [[ -f "$PROFILES_FILE" ]] || printf '{}\n' > "$PROFILES_FILE"
    [[ -f "$STATE_FILE" ]] || printf '{"current_profile":""}\n' > "$STATE_FILE"

    tmp_file="$(mktemp "${PROFILES_FILE}.XXXXXX")"
    jq '
        with_entries(
            select(.key != "official") |
            .value = {
                name: .key,
                base_url: (.value.base_url // ""),
                api_key: (.value.api_key // .value.auth_token // "")
            }
        )
    ' "$PROFILES_FILE" > "$tmp_file"
    mv "$tmp_file" "$PROFILES_FILE"
}

prepare_store() {
    require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
    init_store
}

normalize_base_url() {
    local value="$1"
    value="${value%/}"
    printf "%s\n" "$value"
}

anthropic_models_url() {
    local base_url
    base_url="$(normalize_base_url "$1")"
    if [[ "$base_url" == */v1 ]]; then
        printf "%s/models\n" "$base_url"
    else
        printf "%s/v1/models\n" "$base_url"
    fi
}

profile_exists() {
    local name="$1"
    [[ "$name" == "$OFFICIAL_PROFILE" ]] && return 0
    jq -e --arg name "$name" 'has($name)' "$PROFILES_FILE" >/dev/null
}

get_profile_json() {
    local name="$1"
    if [[ "$name" == "$OFFICIAL_PROFILE" ]]; then
        jq -n --arg name "$OFFICIAL_PROFILE" '{name:$name, official:true, base_url:"", api_key:""}'
        return
    fi
    jq -e --arg name "$name" '.[$name]' "$PROFILES_FILE"
}

get_current_profile_name() {
    jq -r '.current_profile // ""' "$STATE_FILE"
}

get_active_profile_name() {
    local current
    current="$(get_current_profile_name)"
    printf "%s\n" "${current:-$OFFICIAL_PROFILE}"
}

set_current_profile_name() {
    local name="$1"
    local tmp_file

    tmp_file="$(mktemp "${STATE_FILE}.XXXXXX")"
    jq --arg name "$name" '.current_profile = $name' "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}

write_env_file() {
    local base_url="$1"
    local api_key="$2"

    cat > "$ENV_FILE" <<EOF
export ANTHROPIC_BASE_URL=$(shell_quote "$base_url")
export ANTHROPIC_AUTH_TOKEN=$(shell_quote "$api_key")
export ANTHROPIC_API_KEY=$(shell_quote "$api_key")
EOF
}

write_official_env_file() {
    cat > "$ENV_FILE" <<EOF
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_API_KEY
EOF
}

update_shell_rc() {
    local rc_file="$1"
    local begin="# >>> claude-switch >>>"
    local end="# <<< claude-switch <<<"
    local block

    [[ -f "$rc_file" ]] || touch "$rc_file"

    block="$(cat <<EOF
$begin
if [ -f '$ENV_FILE' ]; then
  . '$ENV_FILE'
fi
$end
EOF
)"

    if grep -Fq "$begin" "$rc_file"; then
        local tmp_file
        tmp_file="$(mktemp "${rc_file}.XXXXXX")"
        awk -v begin="$begin" -v end="$end" -v block="$block" '
            $0 == begin { print block; skip=1; next }
            $0 == end { skip=0; next }
            !skip { print }
        ' "$rc_file" > "$tmp_file"
        mv "$tmp_file" "$rc_file"
    else
        printf "\n%s\n" "$block" >> "$rc_file"
    fi
}

sync_shell_environment() {
    local base_url="$1"
    local api_key="$2"

    write_env_file "$base_url" "$api_key"
    export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$api_key"
    export ANTHROPIC_API_KEY="$api_key"
    update_shell_rc "$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" ]]; then
        update_shell_rc "$HOME/.zshrc"
    fi
}

sync_official_environment() {
    write_official_env_file
    unset ANTHROPIC_BASE_URL
    unset ANTHROPIC_AUTH_TOKEN
    unset ANTHROPIC_API_KEY
    update_shell_rc "$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" ]]; then
        update_shell_rc "$HOME/.zshrc"
    fi
}

save_profile() {
    local name="$1"
    local base_url="$2"
    local api_key="$3"
    local tmp_file

    [[ "$name" != "$OFFICIAL_PROFILE" ]] || die "'$OFFICIAL_PROFILE' 是内置官方配置名，请换一个名称"

    base_url="$(normalize_base_url "$base_url")"
    tmp_file="$(mktemp "${PROFILES_FILE}.XXXXXX")"

    jq \
        --arg name "$name" \
        --arg base_url "$base_url" \
        --arg api_key "$api_key" \
        '.[$name] = {name:$name, base_url:$base_url, api_key:$api_key}' \
        "$PROFILES_FILE" > "$tmp_file"
    mv "$tmp_file" "$PROFILES_FILE"

    success "配置 '$name' 已保存"
}

delete_profile() {
    local name="$1"
    local tmp_file

    [[ "$name" != "$OFFICIAL_PROFILE" ]] || die "官方配置不能删除"
    profile_exists "$name" || die "配置 '$name' 不存在"

    tmp_file="$(mktemp "${PROFILES_FILE}.XXXXXX")"
    jq --arg name "$name" 'del(.[$name])' "$PROFILES_FILE" > "$tmp_file"
    mv "$tmp_file" "$PROFILES_FILE"

    if [[ "$(get_current_profile_name)" == "$name" ]]; then
        set_current_profile_name ""
    fi

    success "配置 '$name' 已删除"
}

list_profiles() {
    local current
    current="$(get_current_profile_name)"

    if [[ "$current" == "$OFFICIAL_PROFILE" || -z "$current" ]]; then
        printf "* %s\t%s\n" "$OFFICIAL_PROFILE" "官方 Claude Code"
    else
        printf "  %s\t%s\n" "$OFFICIAL_PROFILE" "官方 Claude Code"
    fi

    jq -r 'to_entries[] | [.key, .value.base_url] | @tsv' "$PROFILES_FILE" |
    while IFS=$'\t' read -r name base_url; do
        if [[ "$name" == "$current" ]]; then
            printf "* %s\t%s\n" "$name" "$base_url"
        else
            printf "  %s\t%s\n" "$name" "$base_url"
        fi
    done
}

mask_api_key() {
    local api_key="$1"
    local length="${#api_key}"
    if (( length <= 8 )); then
        printf "%s\n" "$api_key"
    else
        printf "%s****%s\n" "${api_key:0:4}" "${api_key: -4}"
    fi
}

show_profile_detail() {
    local name="$1"
    local profile
    if [[ "$name" == "$OFFICIAL_PROFILE" ]]; then
        printf "名称: %s\n" "$OFFICIAL_PROFILE"
        printf "模式: 官方 Claude Code\n"
        printf "环境: 清理 ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY\n"
        return
    fi
    profile="$(get_profile_json "$name")"

    printf "名称: %s\n" "$name"
    printf "Base URL: %s\n" "$(jq -r '.base_url' <<<"$profile")"
    printf "API Key: %s\n" "$(mask_api_key "$(jq -r '.api_key' <<<"$profile")")"
}

test_profile() {
    local name="$1"
    local profile
    local base_url
    local api_key
    local endpoint
    local http_code

    if [[ "$name" == "$OFFICIAL_PROFILE" ]]; then
        warn "官方模式不需要测试第三方网关"
        return 0
    fi

    profile="$(get_profile_json "$name")"
    base_url="$(jq -r '.base_url' <<<"$profile")"
    api_key="$(jq -r '.api_key' <<<"$profile")"
    endpoint="$(anthropic_models_url "$base_url")"

    info "测试连接: $endpoint"

    http_code="$(
        curl -sS \
            -o /tmp/claude-switch-test.out \
            -w '%{http_code}' \
            -H "x-api-key: $api_key" \
            -H "Authorization: Bearer $api_key" \
            -H 'anthropic-version: 2023-06-01' \
            "$endpoint" || true
    )"

    case "$http_code" in
        200)
            success "连接成功"
            ;;
        401|403)
            error "连接失败：鉴权被拒绝（HTTP $http_code）"
            return 1
            ;;
        404)
            warn "服务可达，但 /v1/models 不存在（HTTP 404）。Claude Code 仍可能可用，请确认网关兼容 Anthropic API。"
            ;;
        000|'')
            error "连接失败：无法访问目标地址"
            return 1
            ;;
        *)
            warn "收到 HTTP $http_code，请根据网关实现判断是否可用"
            [[ -s /tmp/claude-switch-test.out ]] && sed -n '1,10p' /tmp/claude-switch-test.out >&2
            ;;
    esac
}

activate_profile() {
    local name="$1"
    local launch_after="${2:-false}"
    local profile
    local base_url
    local api_key

    profile_exists "$name" || die "配置 '$name' 不存在"

    if [[ "$name" == "$OFFICIAL_PROFILE" ]]; then
        sync_official_environment
        set_current_profile_name "$OFFICIAL_PROFILE"
        success "已切回官方 Claude Code"
        warn "新终端会自动生效；当前终端可执行: source '$ENV_FILE'"
        if [[ "$launch_after" == "true" ]]; then
            launch_claude
        fi
        return
    fi

    profile="$(get_profile_json "$name")"
    base_url="$(jq -r '.base_url' <<<"$profile")"
    api_key="$(jq -r '.api_key' <<<"$profile")"

    sync_shell_environment "$base_url" "$api_key"
    set_current_profile_name "$name"

    success "当前 Claude Code 配置已切换为 '$name'"
    warn "新终端会自动生效；当前终端可执行: source '$ENV_FILE'"

    if [[ "$launch_after" == "true" ]]; then
        launch_claude
    fi
}

launch_claude() {
    if ! has_cmd claude; then
        die "未检测到 claude 命令，无法启动。请先执行: cw --install-claude"
    fi

    exec claude
}

install_node_runtime() {
    if has_cmd npm; then
        return 0
    fi

    info "未检测到 npm，开始安装 Node.js 运行环境"

    if has_cmd apt-get; then
        run_privileged apt-get update
        run_privileged apt-get install -y nodejs npm
        return 0
    fi

    if has_cmd dnf; then
        run_privileged dnf install -y nodejs npm
        return 0
    fi

    if has_cmd yum; then
        run_privileged yum install -y nodejs npm
        return 0
    fi

    if has_cmd pacman; then
        run_privileged pacman -Sy --noconfirm nodejs npm
        return 0
    fi

    if has_cmd brew; then
        brew install node
        return 0
    fi

    die "无法自动安装 npm。请先手动安装 Node.js 和 npm。"
}

install_claude_cli() {
    install_node_runtime
    require_cmd npm "npm 安装失败，请先检查 Node.js 环境。"

    info "安装或升级 Claude Code"
    if npm install -g @anthropic-ai/claude-code; then
        :
    else
        warn "当前用户全局安装失败，尝试使用 sudo"
        run_privileged npm install -g @anthropic-ai/claude-code
    fi

    hash -r
    require_cmd claude "Claude Code 安装后仍不可用，请检查 npm 全局 bin 目录是否在 PATH 中。"
    success "Claude Code 已安装: $(claude --version 2>/dev/null || echo 'claude')"
    activate_profile "$OFFICIAL_PROFILE" false
}

prompt_required() {
    local label="$1"
    local value=""
    while [[ -z "$value" ]]; do
        read -r -p "$label: " value
    done
    printf "%s\n" "$value"
}

prompt_default() {
    local label="$1"
    local default_value="$2"
    local value=""
    read -r -p "$label [$default_value]: " value
    printf "%s\n" "${value:-$default_value}"
}

add_profile_interactive() {
    local name
    local base_url
    local api_key

    name="$(prompt_required '配置名称')"
    base_url="$(prompt_required 'ANTHROPIC_BASE_URL，例如 https://xxx.xx')"
    api_key="$(prompt_required 'ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY')"

    save_profile "$name" "$base_url" "$api_key"
    test_profile "$name" || true
    activate_profile "$name" true
}

edit_profile_interactive() {
    local name="$1"
    local profile
    local base_url
    local api_key
    local new_base_url
    local new_api_key

    [[ "$name" != "$OFFICIAL_PROFILE" ]] || die "官方配置不需要编辑；要使用第三方请新增配置"
    profile_exists "$name" || die "配置 '$name' 不存在"
    profile="$(get_profile_json "$name")"

    base_url="$(jq -r '.base_url' <<<"$profile")"
    api_key="$(jq -r '.api_key' <<<"$profile")"

    new_base_url="$(prompt_default 'ANTHROPIC_BASE_URL' "$base_url")"
    read -r -p "API Key [留空保持不变]: " new_api_key

    save_profile "$name" "$new_base_url" "${new_api_key:-$api_key}"
}

select_profile_interactive() {
    local names
    local index=1
    local choice
    local selected

    mapfile -t names < <(jq -r 'keys[]' "$PROFILES_FILE")

    printf "可用 Claude Code 配置:\n" >&2
    printf " %d) %s\n" "$index" "$OFFICIAL_PROFILE" >&2
    index=$((index + 1))
    for selected in "${names[@]}"; do
        printf " %d) %s\n" "$index" "$selected" >&2
        index=$((index + 1))
    done

    read -r -p "请选择 [1-$(( ${#names[@]} + 1 ))]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || die "输入无效"
    (( choice >= 1 && choice <= ${#names[@]} + 1 )) || die "输入超出范围"

    if (( choice == 1 )); then
        printf "%s\n" "$OFFICIAL_PROFILE"
        return
    fi
    printf "%s\n" "${names[$((choice - 2))]}"
}

manage_profiles_menu() {
    local choice
    local profile_name

    while true; do
        printf "\nClaude Code 配置管理\n"
        printf "1) 查看配置列表\n"
        printf "2) 查看配置详情\n"
        printf "3) 新增配置\n"
        printf "4) 编辑配置\n"
        printf "5) 删除配置\n"
        printf "0) 返回\n"
        read -r -p "选择: " choice

        case "$choice" in
            1) list_profiles ;;
            2) profile_name="$(select_profile_interactive)"; show_profile_detail "$profile_name" ;;
            3) add_profile_interactive ;;
            4) profile_name="$(select_profile_interactive)"; edit_profile_interactive "$profile_name" ;;
            5) profile_name="$(select_profile_interactive)"; delete_profile "$profile_name" ;;
            0) return 0 ;;
            *) warn "无效选项" ;;
        esac
    done
}

show_help() {
    cat <<EOF
Usage: $APP_NAME [option]

Options:
  --install-claude       一键安装或升级 Claude Code
  --official             切回官方 Claude Code，清理第三方环境变量
  --list                 列出所有 Claude Code 配置
  --switch NAME          切换到指定配置并启动 Claude Code
  --activate NAME        只切换配置，不启动 Claude Code
  --test [NAME]          测试指定配置；未传时测试当前配置
  --show [NAME]          显示指定配置详情；未传时显示当前配置
  --add NAME URL KEY     通过命令行新增或覆盖 Claude Code 配置
  --delete NAME          删除指定配置
  --launch               直接启动 Claude Code
  --help                 显示帮助
  --version              显示版本

直接运行不带参数时，会进入交互式菜单。
EOF
}

show_version() {
    printf "%s %s\n" "$APP_NAME" "$VERSION"
}

print_header() {
    if [[ -t 1 ]]; then
        clear
    fi
    printf "%bClaude Code 配置管理器 v%s%b\n\n" "$CYAN" "$VERSION" "$NC"
}

main_menu() {
    local choice
    local selected
    local current

    while true; do
        print_header
        current="$(get_active_profile_name)"
        printf "当前 Claude Code 配置: %s\n\n" "$current"
        printf "1) 配置新的 AgentRouter 并启动\n"
        printf "2) 切换已有配置并启动\n"
        printf "3) 直接启动 Claude Code（使用当前配置）\n"
        printf "4) 管理 Claude Code 配置\n"
        printf "5) 测试当前配置\n"
        printf "6) 一键部署 Claude Code\n"
        printf "7) 切回官方 Claude Code\n"
        printf "0) 退出\n"
        read -r -p "选择: " choice

        case "$choice" in
            1) add_profile_interactive ;;
            2) selected="$(select_profile_interactive)"; activate_profile "$selected" true ;;
            3) launch_claude ;;
            4) manage_profiles_menu ;;
            5)
                current="$(get_active_profile_name)"
                test_profile "$current"
                read -r -p "按回车继续..." _
                ;;
            6)
                install_claude_cli
                read -r -p "按回车继续..." _
                ;;
            7)
                activate_profile "$OFFICIAL_PROFILE" false
                read -r -p "按回车继续..." _
                ;;
            0) exit 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

main() {
    local current=""

    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --version|-v)
            show_version
            ;;
        --install-claude)
            prepare_store
            install_claude_cli
            ;;
        --official)
            prepare_store
            activate_profile "$OFFICIAL_PROFILE" false
            ;;
        --list)
            prepare_store
            list_profiles
            ;;
        --switch)
            prepare_store
            [[ $# -ge 2 ]] || die "用法: $APP_NAME --switch NAME"
            activate_profile "$2" true
            ;;
        --activate)
            prepare_store
            [[ $# -ge 2 ]] || die "用法: $APP_NAME --activate NAME"
            activate_profile "$2" false
            ;;
        --test)
            prepare_store
            require_cmd curl "缺少依赖 curl，请先安装，例如: sudo apt install curl"
            if [[ $# -ge 2 ]]; then
                test_profile "$2"
            else
                current="$(get_active_profile_name)"
                test_profile "$current"
            fi
            ;;
        --show)
            prepare_store
            if [[ $# -ge 2 ]]; then
                show_profile_detail "$2"
            else
                current="$(get_active_profile_name)"
                show_profile_detail "$current"
            fi
            ;;
        --add)
            prepare_store
            [[ $# -eq 4 ]] || die "用法: $APP_NAME --add NAME URL KEY"
            save_profile "$2" "$3" "$4"
            ;;
        --delete)
            prepare_store
            [[ $# -ge 2 ]] || die "用法: $APP_NAME --delete NAME"
            delete_profile "$2"
            ;;
        --launch)
            launch_claude
            ;;
        "")
            prepare_store
            require_cmd curl "缺少依赖 curl，请先安装，例如: sudo apt install curl"
            main_menu
            ;;
        *)
            die "未知参数: $1，使用 --help 查看帮助"
            ;;
    esac
}

main "$@"

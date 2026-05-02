#!/usr/bin/env bash

set -euo pipefail

VERSION="3.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_NAME="codex-switch"
DEFAULT_PROVIDER="openai-compatible"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/codex-switch"
PROFILES_FILE="$CONFIG_ROOT/profiles.json"
STATE_FILE="$CONFIG_ROOT/state.json"
ENV_FILE="$CONFIG_ROOT/current.env"

CODEX_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex"
CODEX_CONFIG_FILE="$CODEX_CONFIG_DIR/config.json"
CODEX_TOML_DIR="$HOME/.codex"
CODEX_TOML_FILE="$CODEX_TOML_DIR/config.toml"

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

init_store() {
    mkdir -p "$CONFIG_ROOT"
    [[ -f "$PROFILES_FILE" ]] || printf '{}\n' > "$PROFILES_FILE"
    [[ -f "$STATE_FILE" ]] || printf '{"current_profile":""}\n' > "$STATE_FILE"
    jq '
        with_entries(
            .value |= (
                if type == "object" then
                    .provider = (.provider // "openai-compatible")
                else
                    .
                end
            )
        )
    ' "$PROFILES_FILE" > "${PROFILES_FILE}.tmp"
    mv "${PROFILES_FILE}.tmp" "$PROFILES_FILE"
}

normalize_base_url() {
    local value="$1"
    value="${value%/}"
    printf "%s\n" "$value"
}

normalize_provider() {
    local provider="${1:-$DEFAULT_PROVIDER}"
    case "$provider" in
        openai|openai-compatible|openai_compatible)
            printf "openai-compatible\n"
            ;;
        gemini|google|google-gemini)
            printf "gemini\n"
            ;;
        ollama|local-ollama)
            printf "ollama\n"
            ;;
        openrouter)
            printf "openrouter\n"
            ;;
        anthropic)
            printf "anthropic\n"
            ;;
        *)
            printf "%s\n" "$provider"
            ;;
    esac
}

default_model_for_provider() {
    case "$(normalize_provider "${1:-$DEFAULT_PROVIDER}")" in
        gemini) printf "gemini-2.5-pro\n" ;;
        ollama) printf "qwen2.5-coder:latest\n" ;;
        anthropic) printf "claude-sonnet-4-20250514\n" ;;
        *) printf "gpt-5.4\n" ;;
    esac
}

default_base_url_for_provider() {
    case "$(normalize_provider "${1:-$DEFAULT_PROVIDER}")" in
        ollama) printf "http://127.0.0.1:11434/v1\n" ;;
        *) printf "\n" ;;
    esac
}

provider_supports_codex_sync() {
    case "$(normalize_provider "${1:-$DEFAULT_PROVIDER}")" in
        anthropic) return 1 ;;
        *) return 0 ;;
    esac
}

provider_note() {
    case "$(normalize_provider "${1:-$DEFAULT_PROVIDER}")" in
        gemini)
            printf "Gemini 需要可被 Codex 使用的兼容入口；建议填写 Gemini 的 OpenAI-compatible 网关地址。\n"
            ;;
        ollama)
            printf "Ollama 建议使用 http://127.0.0.1:11434/v1，并确保本地模型已拉取。\n"
            ;;
        anthropic)
            printf "Anthropic 原生接口不能直接按 OpenAI provider 写入 Codex；该配置可保存，但不会自动同步到 Codex CLI。\n"
            ;;
        *)
            printf "\n"
            ;;
    esac
}

profile_exists() {
    local name="$1"
    jq -e --arg name "$name" 'has($name)' "$PROFILES_FILE" >/dev/null
}

get_profile_json() {
    local name="$1"
    jq -e --arg name "$name" '.[$name]' "$PROFILES_FILE"
}

get_current_profile_name() {
    jq -r '.current_profile // ""' "$STATE_FILE"
}

set_current_profile_name() {
    local name="$1"
    jq --arg name "$name" '.current_profile = $name' "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

write_env_file() {
    local provider="$1"
    local base_url="$2"
    local api_key="$3"
    local model="$4"

    cat > "$ENV_FILE" <<EOF
export OPENAI_BASE_URL='$base_url'
export OPENAI_API_KEY='$api_key'
export OPENAI_MODEL='$model'
EOF

    case "$(normalize_provider "$provider")" in
        gemini)
            cat >> "$ENV_FILE" <<EOF
export GEMINI_API_KEY='$api_key'
export GOOGLE_API_KEY='$api_key'
EOF
            ;;
        *)
            :
            ;;
    esac
}

update_shell_rc() {
    local rc_file="$1"
    local begin="# >>> codex-switch >>>"
    local end="# <<< codex-switch <<<"
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
        awk -v begin="$begin" -v end="$end" -v block="$block" '
            $0 == begin { print block; skip=1; next }
            $0 == end { skip=0; next }
            !skip { print }
        ' "$rc_file" > "${rc_file}.tmp"
        mv "${rc_file}.tmp" "$rc_file"
    else
        {
            printf "\n%s\n" "$block"
        } >> "$rc_file"
    fi
}

sync_shell_environment() {
    local provider="$1"
    local base_url="$2"
    local api_key="$3"
    local model="$4"

    write_env_file "$provider" "$base_url" "$api_key" "$model"
    update_shell_rc "$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" ]]; then
        update_shell_rc "$HOME/.zshrc"
    fi
}

upsert_toml_root_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if grep -Eq "^${key}[[:space:]]*=" "$file"; then
        sed -i "s|^${key}[[:space:]]*=.*$|${key} = \"${value}\"|" "$file"
    else
        printf "%s = \"%s\"\n%s" "$key" "$value" "$(cat "$file")" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    fi
}

write_codex_toml() {
    local base_url="$1"
    local api_key="$2"
    local model="$3"
    local tmp_file

    mkdir -p "$CODEX_TOML_DIR"
    [[ -f "$CODEX_TOML_FILE" ]] || touch "$CODEX_TOML_FILE"

    upsert_toml_root_key "$CODEX_TOML_FILE" "model_provider" "OpenAI"
    upsert_toml_root_key "$CODEX_TOML_FILE" "model" "$model"

    tmp_file="$(mktemp)"
    awk '
        BEGIN { in_section=0; skip_name=0; skip_base=0; skip_key=0 }
        /^\[model_providers\.OpenAI\]$/ {
            print
            print "name = \"OpenAI\""
            print "base_url = \"__BASE_URL__\""
            print "api_key = \"__API_KEY__\""
            in_section=1
            skip_name=1
            skip_base=1
            skip_key=1
            next
        }
        /^\[/ {
            in_section=0
        }
        in_section && skip_name && /^name[[:space:]]*=/ { next }
        in_section && skip_base && /^base_url[[:space:]]*=/ { next }
        in_section && skip_key && /^api_key[[:space:]]*=/ { next }
        { print }
    ' "$CODEX_TOML_FILE" > "$tmp_file"

    if ! grep -Fq '[model_providers.OpenAI]' "$tmp_file"; then
        {
            printf "\n[model_providers.OpenAI]\n"
            printf "name = \"OpenAI\"\n"
            printf "base_url = \"%s\"\n" "$base_url"
            printf "api_key = \"%s\"\n" "$api_key"
        } >> "$tmp_file"
    else
        sed -i \
            -e "s|__BASE_URL__|$base_url|g" \
            -e "s|__API_KEY__|$api_key|g" \
            "$tmp_file"
    fi

    mv "$tmp_file" "$CODEX_TOML_FILE"
}

sync_codex_cli() {
    local provider="$1"
    local base_url="$2"
    local api_key="$3"
    local model="$4"

    provider="$(normalize_provider "$provider")"

    mkdir -p "$CODEX_CONFIG_DIR"

    if ! provider_supports_codex_sync "$provider"; then
        warn "Provider '$provider' 暂不支持直接同步到 Codex CLI，已跳过 Codex 配置写入"
        return 0
    fi

    if has_cmd codex && codex help config >/dev/null 2>&1; then
        codex config set base_url "$base_url" >/dev/null
        codex config set api_key "$api_key" >/dev/null
        codex config set model "$model" >/dev/null
        success "已同步到官方 Codex CLI"
        return
    fi

    if has_cmd codex; then
        write_codex_toml "$base_url" "$api_key" "$model"
        success "已同步到 ~/.codex/config.toml"
        return
    fi

    jq -n \
        --arg base_url "$base_url" \
        --arg api_key "$api_key" \
        --arg model "$model" \
        '{base_url:$base_url, api_key:$api_key, model:$model}' > "$CODEX_CONFIG_FILE"
    warn "未检测到 codex 命令，已写入本地配置文件: $CODEX_CONFIG_FILE"
}

save_profile() {
    local name="$1"
    local base_url="$2"
    local api_key="$3"
    local model="$4"
    local provider="${5:-$DEFAULT_PROVIDER}"

    base_url="$(normalize_base_url "$base_url")"
    provider="$(normalize_provider "$provider")"

    jq \
        --arg name "$name" \
        --arg provider "$provider" \
        --arg base_url "$base_url" \
        --arg api_key "$api_key" \
        --arg model "$model" \
        '.[$name] = {name:$name, provider:$provider, base_url:$base_url, api_key:$api_key, model:$model}' \
        "$PROFILES_FILE" > "${PROFILES_FILE}.tmp"
    mv "${PROFILES_FILE}.tmp" "$PROFILES_FILE"

    success "配置 '$name' 已保存"
}

delete_profile() {
    local name="$1"

    profile_exists "$name" || die "配置 '$name' 不存在"

    jq --arg name "$name" 'del(.[$name])' "$PROFILES_FILE" > "${PROFILES_FILE}.tmp"
    mv "${PROFILES_FILE}.tmp" "$PROFILES_FILE"

    if [[ "$(get_current_profile_name)" == "$name" ]]; then
        set_current_profile_name ""
    fi

    success "配置 '$name' 已删除"
}

list_profiles() {
    local current
    current="$(get_current_profile_name)"

    if [[ "$(jq 'length' "$PROFILES_FILE")" -eq 0 ]]; then
        warn "还没有保存任何配置"
        return
    fi

    jq -r 'to_entries[] | [.key, (.value.provider // "openai-compatible"), .value.base_url, .value.model] | @tsv' "$PROFILES_FILE" |
    while IFS=$'\t' read -r name provider base_url model; do
        if [[ "$name" == "$current" ]]; then
            printf "* %s\t%s\t%s\t%s\n" "$name" "$provider" "$model" "$base_url"
        else
            printf "  %s\t%s\t%s\t%s\n" "$name" "$provider" "$model" "$base_url"
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
    profile="$(get_profile_json "$name")"

    printf "名称: %s\n" "$name"
    printf "Provider: %s\n" "$(jq -r '.provider // "openai-compatible"' <<<"$profile")"
    printf "Base URL: %s\n" "$(jq -r '.base_url' <<<"$profile")"
    printf "Model: %s\n" "$(jq -r '.model' <<<"$profile")"
    printf "API Key: %s\n" "$(mask_api_key "$(jq -r '.api_key' <<<"$profile")")"
}

test_profile() {
    local name="$1"
    local profile
    local provider
    local base_url
    local api_key
    local endpoint
    local http_code

    profile="$(get_profile_json "$name")"
    provider="$(jq -r '.provider // "openai-compatible"' <<<"$profile")"
    base_url="$(jq -r '.base_url' <<<"$profile")"
    api_key="$(jq -r '.api_key' <<<"$profile")"
    endpoint="$(normalize_base_url "$base_url")/models"

    info "测试连接: $endpoint"

    http_code="$(
        curl -sS \
            -o /tmp/codex-switch-test.out \
            -w '%{http_code}' \
            -H "Authorization: Bearer $api_key" \
            -H 'Content-Type: application/json' \
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
            error "连接失败：接口不存在（HTTP 404），请检查 Base URL 是否包含 /v1"
            return 1
            ;;
        000|'')
            error "连接失败：无法访问目标地址"
            return 1
            ;;
        *)
            error "连接失败：HTTP $http_code"
            [[ -s /tmp/codex-switch-test.out ]] && sed -n '1,10p' /tmp/codex-switch-test.out >&2
            return 1
            ;;
    esac
}

activate_profile() {
    local name="$1"
    local launch_after="${2:-false}"
    local profile
    local provider
    local base_url
    local api_key
    local model

    profile_exists "$name" || die "配置 '$name' 不存在"
    profile="$(get_profile_json "$name")"
    provider="$(jq -r '.provider // "openai-compatible"' <<<"$profile")"
    base_url="$(jq -r '.base_url' <<<"$profile")"
    api_key="$(jq -r '.api_key' <<<"$profile")"
    model="$(jq -r '.model' <<<"$profile")"

    sync_shell_environment "$provider" "$base_url" "$api_key" "$model"
    sync_codex_cli "$provider" "$base_url" "$api_key" "$model"
    set_current_profile_name "$name"

    success "当前配置已切换为 '$name'"
    warn "新终端会自动生效；当前终端可执行: source '$ENV_FILE'"

    if [[ "$launch_after" == "true" ]]; then
        launch_codex
    fi
}

launch_codex() {
    if ! has_cmd codex; then
        die "未检测到 codex 命令，无法启动。请先安装官方 Codex CLI。"
    fi

    exec codex
}

launch_gemini() {
    if ! has_cmd gemini; then
        die "未检测到 gemini 命令，无法启动。请先执行 --install-gemini。"
    fi

    exec gemini
}

run_privileged() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
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

write_gemini_wrapper() {
    local target="/usr/local/bin/gemini"
    local bin_path="$1"
    local wrapper_source

    wrapper_source="$(mktemp)"
    cat > "$wrapper_source" <<EOF
#!/usr/bin/env bash
exec node "$bin_path" "\$@"
EOF

    run_privileged install -m 755 "$wrapper_source" "$target"
    rm -f "$wrapper_source"
}

ensure_gemini_command() {
    local prefix
    local package_dir=""
    local package_json=""
    local bin_rel=""
    local bin_path=""

    has_cmd gemini && return 0

    prefix="$(npm prefix -g 2>/dev/null || npm config get prefix 2>/dev/null || true)"
    for package_dir in \
        "$prefix/lib/node_modules/@google/gemini-cli" \
        "$prefix/lib/node_modules/@google-dev/gemini-cli" \
        "/usr/lib/node_modules/@google/gemini-cli" \
        "/usr/local/lib/node_modules/@google/gemini-cli"
    do
        package_json="$package_dir/package.json"
        if [[ -f "$package_json" ]]; then
            bin_rel="$(jq -r '.bin.gemini // empty' "$package_json" 2>/dev/null || true)"
            if [[ -z "$bin_rel" ]]; then
                bin_rel="$(jq -r 'if (.bin|type)=="string" then .bin else empty end' "$package_json" 2>/dev/null || true)"
            fi
            if [[ -n "$bin_rel" && -f "$package_dir/$bin_rel" ]]; then
                bin_path="$package_dir/$bin_rel"
                write_gemini_wrapper "$bin_path"
                hash -r
                has_cmd gemini && return 0
            fi
        fi
    done

    return 1
}

install_codex_cli() {
    local current_profile=""

    install_node_runtime
    require_cmd npm "npm 安装失败，请先检查 Node.js 环境。"

    info "安装或升级官方 Codex CLI"
    if npm install -g @openai/codex; then
        :
    else
        warn "当前用户全局安装失败，尝试使用 sudo"
        run_privileged npm install -g @openai/codex
    fi

    hash -r
    require_cmd codex "Codex CLI 安装后仍不可用，请检查 npm 全局 bin 目录是否在 PATH 中。"
    success "Codex CLI 已安装: $(codex --version 2>/dev/null || echo 'codex')"

    current_profile="$(get_current_profile_name)"
    if [[ -n "$current_profile" ]] && profile_exists "$current_profile"; then
        sync_codex_cli \
            "$(jq -r --arg name "$current_profile" '.[$name].provider // "openai-compatible"' "$PROFILES_FILE")" \
            "$(jq -r --arg name "$current_profile" '.[$name].base_url' "$PROFILES_FILE")" \
            "$(jq -r --arg name "$current_profile" '.[$name].api_key' "$PROFILES_FILE")" \
            "$(jq -r --arg name "$current_profile" '.[$name].model' "$PROFILES_FILE")"
        success "已同步当前配置 '$current_profile' 到 Codex CLI"
    else
        warn "当前没有激活配置。你可以先运行 'sw' 配置中转站，或直接执行 'codex --login' 登录。"
    fi
}

install_gemini_cli() {
    local current_profile=""
    local current_provider=""

    install_node_runtime
    require_cmd npm "npm 安装失败，请先检查 Node.js 环境。"

    info "安装或升级 Gemini CLI"
    if npm install -g @google/gemini-cli; then
        :
    else
        warn "当前用户全局安装失败，尝试使用 sudo"
        run_privileged npm install -g @google/gemini-cli
    fi

    hash -r
    ensure_gemini_command || true
    require_cmd gemini "Gemini CLI 安装后仍不可用，请检查 npm 全局 bin 目录是否在 PATH 中。"
    success "Gemini CLI 已安装"

    current_profile="$(get_current_profile_name)"
    if [[ -n "$current_profile" ]] && profile_exists "$current_profile"; then
        current_provider="$(jq -r --arg name "$current_profile" '.[$name].provider // "openai-compatible"' "$PROFILES_FILE")"
        if [[ "$(normalize_provider "$current_provider")" == "gemini" ]]; then
            sync_shell_environment \
                "$current_provider" \
                "$(jq -r --arg name "$current_profile" '.[$name].base_url' "$PROFILES_FILE")" \
                "$(jq -r --arg name "$current_profile" '.[$name].api_key' "$PROFILES_FILE")" \
                "$(jq -r --arg name "$current_profile" '.[$name].model' "$PROFILES_FILE")"
            success "已同步当前 Gemini 配置 '$current_profile' 到环境变量"
        else
            warn "当前激活配置不是 gemini。Gemini CLI 首次启动时也可以选择 Google 登录。"
        fi
    else
        warn "当前没有激活配置。你可以先运行 'sw' 添加 gemini 配置，或直接执行 'gemini' 后按提示登录。"
    fi
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

select_provider_interactive() {
    local choice

    printf "Provider 类型:\n"
    printf "1) openai-compatible\n"
    printf "2) gemini\n"
    printf "3) ollama\n"
    printf "4) openrouter\n"
    printf "5) anthropic\n"
    read -r -p "请选择 [1-5, 默认 1]: " choice

    case "${choice:-1}" in
        1) printf "openai-compatible\n" ;;
        2) printf "gemini\n" ;;
        3) printf "ollama\n" ;;
        4) printf "openrouter\n" ;;
        5) printf "anthropic\n" ;;
        *) printf "openai-compatible\n" ;;
    esac
}

add_profile_interactive() {
    local name
    local provider
    local base_url
    local api_key
    local model

    name="$(prompt_required '配置名称')"
    provider="$(select_provider_interactive)"
    base_url="$(prompt_default 'API Base URL' "$(default_base_url_for_provider "$provider")")"
    if [[ -z "$base_url" ]]; then
        base_url="$(prompt_required 'API Base URL')"
    fi
    if [[ "$(normalize_provider "$provider")" == "ollama" ]]; then
        read -r -p "API Key [Ollama 默认可留空]: " api_key
    else
        api_key="$(prompt_required 'API Key')"
    fi
    model="$(prompt_default '默认模型' "$(default_model_for_provider "$provider")")"

    save_profile "$name" "$base_url" "$api_key" "$model" "$provider"
    warn "$(provider_note "$provider")"
    test_profile "$name" || true
    activate_profile "$name" true
}

edit_profile_interactive() {
    local name="$1"
    local profile
    local provider
    local base_url
    local api_key
    local model
    local new_provider
    local new_base_url
    local new_api_key
    local new_model

    profile_exists "$name" || die "配置 '$name' 不存在"
    profile="$(get_profile_json "$name")"

    provider="$(jq -r '.provider // "openai-compatible"' <<<"$profile")"
    base_url="$(jq -r '.base_url' <<<"$profile")"
    api_key="$(jq -r '.api_key' <<<"$profile")"
    model="$(jq -r '.model' <<<"$profile")"

    new_provider="$(prompt_default 'Provider' "$provider")"
    new_base_url="$(prompt_default 'API Base URL' "$base_url")"
    if [[ "$(normalize_provider "$new_provider")" == "ollama" ]]; then
        read -r -p "API Key [留空保持不变，可为空]: " new_api_key
    else
        read -r -p "API Key [留空保持不变]: " new_api_key
    fi
    new_model="$(prompt_default '默认模型' "$model")"

    save_profile "$name" "$new_base_url" "${new_api_key:-$api_key}" "$new_model" "$new_provider"
}

select_profile_interactive() {
    local names
    local index=1
    local choice
    local selected

    mapfile -t names < <(jq -r 'keys[]' "$PROFILES_FILE")
    [[ "${#names[@]}" -gt 0 ]] || die "还没有保存任何配置"

    printf "可用配置:\n" >&2
    for selected in "${names[@]}"; do
        printf " %d) %s\n" "$index" "$selected" >&2
        index=$((index + 1))
    done

    read -r -p "请选择 [1-${#names[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || die "输入无效"
    (( choice >= 1 && choice <= ${#names[@]} )) || die "输入超出范围"

    printf "%s\n" "${names[$((choice - 1))]}"
}

manage_profiles_menu() {
    local choice
    local profile_name

    while true; do
        printf "\n配置管理\n"
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
  --install-codex        一键安装或升级官方 Codex CLI
  --install-gemini       一键安装或升级 Gemini CLI
  --list                 列出所有配置
  --switch NAME          切换到指定配置并启动 Codex
  --activate NAME        只切换配置，不启动 Codex
  --test [NAME]          测试指定配置；未传时测试当前配置
  --show [NAME]          显示指定配置详情；未传时显示当前配置
  --add NAME URL KEY MODEL
                         通过命令行新增或覆盖 openai-compatible 配置
  --add-provider NAME PROVIDER URL KEY MODEL
                         通过命令行新增或覆盖指定 provider 配置
  --delete NAME          删除指定配置
  --launch               直接启动 Codex
  --launch-gemini        直接启动 Gemini CLI
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
    printf "%bCodex 配置管理器 v%s%b\n\n" "$CYAN" "$VERSION" "$NC"
}

main_menu() {
    local choice
    local selected
    local current

    while true; do
        current="$(get_current_profile_name)"
        print_header
        printf "当前配置: %s\n\n" "${current:-未设置}"
        printf "1) 配置新的中转站并启动\n"
        printf "2) 切换已有配置并启动\n"
        printf "3) 直接启动（使用当前配置）\n"
        printf "4) 管理配置\n"
        printf "5) 测试当前配置\n"
        printf "6) 一键部署官方 Codex CLI\n"
        printf "7) 一键部署 Gemini CLI\n"
        printf "8) 直接启动 Gemini CLI\n"
        printf "0) 退出\n"
        read -r -p "选择: " choice

        case "$choice" in
            1) add_profile_interactive ;;
            2) selected="$(select_profile_interactive)"; activate_profile "$selected" true ;;
            3) launch_codex ;;
            4) manage_profiles_menu ;;
            5)
                current="$(get_current_profile_name)"
                [[ -n "$current" ]] || die "当前没有已激活的配置"
                test_profile "$current"
                read -r -p "按回车继续..." _
                ;;
            6)
                install_codex_cli
                read -r -p "按回车继续..." _
                ;;
            7)
                install_gemini_cli
                read -r -p "按回车继续..." _
                ;;
            8) launch_gemini ;;
            0) exit 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --version|-v)
            show_version
            ;;
        --install-codex)
            init_store
            install_codex_cli
            ;;
        --install-gemini)
            init_store
            install_gemini_cli
            ;;
        --list)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            list_profiles
            ;;
        --switch)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            [[ $# -ge 2 ]] || die "用法: $APP_NAME --switch NAME"
            activate_profile "$2" true
            ;;
        --activate)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            [[ $# -ge 2 ]] || die "用法: $APP_NAME --activate NAME"
            activate_profile "$2" false
            ;;
        --test)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            require_cmd curl "缺少依赖 curl，请先安装，例如: sudo apt install curl"
            if [[ $# -ge 2 ]]; then
                test_profile "$2"
            else
                local current
                current="$(get_current_profile_name)"
                [[ -n "$current" ]] || die "当前没有已激活的配置"
                test_profile "$current"
            fi
            ;;
        --show)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            if [[ $# -ge 2 ]]; then
                show_profile_detail "$2"
            else
                local current
                current="$(get_current_profile_name)"
                [[ -n "$current" ]] || die "当前没有已激活的配置"
                show_profile_detail "$current"
            fi
            ;;
        --add)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            [[ $# -eq 5 || $# -eq 6 ]] || die "用法: $APP_NAME --add NAME URL KEY MODEL [PROVIDER]"
            save_profile "$2" "$3" "$4" "$5" "${6:-$DEFAULT_PROVIDER}"
            ;;
        --add-provider)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            [[ $# -eq 6 ]] || die "用法: $APP_NAME --add-provider NAME PROVIDER URL KEY MODEL"
            save_profile "$2" "$4" "$5" "$6" "$3"
            ;;
        --delete)
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            [[ $# -ge 2 ]] || die "用法: $APP_NAME --delete NAME"
            delete_profile "$2"
            ;;
        --launch)
            launch_codex
            ;;
        --launch-gemini)
            launch_gemini
            ;;
        "")
            init_store
            require_cmd jq "缺少依赖 jq，请先安装，例如: sudo apt install jq"
            require_cmd curl "缺少依赖 curl，请先安装，例如: sudo apt install curl"
            main_menu
            ;;
        *)
            die "未知参数: $1，使用 --help 查看帮助"
            ;;
    esac
}

main "$@"

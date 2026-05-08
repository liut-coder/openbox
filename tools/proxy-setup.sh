#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
DEFAULT_BASE_URL="https://raw.githubusercontent.com/liut-coder/openbox/main"
DOWNLOAD_BASE_URL="${OPENBOX_INSTALL_BASE_URL:-$DEFAULT_BASE_URL}"
TMP_FILES=()

DEFAULT_PROXY_HOST="proxyd.picpi.top"
PROXY_HOST="${PROXY_HOST:-$DEFAULT_PROXY_HOST}"
PROXY_URL="https://${PROXY_HOST}/"

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

resolve_source() {
    local source_name="$1"
    local local_source="$SCRIPT_DIR/$source_name"
    local tmp_source

    if [[ -f "$local_source" ]]; then
        printf "%s\n" "$local_source"
        return 0
    fi

    has_cmd curl || { log "需要 curl"; exit 1; }
    tmp_source="$(mktemp "/tmp/openbox.XXXXXX")"
    TMP_FILES+=("$tmp_source")
    curl -fsSL "$DOWNLOAD_BASE_URL/$source_name" -o "$tmp_source"
    chmod +x "$tmp_source"
    printf "%s\n" "$tmp_source"
}

cleanup() {
    local file
    for file in "${TMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

set_proxy() {
    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"

    # Git
    git config --global http.proxy "$PROXY_URL"
    git config --global https.proxy "$PROXY_URL"

    # NPM
    if has_cmd npm; then
        npm config set proxy "$PROXY_URL" 2>/dev/null || true
        npm config set https-proxy "$PROXY_URL" 2>/dev/null || true
    fi

    # Pip
    if has_cmd pip; then
        pip config set global.proxy "$PROXY_URL" 2>/dev/null || \
        export PIP_PROXY="$PROXY_URL"
    fi

    # Docker
    mkdir -p ~/.docker
    cat > ~/.docker/config.json << EOF
{
  "proxies": {
    "default": {
      "httpProxy": "$PROXY_URL",
      "httpsProxy": "$PROXY_URL",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
EOF

    log "✅ 代理已启用: $PROXY_URL"
}

unset_proxy() {
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy PIP_PROXY

    git config --global --unset http.proxy 2>/dev/null || true
    git config --global --unset https.proxy 2>/dev/null || true

    if has_cmd npm; then
        npm config delete proxy 2>/dev/null || true
        npm config delete https-proxy 2>/dev/null || true
    fi

    log "❌ 代理已禁用"
}

show_status() {
    log "=== 当前代理状态 ==="
    log "HTTP_PROXY:     ${HTTP_PROXY:-未设置}"
    log "HTTPS_PROXY:    ${HTTPS_PROXY:-未设置}"
    log "Git http.proxy: $(git config --global http.proxy 2>/dev/null || echo '未设置')"
    if has_cmd npm; then
        log "NPM proxy:       $(npm config get proxy 2>/dev/null || echo '未设置')"
    fi
    log ""
    log "当前代理: $PROXY_URL"
    log "如需更换代理，可设置环境变量: PROXY_HOST=your-proxy.com $0 on"
}

test_proxy() {
    log "测试代理连通性..."
    local test_url="https://raw.githubusercontent.com/"
    local result=$(curl -sS -w "%{http_code}" -o /dev/null --proxy "$PROXY_URL" "$test_url" 2>&1) || result="failed"
    if [[ "$result" == "200" ]]; then
        log "✅ 代理正常"
        return 0
    else
        log "❌ 代理测试失败: $result"
        return 1
    fi
}

show_help() {
    cat <<EOF
proxy-setup 下载代理配置工具

用法:
  proxy-setup on           启用代理
  proxy-setup off          禁用代理
  proxy-setup status       查看状态
  proxy-setup test         测试代理连通性
  proxy-setup -h|--help    查看帮助

环境变量:
  PROXY_HOST               代理地址，默认 $DEFAULT_PROXY_HOST

示例:
  # 使用默认代理
  proxy-setup on

  # 使用自定义代理
  PROXY_HOST=my-proxy.com proxy-setup on

  # 查看状态
  proxy-setup status

  # 一键安装到系统
  curl -fsSL $DEFAULT_BASE_URL/proxy-setup.sh | bash -s on
EOF
}

main() {
    trap cleanup EXIT

    case "${1:-status}" in
        on|enable)
            set_proxy
            ;;
        off|disable)
            unset_proxy
            ;;
        test)
            test_proxy
            ;;
        status)
            show_status
            ;;
        -h|--help)
            show_help
            ;;
        *)
            die "未知命令: $1。使用 proxy-setup -h 查看帮助。"
            ;;
    esac
}

main "$@"
#!/usr/bin/env bash
# return-route — 回程路由测试入口

set -euo pipefail

URL="https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh"

usage() {
  cat <<'EOF'
用法: return-route [参数...]
别名: route

说明:
  调用上游脚本：回程路由测试。
  额外参数会原样传给上游脚本。

示例:
  route
  return-route
EOF
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "缺少 curl，请先安装 curl" >&2
  exit 1
fi

exec bash <(curl -fsSL "$URL") "$@"

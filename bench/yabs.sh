#!/usr/bin/env bash
# yabs — YABS 服务器性能测试入口

set -euo pipefail

URL="https://yabs.sh"

usage() {
  cat <<'EOF'
用法: yabs [参数...]
别名: yabs

说明:
  调用上游脚本：YABS 服务器性能测试。
  额外参数会原样传给上游脚本。

示例:
  yabs
  yabs
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

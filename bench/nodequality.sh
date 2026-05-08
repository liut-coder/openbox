#!/usr/bin/env bash
# nodequality — NodeQuality 服务器质量测试入口

set -euo pipefail

URL="https://run.NodeQuality.com"

usage() {
  cat <<'EOF'
用法: nodequality [参数...]
别名: nq

说明:
  调用 NodeQuality 官方脚本进行服务器质量测试。
  额外参数会原样传给上游脚本。

示例:
  nq
  nodequality
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

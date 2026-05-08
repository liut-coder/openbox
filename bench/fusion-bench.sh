#!/usr/bin/env bash
# fusion-bench — 融合怪 VPS 综合测试入口

set -euo pipefail

URL="https://bash.spiritlhl.net/ecs"

usage() {
  cat <<'EOF'
用法: fusion-bench [参数...]
别名: fjg

说明:
  调用融合怪 VPS 综合测试脚本。
  额外参数会原样传给上游脚本。

示例:
  fjg
  fusion-bench
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

#!/usr/bin/env bash
# ip-quality — Check.Place IP 质量测试入口

set -euo pipefail

URL="https://Check.Place"

usage() {
  cat <<'EOF'
用法: ip-quality [参数...]
别名: ipq

说明:
  调用上游脚本：IP 质量测试。
  额外参数会原样传给上游脚本。

示例:
  ipq
  ip-quality
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

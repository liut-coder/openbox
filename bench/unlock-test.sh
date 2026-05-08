#!/usr/bin/env bash
# unlock-test — 流媒体解锁测试入口

set -euo pipefail

URL="https://Media.Check.Place"

usage() {
  cat <<'EOF'
用法: unlock-test [参数...]
别名: unlock

说明:
  调用上游脚本：流媒体解锁测试。
  额外参数会原样传给上游脚本。

示例:
  unlock
  unlock-test
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

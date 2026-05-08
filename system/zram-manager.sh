#!/usr/bin/env bash
# zram-manager — ZRAM 常用安装 / 状态入口

set -euo pipefail

usage() {
  cat <<'EOF'
用法: zram-manager <status|help>
别名: zram
EOF
}

case "${1:-status}" in
  -h|--help|help) usage; exit 0 ;;
esac

case "${1:-status}" in
  status)
    if command -v zramctl >/dev/null 2>&1; then
      zramctl
    else
      echo "zramctl 不可用"
      exit 1
    fi
    ;;
  *) usage; exit 1 ;;
esac

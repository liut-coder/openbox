#!/usr/bin/env bash
# swap-manager — Swap 常用查看 / 创建入口

set -euo pipefail

usage() {
  cat <<'EOF'
用法: swap-manager [show|off|on|help]
别名: swap
EOF
}

case "${1:-show}" in
  -h|--help|help) usage; exit 0 ;;
esac

case "${1:-show}" in
  show)
    swapon --show 2>/dev/null || true
    free -h
    ;;
  off)
    swapoff -a
    swapon --show
    ;;
  on)
    if [[ -f /swapfile ]]; then
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      swapon --show
    else
      echo "/swapfile 不存在" >&2
      exit 1
    fi
    ;;
  *) usage; exit 1 ;;
esac

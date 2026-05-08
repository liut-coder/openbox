#!/usr/bin/env bash
# disk-usage — 目录磁盘占用快速查看

set -euo pipefail

TARGET="${1:-.}"

usage() {
  cat <<'EOF'
用法: disk-usage [目录]
别名: dux
EOF
}

case "$TARGET" in
  -h|--help|help) usage; exit 0 ;;
esac

if [[ ! -e "$TARGET" ]]; then
  echo "目标不存在: $TARGET" >&2
  exit 1
fi

du -sh "$TARGET"

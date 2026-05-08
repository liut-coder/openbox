#!/usr/bin/env bash
# service-manager — systemd 服务常用管理入口

set -euo pipefail

usage() {
  cat <<'EOF'
用法: service-manager <start|stop|restart|status|enable|disable> <服务名>
别名: svc
EOF
}

case "${1:-}" in
  -h|--help|help|"") usage; exit 0 ;;
esac

ACTION="$1"
SERVICE="${2:-}"
[[ -n "$SERVICE" ]] || { usage; exit 1; }

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl 不可用" >&2
  exit 1
fi

case "$ACTION" in
  start|stop|restart|status|enable|disable) ;;
  *) usage; exit 1 ;;
esac

systemctl "$ACTION" "$SERVICE"
systemctl --no-pager --full status "$SERVICE" || true

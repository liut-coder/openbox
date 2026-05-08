#!/usr/bin/env bash
# agent-restart — 常用服务安全重启入口

set -euo pipefail

usage() {
  cat <<'EOF'
用法: agent-restart <服务名|all> [--dry-run]

常用别名:
  caddy / nginx / docker / ssh / sshd / cron / fail2ban / hermes-gateway

示例:
  agent-restart caddy
  agent-restart docker --dry-run
  agent-restart all
EOF
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }
run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"
  elif has_cmd sudo; then sudo "$@"
  else echo "需要 root 或 sudo" >&2; exit 1
  fi
}

DRY_RUN=0
TARGET="${1:-}"
[[ -n "$TARGET" ]] || { usage; exit 1; }
shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $arg" >&2; usage; exit 1 ;;
  esac
done

case "$TARGET" in
  -h|--help|help) usage; exit 0 ;;
  ssh) SERVICE="sshd" ;;
  cron) SERVICE="cron" ;;
  hermes|gateway|hermes-gateway) SERVICE="hermes-gateway" ;;
  *) SERVICE="$TARGET" ;;
esac

restart_one() {
  local svc="$1"
  if ! has_cmd systemctl; then
    echo "systemctl 不可用，无法重启 $svc" >&2
    return 1
  fi
  echo "▶ 重启: $svc"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run: systemctl restart $svc"
    return 0
  fi
  run_privileged systemctl restart "$svc"
  run_privileged systemctl --no-pager --full status "$svc" || true
}

if [[ "$SERVICE" == "all" ]]; then
  for svc in caddy nginx docker fail2ban cron sshd; do
    systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 && restart_one "$svc" || true
  done
else
  restart_one "$SERVICE"
fi

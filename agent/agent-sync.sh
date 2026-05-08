#!/usr/bin/env bash
# agent-sync — 常用刷新/同步入口：包索引、证书、服务 reload

set -euo pipefail

usage() {
  cat <<'EOF'
用法: agent-sync <目标> [--dry-run]

目标:
  packages    刷新系统包索引
  certs       尝试续签证书并 reload caddy/nginx
  services    reload systemd 并显示失败服务
  openbox     刷新 openbox 安装器缓存
  all         依次执行 packages/certs/services/openbox

示例:
  agent-sync packages
  agent-sync all --dry-run
EOF
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }
run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"
  elif has_cmd sudo; then sudo "$@"
  else echo "需要 root 或 sudo" >&2; exit 1
  fi
}
run() {
  echo "+ $*"
  [[ "$DRY_RUN" -eq 1 ]] || "$@"
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

sync_packages() {
  echo "## 刷新包索引"
  if has_cmd apt-get; then run run_privileged apt-get update
  elif has_cmd dnf; then run run_privileged dnf makecache
  elif has_cmd yum; then run run_privileged yum makecache
  elif has_cmd pacman; then run run_privileged pacman -Sy
  elif has_cmd apk; then run run_privileged apk update
  else echo "未识别包管理器，跳过"
  fi
}

sync_certs() {
  echo "## 证书续签 / 服务 reload"
  if has_cmd certbot; then run run_privileged certbot renew --quiet || true; fi
  if has_cmd systemctl; then
    systemctl list-unit-files caddy.service >/dev/null 2>&1 && run run_privileged systemctl reload caddy || true
    systemctl list-unit-files nginx.service >/dev/null 2>&1 && run run_privileged systemctl reload nginx || true
  fi
}

sync_services() {
  echo "## systemd 刷新"
  if has_cmd systemctl; then
    run run_privileged systemctl daemon-reload
    systemctl --failed --no-pager || true
  else
    echo "systemctl 不可用，跳过"
  fi
}

sync_openbox() {
  echo "## 刷新 openbox 缓存"
  run rm -f "${HOME:-/root}/.cache/openbox/install.sh"
  if has_cmd curl; then
    run bash -c 'curl -fsSL https://sh.misk.cc/install.sh >/tmp/openbox-install-check.sh && bash -n /tmp/openbox-install-check.sh'
  fi
}

case "$TARGET" in
  -h|--help|help) usage ;;
  packages) sync_packages ;;
  certs) sync_certs ;;
  services) sync_services ;;
  openbox) sync_openbox ;;
  all)
    sync_packages
    sync_certs
    sync_services
    sync_openbox
    ;;
  *) echo "未知目标: $TARGET" >&2; usage; exit 1 ;;
esac

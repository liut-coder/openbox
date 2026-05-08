#!/usr/bin/env bash
# system-info — 服务器系统信息汇总

set -euo pipefail

usage() {
  cat <<'EOF'
用法: system-info
别名: sysinfo

说明:
  输出系统、内存、磁盘、负载、监听端口的简要信息。
EOF
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

printf '## 系统\n'
if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "OS: ${PRETTY_NAME:-unknown}"; fi
printf 'Kernel: %s\n' "$(uname -r)"
printf 'Host: %s\n' "$(hostname)"
printf 'Uptime: %s\n' "$(uptime -p 2>/dev/null || uptime)"

printf '\n## 资源\n'
free -h 2>/dev/null || true
printf '\n'
df -hT / 2>/dev/null || df -h / 2>/dev/null || true

printf '\n## 负载\n'
uptime
printf '\nTop CPU:\n'
ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 8 || true

printf '\n## 端口\n'
ss -tulpen 2>/dev/null | head -n 25 || true

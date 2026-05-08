#!/usr/bin/env bash
# agent-status — 服务器常用快速状态面板

set -euo pipefail

has_cmd() { command -v "$1" >/dev/null 2>&1; }
hr() { printf '%s\n' '────────────────────────────────────────'; }
section() { printf '\n## %s\n' "$1"; hr; }

printf '📦 Agent Status\n'
printf '时间: %s\n' "$(date '+%F %T %Z')"
printf '主机: %s\n' "$(hostname 2>/dev/null || echo unknown)"

section "系统"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
else
  printf 'OS: %s\n' "$(uname -a)"
fi
printf 'Kernel: %s\n' "$(uname -r)"
printf 'Uptime: %s\n' "$(uptime -p 2>/dev/null || uptime)"

section "资源"
if has_cmd free; then
  free -h
else
  printf 'free: 未安装\n'
fi
printf '\n磁盘:\n'
df -hT / 2>/dev/null || df -h /

section "负载 / 进程"
uptime
printf '\nTop CPU:\n'
ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 8 || true

section "网络"
printf '公网 IPv4: '
curl -4fsS --max-time 3 https://ipinfo.io/ip 2>/dev/null || printf '获取失败'
printf '\n公网 IPv6: '
curl -6fsS --max-time 3 https://v6.ipinfo.io/ip 2>/dev/null || printf '无/获取失败'
printf '\n'
if has_cmd ss; then
  printf '\n监听端口:\n'
  ss -tulpen 2>/dev/null | head -n 30 || true
fi

section "服务概览"
if has_cmd systemctl; then
  systemctl --failed --no-pager 2>/dev/null || true
else
  printf 'systemctl: 不可用\n'
fi

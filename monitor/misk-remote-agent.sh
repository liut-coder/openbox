#!/usr/bin/env bash
# misk-remote-agent — 安装 Misk 远程安全运维 agent
#
# 用途：
#   在你授权的服务器上安装一个本地白名单执行器，供主控机通过 SSH 调用。
#   它只支持安全动作：重启白名单服务/容器、安全磁盘清理、抓取现场。
#
# 安装：
#   bash <(curl -fsSL https://sh.misk.cc/install.sh) misk-remote-agent
#   sudo misk-remote-agent install
#
# 查看：
#   misk-remote-agent status
#   printf '{"action":"snapshot"}' | /usr/local/sbin/misk-remote-remediate-agent

set -euo pipefail

TARGET="${TARGET:-/usr/local/sbin/misk-remote-remediate-agent}"
SELF_WRAPPER="${SELF_WRAPPER:-/usr/local/bin/misk-remote-agent}"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "需要 root 执行：sudo $0 $*" >&2
    exit 1
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_packages() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -gt 0 ]] || return 0
  if has_cmd apt-get; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  elif has_cmd dnf; then
    dnf install -y "${pkgs[@]}"
  elif has_cmd yum; then
    yum install -y "${pkgs[@]}"
  elif has_cmd apk; then
    apk add --no-cache "${pkgs[@]}"
  elif has_cmd pacman; then
    pacman -Sy --noconfirm "${pkgs[@]}"
  else
    echo "无法自动安装依赖: ${pkgs[*]}，请先手动安装 python3" >&2
    return 1
  fi
}

ensure_python3() {
  if has_cmd python3; then
    return 0
  fi
  echo "检测到 python3 未安装，正在自动安装..."
  install_packages python3
  if ! has_cmd python3; then
    echo "python3 安装后仍不可用，请检查系统包管理器" >&2
    exit 1
  fi
}

install_agent() {
  need_root "$@"
  ensure_python3
  mkdir -p "$(dirname "$TARGET")"
  cat > "$TARGET" <<'PY'
#!/usr/bin/env python3
"""Remote safe remediation agent for Misk-managed servers.

Runs on each node. It reads a small action JSON from stdin and performs only
explicitly allowed low-risk operations.

Supported actions:
- restart_service: systemctl restart <allowed unit>
- restart_container: docker restart <allowed container>
- safe_disk_cleanup: journald vacuum + docker builder prune + old /tmp cleanup
- snapshot: collect CPU/memory/disk/OOM evidence

It never deletes business data, never kills unknown processes, never reboots.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ALLOWED_SERVICES = {
    "komari-agent.service",
    "caddy.service",
    "docker.service",
    "1panel-agent.service",
    "1panel-core.service",
}
ALLOWED_CONTAINERS = {
    "ds2api",
    "filebrowser",
    "new-api",
    "newapi",
    "1Panel-openresty-vFkI",
}


def run(cmd: list[str], timeout: int = 60) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return p.returncode, p.stdout.strip()
    except subprocess.TimeoutExpired as e:
        return 124, f"timeout: {e}"
    except Exception as e:
        return 1, f"{e.__class__.__name__}: {e}"


def snapshot() -> dict:
    data = {"time": datetime.now(timezone.utc).isoformat(timespec="seconds"), "items": []}
    commands = [
        ("uptime", ["uptime"]),
        ("memory", ["free", "-h"]),
        ("disk", ["bash", "-lc", "df -h / /srv /opt /home 2>/dev/null | sed -n '1,20p'"]),
        ("cpu_top", ["bash", "-lc", "ps -eo pid,ppid,comm,%cpu,%mem,rss,args --sort=-%cpu | head -8"]),
        ("mem_top", ["bash", "-lc", "ps -eo pid,ppid,comm,%mem,%cpu,rss,args --sort=-%mem | head -8"]),
        ("oom", ["bash", "-lc", "dmesg -T 2>/dev/null | grep -Ei 'out of memory|oom|killed process' | tail -8"]),
        ("komari", ["bash", "-lc", "systemctl is-active komari-agent 2>/dev/null || true"]),
    ]
    for name, cmd in commands:
        code, out = run(cmd, timeout=25)
        data["items"].append({"name": name, "exit": code, "output": out[-1600:]})
    return data


def safe_disk_cleanup() -> dict:
    before = shutil.disk_usage("/")
    before_p = before.used * 100 / before.total
    actions = []
    for label, cmd, timeout in [
        ("journalctl vacuum 7d", ["journalctl", "--vacuum-time=7d"], 120),
        ("docker builder prune", ["docker", "builder", "prune", "-af"], 180),
        ("/tmp old files", ["find", "/tmp", "-xdev", "-type", "f", "-mtime", "+3", "-delete"], 120),
    ]:
        code, out = run(cmd, timeout=timeout)
        actions.append({"action": label, "exit": code, "output": out[-600:]})
    after = shutil.disk_usage("/")
    after_p = after.used * 100 / after.total
    freed_gb = (before.used - after.used) / 1024 / 1024 / 1024
    return {"before_pct": round(before_p, 1), "after_pct": round(after_p, 1), "freed_gb": round(freed_gb, 2), "actions": actions}


def main() -> int:
    try:
        req = json.load(sys.stdin)
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"bad json: {e}"}, ensure_ascii=False))
        return 2
    action = req.get("action")
    target = req.get("target")
    if action == "snapshot":
        print(json.dumps({"ok": True, "result": snapshot()}, ensure_ascii=False))
        return 0
    if action == "safe_disk_cleanup":
        print(json.dumps({"ok": True, "result": safe_disk_cleanup()}, ensure_ascii=False))
        return 0
    if action == "restart_service":
        if target not in ALLOWED_SERVICES:
            print(json.dumps({"ok": False, "error": f"service not allowed: {target}"}, ensure_ascii=False))
            return 3
        code, out = run(["systemctl", "restart", target], timeout=90)
        code2, out2 = run(["systemctl", "is-active", target], timeout=20)
        print(json.dumps({"ok": code == 0 and out2.strip() == "active", "exit": code, "output": out[-600:], "status": out2.strip()}, ensure_ascii=False))
        return 0
    if action == "restart_container":
        if target not in ALLOWED_CONTAINERS:
            print(json.dumps({"ok": False, "error": f"container not allowed: {target}"}, ensure_ascii=False))
            return 3
        code, out = run(["docker", "restart", target], timeout=120)
        print(json.dumps({"ok": code == 0, "exit": code, "output": out[-600:]}, ensure_ascii=False))
        return 0
    print(json.dumps({"ok": False, "error": f"unknown action: {action}"}, ensure_ascii=False))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod 700 "$TARGET"
  python3 -m py_compile "$TARGET"
  echo "✓ 已安装远程 agent: $TARGET"
  echo "测试: printf '{\"action\":\"snapshot\"}' | $TARGET"
}

uninstall_agent() {
  need_root "$@"
  rm -f "$TARGET"
  echo "✓ 已卸载: $TARGET"
}

status_agent() {
  echo "misk-remote-agent"
  echo "目标: $TARGET"
  if [[ -x "$TARGET" ]]; then
    echo "状态: installed"
    if ! has_cmd python3; then
      echo "依赖: missing python3"
      echo "修复: sudo misk-remote-agent install"
      return 1
    fi
    python3 -m py_compile "$TARGET" && echo "语法: ok" || echo "语法: failed"
    printf '{"action":"snapshot"}' | "$TARGET" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("snapshot:", "ok" if d.get("ok") else d)' 2>/dev/null || true
  else
    echo "状态: not installed"
  fi
}

show_help() {
  cat <<EOF
用法: misk-remote-agent <命令>

命令:
  install      安装远程安全运维 agent 到 $TARGET，会自动补 python3
  status       查看安装状态并做 snapshot 自检
  uninstall    卸载 agent
  help         显示帮助

一键安装示例:
  bash <(curl -fsSL https://sh.misk.cc/install.sh) misk-remote-agent
  sudo misk-remote-agent install

主控调用示例:
  printf '{"action":"snapshot"}' | ssh root@host $TARGET
  printf '{"action":"restart_service","target":"komari-agent.service"}' | ssh root@host $TARGET

安全边界:
  - 只执行白名单服务/容器
  - 不删除业务数据
  - 不 kill 未知进程
  - 不重启整机
EOF
}

case "${1:-help}" in
  install) install_agent "$@" ;;
  status) status_agent ;;
  uninstall|remove) uninstall_agent "$@" ;;
  help|-h|--help) show_help ;;
  *) echo "未知命令: $1" >&2; show_help; exit 2 ;;
esac

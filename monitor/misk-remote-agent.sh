#!/usr/bin/env bash
# misk-remote-agent — 安装 Misk 远程安全运维 agent
#
# 推荐一行上线：
#   MRA_TOKEN=xxx bash <(curl -fsSL https://sh.misk.cc/install.sh) misk-remote-agent install
#
# 或先安装包装器再安装：
#   bash <(curl -fsSL https://sh.misk.cc/install.sh) misk-remote-agent
#   sudo MRA_TOKEN=xxx misk-remote-agent install

set -euo pipefail

TARGET="${TARGET:-/usr/local/sbin/misk-remote-remediate-agent}"
SERVICE="${SERVICE:-misk-remote-agent.service}"
ENV_FILE="${ENV_FILE:-/etc/misk-remote-agent.env}"
CONTROL_URL="${MRA_CONTROL_URL:-https://agent.misk.cc}"
VERSION="0.2.0"

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
  if has_cmd python3; then return 0; fi
  echo "检测到 python3 未安装，正在自动安装..."
  install_packages python3
  has_cmd python3 || { echo "python3 安装后仍不可用" >&2; exit 1; }
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip(), ensure_ascii=False))'
}

write_agent() {
  mkdir -p "$(dirname "$TARGET")"
  cat > "$TARGET" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

VERSION = "0.2.0"
CONTROL_URL = os.environ.get("MRA_CONTROL_URL", "https://agent.misk.cc").rstrip("/")
ENV_PATH = os.environ.get("MRA_ENV_FILE", "/etc/misk-remote-agent.env")
TOKEN = os.environ.get("MRA_TOKEN", "")
REGISTER_TOKEN = os.environ.get("MRA_REGISTER_TOKEN", "")
NODE_ID = os.environ.get("MRA_NODE_ID") or socket.gethostname()
INTERVAL = int(os.environ.get("MRA_INTERVAL", "60"))

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


def action_local(req: dict) -> dict:
    action = req.get("action")
    target = req.get("target")
    if action == "snapshot":
        return {"ok": True, "result": snapshot()}
    if action == "safe_disk_cleanup":
        return {"ok": True, "result": safe_disk_cleanup()}
    if action == "restart_service":
        if target not in ALLOWED_SERVICES:
            return {"ok": False, "error": f"service not allowed: {target}"}
        code, out = run(["systemctl", "restart", target], timeout=90)
        code2, out2 = run(["systemctl", "is-active", target], timeout=20)
        return {"ok": code == 0 and out2.strip() == "active", "exit": code, "output": out[-600:], "status": out2.strip()}
    if action == "restart_container":
        if target not in ALLOWED_CONTAINERS:
            return {"ok": False, "error": f"container not allowed: {target}"}
        code, out = run(["docker", "restart", target], timeout=120)
        return {"ok": code == 0, "exit": code, "output": out[-600:]}
    return {"ok": False, "error": f"unknown action: {action}"}


def request(method: str, path: str, data: dict | None = None, timeout: int = 20, auth_token: str | None = None) -> dict:
    tok = auth_token or TOKEN
    body = None if data is None else json.dumps(data, ensure_ascii=False).encode()
    headers = {"User-Agent": f"misk-remote-agent/{VERSION}", "Authorization": f"Bearer {tok}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(CONTROL_URL + path, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def update_env(key: str, value: str) -> None:
    """Replace or add a key=value line in the env file."""
    try:
        lines = []
        with open(ENV_PATH) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []
    found = False
    new_lines = []
    for line in lines:
        if line.startswith(f"{key}="):
            new_lines.append(f"{key}={value}")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{key}={value}")
    with open(ENV_PATH, "w") as f:
        f.write("\n".join(new_lines) + "\n")
    # Also update in-process env so daemon picks it up
    os.environ[key] = value
    if key == "MRA_TOKEN":
        global TOKEN
        TOKEN = value


def identity(snapshot_data: dict | None = None) -> dict:
    return {
        "node_id": NODE_ID,
        "hostname": socket.gethostname(),
        "version": VERSION,
        "os": platform.platform(),
        "snapshot": snapshot_data or {},
    }


def register() -> None:
    """Register with the master using REGISTER_TOKEN, then save returned per-agent token."""
    if not REGISTER_TOKEN:
        print("missing MRA_REGISTER_TOKEN", file=sys.stderr)
        return
    resp = request("POST", "/api/register", identity(snapshot()), auth_token=REGISTER_TOKEN)
    agent_tok = resp.get("agent_token")
    if agent_tok:
        update_env("MRA_TOKEN", agent_tok)
        # Remove register token from env file so it's not kept around
        update_env("MRA_REGISTER_TOKEN", "")
        print(f"registered agent_token={agent_tok[:8]}...")
    else:
        print("register: no agent_token in response", file=sys.stderr)


def heartbeat() -> None:
    request("POST", "/api/heartbeat", identity(snapshot()))


def poll_once() -> None:
    cmd = request("GET", f"/api/commands/{NODE_ID}").get("command")
    if not cmd:
        return
    result = action_local(cmd)
    request("POST", f"/api/commands/{cmd['id']}/result", {"node_id": NODE_ID, "result": result})


def daemon() -> int:
    tok = TOKEN or REGISTER_TOKEN
    if not tok:
        print("missing MRA_TOKEN or MRA_REGISTER_TOKEN", file=sys.stderr)
        return 2
    # If we only have a register token, register first to get per-agent token
    if REGISTER_TOKEN and not TOKEN:
        try:
            register()
        except Exception as e:
            print(f"auto-register failed: {e.__class__.__name__}: {e}", file=sys.stderr)
            time.sleep(30)
    while True:
        try:
            heartbeat()
            poll_once()
        except Exception as e:
            print(f"agent loop error: {e.__class__.__name__}: {e}", file=sys.stderr)
        time.sleep(INTERVAL)


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        return daemon()
    if len(sys.argv) > 1 and sys.argv[1] == "register":
        register(); print("registered"); return 0
    if len(sys.argv) > 1 and sys.argv[1] == "heartbeat":
        heartbeat(); print("heartbeat-ok"); return 0
    try:
        req = json.load(sys.stdin)
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"bad json: {e}"}, ensure_ascii=False))
        return 2
    print(json.dumps(action_local(req), ensure_ascii=False))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod 700 "$TARGET"
  python3 -m py_compile "$TARGET"
}

write_env() {
  local token="${MRA_TOKEN:-}"
  local node_id="${MRA_NODE_ID:-$(hostname)}"
  if [[ -z "$token" && -f "$ENV_FILE" ]]; then
    token="$(grep -E '^MRA_REGISTER_TOKEN=' "$ENV_FILE" 2>/dev/null | sed 's/^MRA_REGISTER_TOKEN=//' | tr -d '"' || true)"
    [[ -z "$token" ]] && token="$(grep -E '^MRA_TOKEN=' "$ENV_FILE" 2>/dev/null | sed 's/^MRA_TOKEN=//' | tr -d '"' || true)"
  fi
  if [[ -z "$token" ]]; then
    echo "缺少 MRA_TOKEN。请用：MRA_TOKEN=xxx misk-remote-agent install" >&2
    exit 2
  fi
  umask 077
  cat > "$ENV_FILE" <<EOF
MRA_CONTROL_URL=$CONTROL_URL
MRA_REGISTER_TOKEN=$token
MRA_NODE_ID=$node_id
MRA_INTERVAL=${MRA_INTERVAL:-60}
MRA_ENV_FILE=$ENV_FILE
EOF
}

write_service() {
  cat > /etc/systemd/system/$SERVICE <<EOF
[Unit]
Description=Misk Remote Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
ExecStart=$TARGET daemon
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$SERVICE"
}

install_agent() {
  need_root "$@"
  ensure_python3
  write_agent
  write_env
  # Pass register token and env file path to the Python agent for registration
  MRA_REGISTER_TOKEN="${MRA_TOKEN:-}" MRA_ENV_FILE="$ENV_FILE" "$TARGET" register
  write_service
  echo "✓ 已上线: $(hostname) -> $CONTROL_URL"
  echo "✓ agent: $TARGET"
  echo "✓ service: $SERVICE"
}

uninstall_agent() {
  need_root "$@"
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$SERVICE" "$TARGET" "$ENV_FILE"
  systemctl daemon-reload 2>/dev/null || true
  echo "✓ 已卸载"
}

status_agent() {
  echo "misk-remote-agent $VERSION"
  echo "控制端: $CONTROL_URL"
  echo "目标: $TARGET"
  [[ -x "$TARGET" ]] && echo "状态: installed" || { echo "状态: not installed"; return 1; }
  if ! has_cmd python3; then echo "依赖: missing python3"; return 1; fi
  python3 -m py_compile "$TARGET" && echo "语法: ok" || echo "语法: failed"
  if has_cmd systemctl; then systemctl is-active "$SERVICE" 2>/dev/null | sed 's/^/服务: /' || true; fi
  if [[ -f "$ENV_FILE" ]]; then "$TARGET" heartbeat || true; fi
  printf '{"action":"snapshot"}' | "$TARGET" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("snapshot:", "ok" if d.get("ok") else d)' 2>/dev/null || true
}

show_help() {
  cat <<EOF
用法: misk-remote-agent <命令>

命令:
  install      安装并注册到主控，自动补 python3，并创建 systemd 常驻服务
  status       查看安装/在线状态并做 snapshot 自检
  uninstall    卸载 agent
  help         显示帮助

一行上线:
  MRA_TOKEN=xxx bash <(curl -fsSL https://sh.misk.cc/install.sh) misk-remote-agent install

可选变量:
  MRA_CONTROL_URL=$CONTROL_URL
  MRA_NODE_ID=$(hostname)
  MRA_INTERVAL=60

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

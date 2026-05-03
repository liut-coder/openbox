#!/usr/bin/env bash
set -euo pipefail

TAG="nax-forward"
TARGET_IP=""
SSH_PORT=""
ACTION=""
SOURCE_PORT=""
TARGET_PORT=""
PROTOCOL="tcp"

usage() {
cat <<USAGE
用法:
  全端口转发，自动保护 SSH:
    $0 --all -t 目标IP

  指定 SSH 端口:
    $0 --all -t 目标IP --ssh-port 2222

  单端口添加:
    $0 -a -s 源端口 -t 目标IP -p 目标端口 -P tcp|udp|all

  单端口删除:
    $0 -d -s 源端口 -t 目标IP -p 目标端口 -P tcp|udp|all

  查看规则:
    $0 --list

  清理本脚本规则:
    $0 --flush
USAGE
exit 1
}

[ "$(id -u)" = "0" ] || { echo "请用 root 运行"; exit 1; }

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_ipv6() {
    [[ "$1" == *:* ]]
}

detect_ssh_port() {
    if [ -n "${SSH_PORT:-}" ]; then
        echo "$SSH_PORT"
        return
    fi

    # 优先从当前 SSH 连接识别本机端口
    if [ -n "${SSH_CONNECTION:-}" ]; then
        # SSH_CONNECTION 格式：客户端IP 客户端端口 服务端IP 服务端端口
        echo "$SSH_CONNECTION" | awk '{print $4}'
        return
    fi

    # 再从 sshd 配置读取
    local conf_port
    conf_port=$(grep -Ei '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -n1 || true)
    if [ -n "$conf_port" ]; then
        echo "$conf_port"
        return
    fi

    # 再尝试从监听端口识别
    if cmd_exists ss; then
        ss -lntp 2>/dev/null | grep -E 'sshd|dropbear' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1
        return
    fi

    echo "22"
}

enable_forward() {
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
}

backup_rules() {
    mkdir -p /root/forward-backup
    iptables-save > /root/forward-backup/iptables.$(date +%F-%H%M%S).bak
    cat > /root/forward-rollback.sh <<'ROLLBACK'
#!/usr/bin/env bash
set -e
latest=$(ls -t /root/forward-backup/iptables.*.bak 2>/dev/null | head -n1)
[ -n "$latest" ] || { echo "没有找到备份"; exit 1; }
iptables-restore < "$latest"
echo "已回滚 iptables 规则：$latest"
ROLLBACK
    chmod +x /root/forward-rollback.sh
}

protect_ssh() {
    local port="$1"

    valid_port "$port" || {
        echo "SSH 端口不合法：$port"
        exit 1
    }

    # INPUT 保护
    iptables -C INPUT -p tcp --dport "$port" -m comment --comment "$TAG protect-ssh-$port" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -p tcp --dport "$port" -m comment --comment "$TAG protect-ssh-$port" -j ACCEPT

    # NAT PREROUTING 提前 RETURN，防止 SSH 被 DNAT 转走
    iptables -t nat -C PREROUTING -p tcp --dport "$port" -m comment --comment "$TAG keep-ssh-$port" -j RETURN 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -p tcp --dport "$port" -m comment --comment "$TAG keep-ssh-$port" -j RETURN

    echo "已保护 SSH 端口：$port"
}

add_masquerade() {
    iptables -t nat -C POSTROUTING -m comment --comment "$TAG masquerade" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -m comment --comment "$TAG masquerade" -j MASQUERADE
}

add_all() {
    [ -n "$TARGET_IP" ] || usage

    if is_ipv6 "$TARGET_IP"; then
        echo "全端口模式建议使用 IPv4，IPv6 请单端口配置"
        exit 1
    fi

    SSH_PORT="$(detect_ssh_port)"
    valid_port "$SSH_PORT" || {
        echo "无法安全识别 SSH 端口，请手动指定：--ssh-port 端口"
        exit 1
    }

    echo "检测到 SSH 端口：$SSH_PORT"
    echo "目标后端 IP：$TARGET_IP"

    backup_rules
    enable_forward
    protect_ssh "$SSH_PORT"

    iptables -t nat -C PREROUTING -p tcp ! --dport "$SSH_PORT" \
        -m comment --comment "$TAG all-tcp-to-$TARGET_IP" \
        -j DNAT --to-destination "$TARGET_IP" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p tcp ! --dport "$SSH_PORT" \
        -m comment --comment "$TAG all-tcp-to-$TARGET_IP" \
        -j DNAT --to-destination "$TARGET_IP"

    iptables -t nat -C PREROUTING -p udp \
        -m comment --comment "$TAG all-udp-to-$TARGET_IP" \
        -j DNAT --to-destination "$TARGET_IP" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p udp \
        -m comment --comment "$TAG all-udp-to-$TARGET_IP" \
        -j DNAT --to-destination "$TARGET_IP"

    iptables -C FORWARD -d "$TARGET_IP" \
        -m comment --comment "$TAG forward-to-$TARGET_IP" \
        -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -d "$TARGET_IP" \
        -m comment --comment "$TAG forward-to-$TARGET_IP" \
        -j ACCEPT

    add_masquerade
    save_rules

    echo "完成：SSH $SSH_PORT 保留在本机，其它 TCP/UDP 转发到 $TARGET_IP"
    echo "如误操作，可执行回滚：/root/forward-rollback.sh"
}

add_single_proto() {
    local proto="$1"

    iptables -t nat -C PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$TAG single-$proto-$SOURCE_PORT-to-$TARGET_IP-$TARGET_PORT" \
        -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$TAG single-$proto-$SOURCE_PORT-to-$TARGET_IP-$TARGET_PORT" \
        -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"

    iptables -C FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
        -m comment --comment "$TAG forward-$proto-$TARGET_IP-$TARGET_PORT" \
        -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
        -m comment --comment "$TAG forward-$proto-$TARGET_IP-$TARGET_PORT" \
        -j ACCEPT
}

del_single_proto() {
    local proto="$1"

    iptables -t nat -D PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$TAG single-$proto-$SOURCE_PORT-to-$TARGET_IP-$TARGET_PORT" \
        -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT" 2>/dev/null || true

    iptables -D FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
        -m comment --comment "$TAG forward-$proto-$TARGET_IP-$TARGET_PORT" \
        -j ACCEPT 2>/dev/null || true
}

add_single() {
    valid_port "$SOURCE_PORT" || { echo "源端口不合法"; exit 1; }
    valid_port "$TARGET_PORT" || { echo "目标端口不合法"; exit 1; }

    SSH_PORT="$(detect_ssh_port)"
    if [ "$SOURCE_PORT" = "$SSH_PORT" ]; then
        echo "拒绝：源端口 $SOURCE_PORT 是当前 SSH 端口，避免锁死"
        exit 1
    fi

    backup_rules
    enable_forward
    protect_ssh "$SSH_PORT"

    if [ "$PROTOCOL" = "all" ]; then
        add_single_proto tcp
        add_single_proto udp
    else
        add_single_proto "$PROTOCOL"
    fi

    add_masquerade
    save_rules
    echo "已添加单端口转发"
}

del_single() {
    if [ "$PROTOCOL" = "all" ]; then
        del_single_proto tcp
        del_single_proto udp
    else
        del_single_proto "$PROTOCOL"
    fi

    save_rules
    echo "已删除单端口转发"
}

list_rules() {
    echo "===== NAT ====="
    iptables -t nat -L -n -v --line-numbers | grep -E "$TAG|DNAT|MASQUERADE|RETURN" || true
    echo
    echo "===== FORWARD ====="
    iptables -L FORWARD -n -v --line-numbers | grep -E "$TAG|ACCEPT" || true
    echo
    echo "===== INPUT ====="
    iptables -L INPUT -n -v --line-numbers | grep -E "$TAG|ACCEPT" || true
}

flush_rules() {
    backup_rules

    for chain in PREROUTING POSTROUTING; do
        while iptables -t nat -S "$chain" | grep -q "$TAG"; do
            rule=$(iptables -t nat -S "$chain" | grep "$TAG" | head -n1 | sed 's/^-A/-D/')
            iptables -t nat $rule || true
        done
    done

    for chain in FORWARD INPUT; do
        while iptables -S "$chain" | grep -q "$TAG"; do
            rule=$(iptables -S "$chain" | grep "$TAG" | head -n1 | sed 's/^-A/-D/')
            iptables $rule || true
        done
    done

    save_rules
    echo "已清理本脚本创建的规则"
}

save_rules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
    elif [ -d /etc/iptables ] && command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4
    elif command -v service >/dev/null 2>&1; then
        service iptables save >/dev/null 2>&1 || true
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            ACTION="all"
            shift
            ;;
        -a)
            ACTION="add"
            shift
            ;;
        -d)
            ACTION="del"
            shift
            ;;
        -s)
            SOURCE_PORT="${2:-}"
            shift 2
            ;;
        -t)
            TARGET_IP="${2:-}"
            shift 2
            ;;
        -p)
            TARGET_PORT="${2:-}"
            shift 2
            ;;
        -P)
            PROTOCOL="${2:-tcp}"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="${2:-}"
            shift 2
            ;;
        --list)
            list_rules
            exit 0
            ;;
        --flush)
            flush_rules
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "未知参数：$1"
            usage
            ;;
    esac
done

case "$ACTION" in
    all)
        add_all
        ;;
    add)
        [ -n "$SOURCE_PORT" ] && [ -n "$TARGET_IP" ] && [ -n "$TARGET_PORT" ] || usage
        add_single
        ;;
    del)
        [ -n "$SOURCE_PORT" ] && [ -n "$TARGET_IP" ] && [ -n "$TARGET_PORT" ] || usage
        del_single
        ;;
    *)
        usage
        ;;
esac

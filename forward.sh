#!/usr/bin/env bash
set -euo pipefail

SCRIPT_TAG="nax-forward"
ACTION=""
SOURCE_PORT=""
TARGET_IP=""
TARGET_PORT=""
PROTOCOL="tcp"
ALL_MODE="false"
SSH_PORT="22"

usage() {
cat <<USAGE
通用端口转发脚本

用法:
  单端口添加:
    $0 -a -s 源端口 -t 目标IP -p 目标端口 -P tcp|udp|all

  单端口删除:
    $0 -d -s 源端口 -t 目标IP -p 目标端口 -P tcp|udp|all

  全端口转发，保留 SSH:
    $0 --all -t 目标IP --ssh-port 22

  查看规则:
    $0 --list

  清理本脚本规则:
    $0 --flush

示例:
  $0 -a -s 8080 -t 192.168.1.100 -p 80 -P tcp
  $0 -a -s 7001 -t 1.2.3.4 -p 7001 -P all
  $0 --all -t 1.2.3.4 --ssh-port 22
USAGE
exit 1
}

need_root() {
    [ "$(id -u)" = "0" ] || {
        echo "错误：请用 root 用户运行"
        exit 1
    }
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_ipv6() {
    [[ "$1" == *:* ]]
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

valid_proto() {
    [[ "$1" == "tcp" || "$1" == "udp" || "$1" == "all" ]]
}

enable_forward() {
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi

    if cmd_exists ip6tables; then
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true
        if ! grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf 2>/dev/null; then
            echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
        fi
    fi
}

ensure_tools() {
    if ! cmd_exists iptables; then
        echo "错误：未找到 iptables"
        echo "Debian/Ubuntu: apt update && apt install -y iptables"
        echo "CentOS/Rocky: yum install -y iptables-services"
        exit 1
    fi
}

ensure_docker_user_chain() {
    if iptables -L DOCKER-USER -n >/dev/null 2>&1; then
        if ! iptables -C DOCKER-USER -j RETURN >/dev/null 2>&1; then
            iptables -A DOCKER-USER -j RETURN || true
        fi
    fi
}

add_one_proto_v4() {
    local proto="$1"

    if iptables -t nat -C PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$SCRIPT_TAG single $proto $SOURCE_PORT->$TARGET_IP:$TARGET_PORT" \
        -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT" 2>/dev/null; then
        echo "IPv4 $proto 规则已存在：$SOURCE_PORT -> $TARGET_IP:$TARGET_PORT"
    else
        iptables -t nat -A PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
            -m comment --comment "$SCRIPT_TAG single $proto $SOURCE_PORT->$TARGET_IP:$TARGET_PORT" \
            -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"

        iptables -C FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
            -m comment --comment "$SCRIPT_TAG forward $proto $TARGET_IP:$TARGET_PORT" \
            -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
            -m comment --comment "$SCRIPT_TAG forward $proto $TARGET_IP:$TARGET_PORT" \
            -j ACCEPT

        echo "已添加 IPv4 $proto：$SOURCE_PORT -> $TARGET_IP:$TARGET_PORT"
    fi
}

del_one_proto_v4() {
    local proto="$1"

    iptables -t nat -D PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$SCRIPT_TAG single $proto $SOURCE_PORT->$TARGET_IP:$TARGET_PORT" \
        -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT" 2>/dev/null || true

    iptables -D FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
        -m comment --comment "$SCRIPT_TAG forward $proto $TARGET_IP:$TARGET_PORT" \
        -j ACCEPT 2>/dev/null || true

    echo "已删除 IPv4 $proto：$SOURCE_PORT -> $TARGET_IP:$TARGET_PORT"
}

add_one_proto_v6() {
    local proto="$1"

    cmd_exists ip6tables || {
        echo "跳过 IPv6：未安装 ip6tables"
        return
    }

    if ip6tables -t nat -C PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$SCRIPT_TAG single6 $proto $SOURCE_PORT->[$TARGET_IP]:$TARGET_PORT" \
        -j DNAT --to-destination "[$TARGET_IP]:$TARGET_PORT" 2>/dev/null; then
        echo "IPv6 $proto 规则已存在：$SOURCE_PORT -> [$TARGET_IP]:$TARGET_PORT"
    else
        ip6tables -t nat -A PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
            -m comment --comment "$SCRIPT_TAG single6 $proto $SOURCE_PORT->[$TARGET_IP]:$TARGET_PORT" \
            -j DNAT --to-destination "[$TARGET_IP]:$TARGET_PORT"

        ip6tables -C FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
            -m comment --comment "$SCRIPT_TAG forward6 $proto [$TARGET_IP]:$TARGET_PORT" \
            -j ACCEPT 2>/dev/null || \
        ip6tables -A FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
            -m comment --comment "$SCRIPT_TAG forward6 $proto [$TARGET_IP]:$TARGET_PORT" \
            -j ACCEPT

        echo "已添加 IPv6 $proto：$SOURCE_PORT -> [$TARGET_IP]:$TARGET_PORT"
    fi
}

del_one_proto_v6() {
    local proto="$1"

    cmd_exists ip6tables || {
        echo "跳过 IPv6：未安装 ip6tables"
        return
    }

    ip6tables -t nat -D PREROUTING -p "$proto" --dport "$SOURCE_PORT" \
        -m comment --comment "$SCRIPT_TAG single6 $proto $SOURCE_PORT->[$TARGET_IP]:$TARGET_PORT" \
        -j DNAT --to-destination "[$TARGET_IP]:$TARGET_PORT" 2>/dev/null || true

    ip6tables -D FORWARD -p "$proto" -d "$TARGET_IP" --dport "$TARGET_PORT" \
        -m comment --comment "$SCRIPT_TAG forward6 $proto [$TARGET_IP]:$TARGET_PORT" \
        -j ACCEPT 2>/dev/null || true

    echo "已删除 IPv6 $proto：$SOURCE_PORT -> [$TARGET_IP]:$TARGET_PORT"
}

add_masquerade() {
    iptables -t nat -C POSTROUTING \
        -m comment --comment "$SCRIPT_TAG masquerade" \
        -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING \
        -m comment --comment "$SCRIPT_TAG masquerade" \
        -j MASQUERADE

    if cmd_exists ip6tables; then
        ip6tables -t nat -C POSTROUTING \
            -m comment --comment "$SCRIPT_TAG masquerade6" \
            -j MASQUERADE 2>/dev/null || \
        ip6tables -t nat -A POSTROUTING \
            -m comment --comment "$SCRIPT_TAG masquerade6" \
            -j MASQUERADE 2>/dev/null || true
    fi
}

add_single() {
    valid_port "$SOURCE_PORT" || { echo "源端口不合法"; exit 1; }
    valid_port "$TARGET_PORT" || { echo "目标端口不合法"; exit 1; }
    valid_proto "$PROTOCOL" || { echo "协议只能是 tcp/udp/all"; exit 1; }

    if [ "$SOURCE_PORT" = "$SSH_PORT" ]; then
        echo "拒绝：源端口是 SSH 保留端口 $SSH_PORT，避免把自己踢下线"
        exit 1
    fi

    enable_forward

    local protos=()
    if [ "$PROTOCOL" = "all" ]; then
        protos=("tcp" "udp")
    else
        protos=("$PROTOCOL")
    fi

    for proto in "${protos[@]}"; do
        if is_ipv6 "$TARGET_IP"; then
            add_one_proto_v6 "$proto"
        else
            add_one_proto_v4 "$proto"
        fi
    done

    add_masquerade
}

del_single() {
    valid_port "$SOURCE_PORT" || { echo "源端口不合法"; exit 1; }
    valid_port "$TARGET_PORT" || { echo "目标端口不合法"; exit 1; }
    valid_proto "$PROTOCOL" || { echo "协议只能是 tcp/udp/all"; exit 1; }

    local protos=()
    if [ "$PROTOCOL" = "all" ]; then
        protos=("tcp" "udp")
    else
        protos=("$PROTOCOL")
    fi

    for proto in "${protos[@]}"; do
        if is_ipv6 "$TARGET_IP"; then
            del_one_proto_v6 "$proto"
        else
            del_one_proto_v4 "$proto"
        fi
    done
}

add_all_forward() {
    [ -n "$TARGET_IP" ] || usage
    valid_port "$SSH_PORT" || { echo "SSH 端口不合法"; exit 1; }

    if is_ipv6 "$TARGET_IP"; then
        echo "全端口模式暂建议 IPv4 使用，IPv6 请用单端口模式"
        exit 1
    fi

    enable_forward

    iptables -t nat -C PREROUTING -p tcp ! --dport "$SSH_PORT" \
        -m comment --comment "$SCRIPT_TAG all-tcp except-ssh-$SSH_PORT" \
        -j DNAT --to-destination "$TARGET_IP" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p tcp ! --dport "$SSH_PORT" \
        -m comment --comment "$SCRIPT_TAG all-tcp except-ssh-$SSH_PORT" \
        -j DNAT --to-destination "$TARGET_IP"

    iptables -t nat -C PREROUTING -p udp \
        -m comment --comment "$SCRIPT_TAG all-udp" \
        -j DNAT --to-destination "$TARGET_IP" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p udp \
        -m comment --comment "$SCRIPT_TAG all-udp" \
        -j DNAT --to-destination "$TARGET_IP"

    iptables -C FORWARD -d "$TARGET_IP" \
        -m comment --comment "$SCRIPT_TAG all-forward" \
        -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -d "$TARGET_IP" \
        -m comment --comment "$SCRIPT_TAG all-forward" \
        -j ACCEPT

    add_masquerade

    echo "已开启全端口转发："
    echo "  保留本机 SSH: $SSH_PORT"
    echo "  其它 TCP/UDP -> $TARGET_IP"
}

list_rules() {
    echo "===== IPv4 NAT 规则 ====="
    iptables -t nat -L -n -v --line-numbers | grep -E "$SCRIPT_TAG|DNAT|MASQUERADE" || true
    echo
    echo "===== IPv4 FORWARD 规则 ====="
    iptables -L FORWARD -n -v --line-numbers | grep -E "$SCRIPT_TAG|ACCEPT" || true

    if cmd_exists ip6tables; then
        echo
        echo "===== IPv6 NAT 规则 ====="
        ip6tables -t nat -L -n -v --line-numbers 2>/dev/null | grep -E "$SCRIPT_TAG|DNAT|MASQUERADE" || true
        echo
        echo "===== IPv6 FORWARD 规则 ====="
        ip6tables -L FORWARD -n -v --line-numbers 2>/dev/null | grep -E "$SCRIPT_TAG|ACCEPT" || true
    fi
}

flush_chain_rules() {
    local bin="$1"
    local table="$2"
    local chain="$3"

    while "$bin" ${table:+-t "$table"} -S "$chain" 2>/dev/null | grep -q "$SCRIPT_TAG"; do
        local rule
        rule=$("$bin" ${table:+-t "$table"} -S "$chain" | grep "$SCRIPT_TAG" | head -n1 | sed 's/^-A/-D/')
        "$bin" ${table:+-t "$table"} $rule || true
    done
}

flush_rules() {
    echo "清理本脚本创建的规则..."

    flush_chain_rules iptables nat PREROUTING
    flush_chain_rules iptables nat POSTROUTING
    flush_chain_rules iptables "" FORWARD

    if cmd_exists ip6tables; then
        flush_chain_rules ip6tables nat PREROUTING || true
        flush_chain_rules ip6tables nat POSTROUTING || true
        flush_chain_rules ip6tables "" FORWARD || true
    fi

    echo "清理完成"
}

save_rules() {
    if cmd_exists netfilter-persistent; then
        netfilter-persistent save >/dev/null 2>&1 || true
        echo "规则已通过 netfilter-persistent 保存"
    elif [ -d /etc/iptables ] && cmd_exists iptables-save; then
        iptables-save > /etc/iptables/rules.v4
        cmd_exists ip6tables-save && ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
        echo "规则已保存到 /etc/iptables/rules.v4"
    elif cmd_exists service; then
        service iptables save >/dev/null 2>&1 || true
        service ip6tables save >/dev/null 2>&1 || true
        echo "已尝试通过 service iptables save 保存"
    else
        echo "提醒：未检测到持久化工具，重启后规则可能丢失"
        echo "Debian/Ubuntu 可安装：apt install -y iptables-persistent"
        echo "CentOS/Rocky 可安装：yum install -y iptables-services"
    fi
}

need_root
ensure_tools
ensure_docker_user_chain

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --all)
            ALL_MODE="true"
            ACTION="all"
            shift
            ;;
        --ssh-port)
            SSH_PORT="${2:-22}"
            shift 2
            ;;
        --list)
            list_rules
            exit 0
            ;;
        --flush)
            flush_rules
            save_rules
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
    add)
        [ -n "$SOURCE_PORT" ] && [ -n "$TARGET_IP" ] && [ -n "$TARGET_PORT" ] || usage
        add_single
        save_rules
        ;;
    del)
        [ -n "$SOURCE_PORT" ] && [ -n "$TARGET_IP" ] && [ -n "$TARGET_PORT" ] || usage
        del_single
        save_rules
        ;;
    all)
        add_all_forward
        save_rules
        ;;
    *)
        usage
        ;;
esac

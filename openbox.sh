#!/usr/bin/env bash
# openbox.sh — 脚本自动化中心入口
# 用法: bash <(curl -fsSL sh.misk.cc)  或  bash <(curl -fsSL sh.misk.cc/install.sh) <目标>

set -euo pipefail

BASE_URL="${OPENBOX_BASE_URL:-https://raw.githubusercontent.com/liut-coder/openbox/main}"

INSTALL_URL="${BASE_URL}/install.sh"
CACHE_DIR="${HOME:-/root}/.cache/openbox"
mkdir -p "$CACHE_DIR"
INSTALL_CACHE="$CACHE_DIR/install.sh"

# 缓存 install.sh，减少重复下载
if [[ ! -f "$INSTALL_CACHE" ]] || [[ "$(find "$INSTALL_CACHE" -mmin +60 2>/dev/null)" ]]; then
    curl -fsSL "$INSTALL_URL" -o "$INSTALL_CACHE" 2>/dev/null || {
        echo "无法下载 install.sh，尝试直接执行..."
        bash <(curl -fsSL "$INSTALL_URL") "$@"
        exit $?
    }
fi
chmod +x "$INSTALL_CACHE"

# 有参数直接透传
if [[ $# -gt 0 ]]; then
    exec bash "$INSTALL_CACHE" "$@"
fi

# ── 交互菜单 ────────────────────────────────────────────────────

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

show_banner() {
    echo -e "${CYAN}"
    cat <<'EOF'
╔════════════════════════════════════╗
║        📦  Openbox 脚本中心        ║
╠════════════════════════════════════╣
║  输入编号进入分类，按 q 退出        ║
╚════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

show_menu() {
    show_banner
    echo -e "${YELLOW}分类${NC}"
    echo "  1  proxy      代理 / 转发 / 反代"
    echo "  2  tools      开发工具 / 切换器"
    echo "  3  bench      服务器测试"
    echo "  4  system     系统管理"
    echo "  5  monitor    监控预警  · 规划中"
    echo "  6  security   安全加固  · 规划中"
    echo "  7  bootstrap  新机初始化 · 规划中"
    echo "  8  backup     备份脚本  · 规划中"
    echo "  9  agent      助手常用脚本"
    echo ""
    echo -e "${YELLOW}快捷操作${NC}"
    echo "  i  安装全部"
    echo "  l  查看完整列表"
    echo "  u  卸载脚本"
    echo "  h  帮助信息"
    echo "  q  退出"
    echo ""
    echo -e "${GREEN}示例：bash <(curl -fsSL sh.misk.cc) bench${NC}"
    echo ""
}

category_title() {
    case "$1" in
        proxy)  echo "代理 / 转发 / 反代" ;;
        tools)  echo "开发工具 / 切换器" ;;
        bench)  echo "服务器测试" ;;
        system) echo "系统管理" ;;
        agent)  echo "助手常用脚本" ;;
        *)      echo "$1" ;;
    esac
}

list_category_entries() {
    local cat="$1"
    awk -v cat="$cat" '
        /^[[:space:]]*"[^|]+\|[^|]+\|/ {
            line=$0
            sub(/^[[:space:]]*"/, "", line)
            sub(/"[[:space:]]*$/, "", line)
            n=split(line, f, "|")
            if (n >= 6 && f[2] == cat) {
                printf "%s|%s|%s\n", f[1], f[3], f[6]
            }
        }
    ' "$INSTALL_CACHE"
}

show_category_menu() {
    local cat="$1"
    local title; title="$(category_title "$cat")"
    local entries=()
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] && entries+=("$line")
    done < <(list_category_entries "$cat")

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "$cat 分类暂未上线，请期待后续更新。"
        return 0
    fi

    while true; do
        echo ""
        echo -e "${CYAN}## $cat · $title${NC}"
        echo "输入编号安装单个脚本；输入 a 安装本分类全部。"
        echo ""

        local i=1
        local entry name desc alias alias_str
        for entry in "${entries[@]}"; do
            IFS='|' read -r name desc alias <<< "$entry"
            alias_str=""
            [[ -n "$alias" ]] && alias_str=" / $alias"
            printf '  %2d  %-18s %s%s\n' "$i" "$name" "$desc" "$alias_str"
            ((i++))
        done

        echo ""
        echo "  a   安装 $cat 分类全部"
        echo "  b   返回主菜单"
        echo "  q   退出"
        echo ""
        read -r -p "请选择 > " subchoice

        case "${subchoice,,}" in
            a|all)
                bash "$INSTALL_CACHE" "$cat"
                return 0
                ;;
            b|back|"")
                return 0
                ;;
            q|quit|exit)
                echo "再见~"
                exit 0
                ;;
            ''|*[!0-9]*)
                echo "未知选项，重试"
                ;;
            *)
                if (( subchoice >= 1 && subchoice <= ${#entries[@]} )); then
                    IFS='|' read -r name desc alias <<< "${entries[$((subchoice-1))]}"
                    bash "$INSTALL_CACHE" "$name"
                    return 0
                fi
                echo "编号超出范围，重试"
                ;;
        esac
    done
}

while true; do
    show_menu
    read -r -p "请选择 > " choice

    case "${choice,,}" in
        1|proxy)         show_category_menu proxy ;;
        2|tools)         show_category_menu tools ;;
        3|bench)         show_category_menu bench ;;
        4|system)        show_category_menu system ;;
        5|monitor)       echo "monitor 分类暂未上线，请期待后续更新。" ;;
        6|security)      echo "security 分类暂未上线，请期待后续更新。" ;;
        7|bootstrap)     echo "bootstrap 分类暂未上线，请期待后续更新。" ;;
        8|backup)        echo "backup 分类暂未上线，请期待后续更新。" ;;
        9|agent)         show_category_menu agent ;;
        i|all)           bash "$INSTALL_CACHE" all ;;
        l|list)          bash "$INSTALL_CACHE" --list ;;
        u|uninstall)
            read -r -p "卸载目标 (脚本名/分类/all): " utarget
            bash "$INSTALL_CACHE" --uninstall "$utarget"
            ;;
        h|help)          bash "$INSTALL_CACHE" --help ;;
        q|quit|exit)     echo "再见~"; exit 0 ;;
        *)               echo "未知选项，重试"; sleep 1 ;;
    esac

    echo ""; read -r -p "按回车继续..." _
done

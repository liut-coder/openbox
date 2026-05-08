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

while true; do
    show_menu
    read -r -p "请选择 > " choice

    case "${choice,,}" in
        1|proxy)         bash "$INSTALL_CACHE" proxy ;;
        2|tools)         bash "$INSTALL_CACHE" tools ;;
        3|bench)         bash "$INSTALL_CACHE" bench ;;
        4|system)        bash "$INSTALL_CACHE" system ;;
        5|monitor)       echo "monitor 分类暂未上线，请期待后续更新。" ;;
        6|security)      echo "security 分类暂未上线，请期待后续更新。" ;;
        7|bootstrap)     echo "bootstrap 分类暂未上线，请期待后续更新。" ;;
        8|backup)        echo "backup 分类暂未上线，请期待后续更新。" ;;
        9|agent)         bash "$INSTALL_CACHE" agent ;;
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

#!/usr/bin/env bash
# hmn-install — Hermes Managed Network 主控一键安装/更新入口

set -euo pipefail

HMN_BRANCH="${HMN_BRANCH:-feat/control-plane-mvp}"
HMN_REPO="${HMN_REPO:-liut-coder/hermes-managed-network}"
HMN_INSTALL_URL="${HMN_INSTALL_URL:-https://raw.githubusercontent.com/${HMN_REPO}/${HMN_BRANCH}/install.sh}"

show_help() {
  cat <<EOF
用法: hmn-install [install|update|url|help]

说明:
  安装/更新 Hermes Managed Network 主控。
  默认使用分支: ${HMN_BRANCH}

环境变量:
  HMN_BRANCH       指定分支，默认 feat/control-plane-mvp
  HMN_REPO         指定仓库，默认 liut-coder/hermes-managed-network
  HMN_PUBLIC_URL   可选，设置 hmn wake 默认主控 URL
  HMN_HOST         可选，默认由 HMN 安装脚本处理
  HMN_PORT         可选，默认由 HMN 安装脚本处理
  HMN_DB           可选，默认由 HMN 安装脚本处理

示例:
  hmn-install
  hmn-install update
  HMN_PUBLIC_URL=http://1.2.3.4:8765 hmn-install
EOF
}

case "${1:-install}" in
  install|update)
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      if command -v sudo >/dev/null 2>&1; then
        exec sudo \
          HMN_BRANCH="${HMN_BRANCH}" \
          HMN_REPO="${HMN_REPO}" \
          HMN_INSTALL_URL="${HMN_INSTALL_URL}" \
          HMN_PUBLIC_URL="${HMN_PUBLIC_URL:-}" \
          HMN_HOST="${HMN_HOST:-}" \
          HMN_PORT="${HMN_PORT:-}" \
          HMN_DB="${HMN_DB:-}" \
          bash "$0" "${1:-install}"
      fi
      echo "需要 root 或 sudo" >&2
      exit 1
    fi
    curl -fsSL "${HMN_INSTALL_URL}" | bash
    ;;
  url)
    printf '%s\n' "${HMN_INSTALL_URL}"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "未知命令: $1" >&2
    show_help
    exit 1
    ;;
esac

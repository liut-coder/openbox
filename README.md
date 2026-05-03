# openbox

公开脚本集合，用于快速配置服务器反代、管理 Codex CLI / Claude Code 中转配置。

## 脚本

- `caddy_manager.sh`: Caddy 交互式管理脚本，支持一键反代、配置预览、语法校验、失败回滚。
- `forward.sh`: 安全版通用端口转发脚本，支持自动识别并保护 SSH 端口、规则备份/回滚、单端口 TCP/UDP 转发、全端口转发、规则查看与清理。
- `codex-switch.sh`: Codex / OpenAI-compatible 中转配置管理器，支持多配置切换、测试、启动 Codex CLI。
- `claude-switch.sh`: Claude Code / AgentRouter 配置管理器，支持官方模式和第三方网关切换。
- `install.sh`: 通用安装器，可安装 `codex-switch`、`claude-switch`、`caddy-manager`、`forward` 或全部脚本。
- `install-codex-switch.sh`: 兼容旧命令的安装入口，内部调用 `install.sh codex-switch`。

## 统一入口

推荐直接使用 Cloudflare 脚本入口：

```bash
bash <(curl -fsSL https://sh.misk.cc)
```

查看可安装目标：

```bash
bash <(curl -fsSL https://sh.misk.cc) --list
```

安装全部脚本：

```bash
bash <(curl -fsSL https://sh.misk.cc) all
```

安装到指定目录：

```bash
TARGET_DIR="$HOME/.local/bin" \
bash <(curl -fsSL https://sh.misk.cc) all
```

如果 Cloudflare 入口暂时不可用，也可以直接使用 GitHub Raw：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/openbox.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) all
```

## 一键安装并启动 Codex Switch

```bash
bash <(curl -fsSL https://sh.misk.cc) codex-switch && sw
```

旧安装命令仍然可用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install-codex-switch.sh) && sw
```

安装完成后可直接使用：

```bash
sw
codex-switch
```

直接启动当前 Codex 配置：

```bash
sw --launch
```

一键安装或升级官方 Codex CLI：

```bash
sw --install-codex
```

`sw --install-codex` 默认切回官方 Codex CLI。需要第三方中转时再添加配置：

```bash
sw --add router https://api.example.com/v1 sk-xxx gpt-5.4
sw --activate router
```

切回官方：

```bash
sw --official
```

## 一键安装并启动 Claude Switch

```bash
bash <(curl -fsSL https://sh.misk.cc) claude-switch && cw
```

安装完成后可直接使用：

```bash
cw
claude-switch
```

一键安装或升级 Claude Code：

```bash
cw --install-claude
```

`cw --install-claude` 默认使用官方 Claude Code，不写第三方环境变量。需要 AgentRouter 或其他 Anthropic-compatible 网关时再添加配置：

```bash
cw --add router https://xxx.xx sk-xxx
cw --activate router
```

第三方配置会写入：

```bash
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY
```

切回官方：

```bash
cw --official
```

## 一键安装 Caddy 管理脚本

```bash
bash <(curl -fsSL https://sh.misk.cc) caddy-manager
```

安装完成后可直接使用：

```bash
cm
caddy-manager
```

## 一键安装 Forward 转发脚本

```bash
bash <(curl -fsSL https://sh.misk.cc) forward
```

安装完成后可直接使用：

```bash
forward --help
```

常见示例：

```bash
# 单端口 TCP 转发
forward -a -s 8080 -t 192.168.1.100 -p 80 -P tcp

# 同时转发 TCP + UDP
forward -a -s 7001 -t 1.2.3.4 -p 7001 -P all

# 全端口转发，自动识别并保护当前 SSH 端口
forward --all -t 1.2.3.4

# 手动指定 SSH 端口
forward --all -t 1.2.3.4 --ssh-port 22

# 查看规则
forward --list

# 清理本脚本添加的规则
forward --flush

# 如误操作，可用自动生成的回滚脚本恢复
/root/forward-rollback.sh
```

## Caddy 反代部署

`caddy_manager.sh` 适合在服务器上交互式部署 Caddy 反代。常用流程：

1. 安装管理脚本：

```bash
bash <(curl -fsSL https://sh.misk.cc) caddy-manager
```

2. 启动菜单：

```bash
cm
```

3. 选择 `11. 一键反代`。

4. 输入站点地址，例如：

```text
api.example.com
```

5. 选择本机监听服务，或手动输入上游地址，例如：

```text
127.0.0.1:8317
```

6. 预览配置并确认应用。

Caddy 会自动处理 HTTPS，前提是：

- 域名已解析到当前服务器公网 IP
- 服务器 `80` 和 `443` 端口可访问
- 没有其他服务占用 `80/443`

如果输入的是普通域名，例如 `api.example.com`，最终访问地址是：

```text
https://api.example.com
```

如果输入的是 `http://api.example.com` 或 `:8080`，则按你输入的 HTTP/端口方式监听，不会自动签发公网 HTTPS 证书。

## 本地运行脚本

克隆仓库后，也可以直接运行：

```bash
git clone https://github.com/liut-coder/openbox.git
cd openbox
bash caddy_manager.sh
```

常用快捷方式：

```bash
alias cm='bash /path/to/caddy_manager.sh'
```

## Codex Switch 常用命令

```bash
sw --list
sw --show
sw --add work https://api.example.com/v1 sk-xxx gpt-5.4
sw --activate work
sw --switch work
sw --official
sw --test
sw --delete work
```

完整文档见 [docs/codex-switch.md](docs/codex-switch.md)。

## Claude Switch 常用命令

```bash
cw --list
cw --show
cw --add router https://xxx.xx sk-xxx
cw --activate router
cw --switch router
cw --official
cw --test
cw --delete router
```

完整文档见 [docs/claude-switch.md](docs/claude-switch.md)。

## 注意

- `caddy_manager.sh` 建议使用 `root` 运行。
- `forward.sh` 需要 `root` 运行，并依赖 `iptables`；会修改转发/NAT 规则，执行前会备份当前规则并生成 `/root/forward-rollback.sh` 回滚脚本。
- `codex-switch.sh` 依赖 `bash`、`curl`、`jq`；安装器会尝试自动安装缺失依赖。
- `claude-switch.sh` 依赖 `bash`、`curl`、`jq`；安装器会尝试自动安装缺失依赖。
- `caddy_manager.sh` 会按需安装 Caddy，并写入 `/etc/caddy/Caddyfile`。
- 不要提交私钥、API Key、OAuth Token、生产配置文件。

# openbox

公开脚本集合，用于快速配置服务器反代、管理 Codex CLI 中转配置。

## 脚本

- `caddy_manager.sh`: Caddy 交互式管理脚本，支持一键反代、配置预览、语法校验、失败回滚。
- `codex-switch.sh`: Codex / OpenAI-compatible 中转配置管理器，支持多配置切换、测试、启动 Codex CLI。
- `install.sh`: 通用安装器，可安装 `codex-switch`、`caddy-manager` 或全部脚本。
- `install-codex-switch.sh`: 兼容旧命令的安装入口，内部调用 `install.sh codex-switch`。

## 通用一键安装

查看可安装目标：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) --list
```

安装全部脚本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) all
```

安装到指定目录：

```bash
TARGET_DIR="$HOME/.local/bin" \
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) all
```

## 一键安装并启动 Codex Switch

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) codex-switch && sw
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

## 一键安装 Caddy 管理脚本

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) caddy-manager
```

安装完成后可直接使用：

```bash
cm
caddy-manager
```

## Caddy 反代部署

`caddy_manager.sh` 适合在服务器上交互式部署 Caddy 反代。常用流程：

1. 安装管理脚本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) caddy-manager
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
sw --test
sw --delete work
```

完整文档见 [docs/codex-switch.md](docs/codex-switch.md)。

## 注意

- `caddy_manager.sh` 建议使用 `root` 运行。
- `codex-switch.sh` 依赖 `bash`、`curl`、`jq`；安装器会尝试自动安装缺失依赖。
- `caddy_manager.sh` 会按需安装 Caddy，并写入 `/etc/caddy/Caddyfile`。
- 不要提交私钥、API Key、OAuth Token、生产配置文件。

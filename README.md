# openbox

公开脚本集合，用于快速配置服务器反代、管理 Codex CLI 中转配置。

## 脚本

- `openbox.sh`: Caddy 交互式管理脚本，支持一键反代、配置预览、语法校验、失败回滚。
- `codex-switch.sh`: Codex / OpenAI-compatible 中转配置管理器，支持多配置切换、测试、启动 Codex CLI。
- `install-codex-switch.sh`: `codex-switch.sh` 安装器，会安装为 `codex-switch` 和 `sw` 两个命令。

## 一键安装并启动 Codex Switch

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

## 安装到指定目录

默认安装到 `/usr/local/bin`。如需安装到用户目录：

```bash
TARGET_DIR="$HOME/.local/bin" \
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install-codex-switch.sh)
```

## 使用 Caddy 管理脚本

```bash
bash openbox.sh
```

常用快捷方式：

```bash
alias cm='bash /path/to/openbox.sh'
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

- `openbox.sh` 建议使用 `root` 运行。
- `codex-switch.sh` 依赖 `bash`、`curl`、`jq`；安装器会尝试自动安装缺失依赖。
- 不要提交私钥、API Key、OAuth Token、生产配置文件。

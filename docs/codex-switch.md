# codex-switch

`codex-switch` 是一个专用于 Codex CLI 的配置切换脚本。它只管理 Codex 需要的 OpenAI-compatible 配置：

- `Base URL`
- `API Key`
- `Model`

切换第三方配置时，脚本会同步写入本地 shell 环境和 Codex CLI 配置。切回官方时，脚本会清理 `OPENAI_*` 环境变量，并尽量移除脚本写入的第三方 Codex 配置。

## 文件结构

```text
.
├── codex-switch.sh        # 主脚本
├── install.sh             # 通用安装器
├── install-codex-switch.sh # 兼容旧命令的安装入口
└── docs/codex-switch.md
```

## 安装

从 openbox 仓库安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) codex-switch
```

安装后会得到两个命令：

```bash
codex-switch
sw
```

旧入口仍然可用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install-codex-switch.sh)
```

安装到指定目录：

```bash
TARGET_DIR="$HOME/.local/bin" \
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) codex-switch
```

## 快速使用

进入交互菜单：

```bash
sw
```

新增一个 Codex 中转配置：

```bash
sw --add work https://api.example.com/v1 sk-xxx gpt-5.4
```

切换配置但不启动 Codex：

```bash
sw --activate work
```

切换配置并启动 Codex：

```bash
sw --switch work
```

切回官方 Codex CLI：

```bash
sw --official
```

直接启动当前配置：

```bash
sw --launch
```

## 常用命令

```bash
sw --list
sw --show
sw --show work
sw --test
sw --test work
sw --add work https://api.example.com/v1 sk-xxx gpt-5.4
sw --activate work
sw --switch work
sw --official
sw --delete work
sw --install-codex
sw --launch
```

## 一键部署 Codex CLI

```bash
sw --install-codex
```

脚本会优先检测 `npm`。如果缺失，会尝试自动安装 `nodejs` / `npm`，然后执行：

```bash
npm install -g @openai/codex
```

安装完成后默认切回官方 Codex CLI，不启用任何第三方中转。需要第三方时再运行 `sw --add` 和 `sw --activate`。

## 写入内容

脚本自己的配置：

```text
~/.config/codex-switch/
├── profiles.json
├── state.json
└── current.env
```

`current.env` 会导出：

```bash
OPENAI_BASE_URL
OPENAI_API_KEY
OPENAI_MODEL
```

官方模式下 `current.env` 会清理这些变量：

```bash
unset OPENAI_BASE_URL
unset OPENAI_API_KEY
unset OPENAI_MODEL
```

脚本会在 `~/.bashrc` 中写入一个受管区块，用于自动加载 `current.env`。如果存在 `~/.zshrc`，也会同步更新。

Codex CLI 配置会优先通过 `codex config set` 写入。如果当前 Codex CLI 不支持该命令，会回退写入：

```text
~/.codex/config.toml
```

如果本机尚未安装 `codex` 命令，会先写入：

```text
~/.config/codex/config.json
```

执行 `sw --official` 时，脚本会尝试：

- 清理 `OPENAI_BASE_URL` / `OPENAI_API_KEY` / `OPENAI_MODEL`
- 调用 `codex config unset`（如果当前 Codex CLI 支持）
- 清理 `~/.config/codex/config.json` 中的脚本字段
- 从 `~/.codex/config.toml` 移除脚本写入的 OpenAI-compatible provider，并保留一份 `.codex-switch.bak` 备份

## 依赖

- `bash`
- `curl`
- `jq`
- `npm`（只在执行 `sw --install-codex` 时需要）

安装器会尝试自动安装 `curl` 和 `jq`。

## 注意

- 这个脚本只服务 Codex 配置，不管理其他 CLI。
- `official` 是内置配置名，不能删除或覆盖。
- `Base URL` 通常需要包含 `/v1`，例如 `https://api.example.com/v1`。
- 不要把 `profiles.json` 或 API Key 提交到公开仓库。

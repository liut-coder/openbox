# codex-switch

`codex-switch` 是一个专用于 Codex CLI 的配置切换脚本。它只管理 Codex 需要的 OpenAI-compatible 配置：

- `Base URL`
- `API Key`
- `Model`

切换配置时，脚本会同步写入本地 shell 环境和 Codex CLI 配置。

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

如果当前已有激活配置，安装完成后会自动同步到 Codex CLI。

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

脚本会在 `~/.bashrc` 中写入一个受管区块，用于自动加载 `current.env`。如果存在 `~/.zshrc`，也会同步更新。

Codex CLI 配置会优先通过 `codex config set` 写入。如果当前 Codex CLI 不支持该命令，会回退写入：

```text
~/.codex/config.toml
```

如果本机尚未安装 `codex` 命令，会先写入：

```text
~/.config/codex/config.json
```

## 依赖

- `bash`
- `curl`
- `jq`
- `npm`（只在执行 `sw --install-codex` 时需要）

安装器会尝试自动安装 `curl` 和 `jq`。

## 注意

- 这个脚本只服务 Codex 配置，不管理其他 CLI。
- `Base URL` 通常需要包含 `/v1`，例如 `https://api.example.com/v1`。
- 不要把 `profiles.json` 或 API Key 提交到公开仓库。

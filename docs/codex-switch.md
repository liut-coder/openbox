# codex-switch

用于管理多个 Codex / OpenAI 兼容中转配置，并在切换时自动同步到本地环境和官方 `codex` CLI。
在保持现有 OpenAI 兼容配置不变的前提下，已支持记录多 Provider 类型，例如 `gemini`、`ollama`、`openrouter`。

## 文件结构

```text
.
├── codex-switch.sh   # 主脚本
├── install-codex-switch.sh
├── README.md
└── HISTORY.md
```

## 功能

- 管理多套中转配置
- 一键切换当前配置
- 自动写入 `OPENAI_BASE_URL`、`OPENAI_API_KEY`、`OPENAI_MODEL`
- 自动同步 `codex config set ...`
- 支持一键安装或升级官方 `codex` CLI
- 支持一键安装或升级 Gemini CLI
- 支持多 Provider 配置：`openai-compatible` / `gemini` / `ollama` / `openrouter` / `anthropic`
- 支持连接测试
- 支持交互式菜单和命令行模式

## 安装

### 从仓库安装

```bash
git clone https://github.com/liut-coder/openbox.git
cd openbox
bash install-codex-switch.sh
```

### 远程安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install-codex-switch.sh)
```

如果你 fork 了仓库，把上面的 `liut-coder/codex-switch` 改成你自己的仓库路径即可。也可以通过环境变量覆盖下载地址：

```bash
CODEX_INSTALL_BASE_URL="https://raw.githubusercontent.com/<your-name>/openbox/main" \
bash <(curl -fsSL https://raw.githubusercontent.com/<your-name>/openbox/main/install-codex-switch.sh)
```

## 使用

### 交互模式

```bash
codex-switch
# 或
sw
```

### 命令行模式

```bash
codex-switch --list
codex-switch --switch work
codex-switch --activate work
codex-switch --test
codex-switch --test work
codex-switch --show
codex-switch --add work https://api.example.com/v1 sk-xxx gpt-5.4
codex-switch --add work https://api.example.com/v1 sk-xxx gpt-5.4 gemini
codex-switch --add-provider ollama-home ollama http://127.0.0.1:11434/v1 "" qwen2.5-coder:latest
codex-switch --delete work
codex-switch --install-codex
codex-switch --install-gemini
codex-switch --launch
codex-switch --launch-gemini
```

## Provider 扩展说明

- 老配置和老命令默认按 `openai-compatible` 处理，不影响现有功能。
- `gemini`、`openrouter`、`ollama` 本质上仍建议提供一个可被 Codex 使用的兼容入口。
- Gemini 官方 CLI 安装和启动是独立链路，不会和 `codex` 安装流程混用。
- `anthropic` 配置可以保存，但不会自动同步到 Codex CLI，因为原生接口不是 OpenAI-compatible。
- `ollama` 默认建议地址是 `http://127.0.0.1:11434/v1`，`API Key` 可留空。

## 一键部署 Codex CLI

```bash
codex-switch --install-codex
```

或在交互菜单中选择“`一键部署官方 Codex CLI`”。

脚本会优先检测 `npm`，如果缺失则尝试自动安装 `nodejs` / `npm`，然后执行：

```bash
npm install -g @openai/codex
```

如果当前已有激活配置，安装完成后会自动同步到 Codex CLI。

## 一键部署 Gemini CLI

```bash
codex-switch --install-gemini
```

或在交互菜单中选择“`一键部署 Gemini CLI`”。

脚本会优先检测 `npm`，如果缺失则尝试自动安装 `nodejs` / `npm`，然后执行：

```bash
npm install -g @google/gemini-cli
```

如果当前激活配置是 `gemini` provider，安装完成后会自动导出：

```bash
GEMINI_API_KEY
GOOGLE_API_KEY
```

直接启动 Gemini CLI：

```bash
codex-switch --launch-gemini
```

## 存储位置

脚本自己的配置：

```text
~/.config/codex-switch/
├── profiles.json
├── state.json
└── current.env
```

官方 Codex CLI 配置：

```text
~/.config/codex/config.json
```

脚本会在 `~/.bashrc` 中写入一个受管区块，用于自动加载 `current.env`。如果存在 `~/.zshrc`，也会同步更新。

## 依赖

- `bash`
- `jq`
- `curl`
- 官方 `codex` CLI（可选，但推荐）

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install -y jq curl
```

## 跨机器使用建议

1. 把仓库推到 GitHub。
2. 在新机器执行仓库安装或远程安装命令。
3. 安装官方 `codex` CLI。
4. 运行 `sw` 新增或切换配置。

如果你希望多台机器共用同一套配置，建议后续再把 `~/.config/codex-switch/profiles.json` 做加密同步，而不是直接把 API Key 明文提交到仓库。

## 从 cmdbox 拆分

如果你当前是在 `cmdbox` 仓库里维护这套脚本，把本目录 5 个文件作为新仓库根目录即可：

```text
standalone/
├── .gitignore
├── codex-switch.sh
├── install-codex-switch.sh
├── README.md
└── HISTORY.md
```

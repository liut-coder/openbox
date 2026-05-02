# claude-switch

`claude-switch` 是 Claude Code 的配置切换脚本。它默认保留官方 Claude Code 行为，需要第三方 AgentRouter / Anthropic-compatible 网关时再写入环境变量。

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) claude-switch
```

安装后会得到两个命令：

```bash
claude-switch
cw
```

安装到指定目录：

```bash
TARGET_DIR="$HOME/.local/bin" \
bash <(curl -fsSL https://raw.githubusercontent.com/liut-coder/openbox/main/install.sh) claude-switch
```

## 快速使用

进入交互菜单：

```bash
cw
```

一键安装或升级 Claude Code：

```bash
cw --install-claude
```

脚本会优先检测 `npm`。如果缺失，会尝试自动安装 `nodejs` / `npm`，然后执行：

```bash
npm install -g @anthropic-ai/claude-code
```

安装完成后默认切回官方 Claude Code，不写第三方网关变量。

新增一个 AgentRouter 配置：

```bash
cw --add router https://xxx.xx sk-xxx
```

切换配置但不启动 Claude Code：

```bash
cw --activate router
```

切换配置并启动 Claude Code：

```bash
cw --switch router
```

切回官方 Claude Code：

```bash
cw --official
```

直接启动当前配置：

```bash
cw --launch
```

## 常用命令

```bash
cw --list
cw --show
cw --show router
cw --test
cw --test router
cw --add router https://xxx.xx sk-xxx
cw --activate router
cw --switch router
cw --official
cw --delete router
cw --install-claude
cw --launch
```

## 写入内容

脚本自己的配置：

```text
~/.config/claude-switch/
├── profiles.json
├── state.json
└── current.env
```

第三方模式下 `current.env` 会导出：

```bash
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY
```

官方模式下 `current.env` 会清理这些变量：

```bash
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_API_KEY
```

脚本会在 `~/.bashrc` 中写入一个受管区块，用于自动加载 `current.env`。如果存在 `~/.zshrc`，也会同步更新。

## 依赖

- `bash`
- `curl`
- `jq`
- `npm`（只在执行 `cw --install-claude` 时需要）

安装器会尝试自动安装 `curl` 和 `jq`。

## 注意

- `official` 是内置配置名，不能删除或覆盖。
- `ANTHROPIC_BASE_URL` 建议填写网关根地址，例如 `https://xxx.xx`。
- 同一个 API Key 会同时写入 `ANTHROPIC_AUTH_TOKEN` 和 `ANTHROPIC_API_KEY`，兼容不同网关读取方式。
- 不要把 `profiles.json` 或 API Key 提交到公开仓库。

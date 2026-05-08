# openbox

公开脚本集合，按分类组织。一键安装、统一入口。

## 一键入口

```bash
bash <(curl -fsSL https://sh.misk.cc)
```

查看可安装列表：

```bash
bash <(curl -fsSL https://sh.misk.cc) --list
```

## 分类

### proxy — 代理 / 转发 / 反代

| 脚本 | 命令 | 说明 |
|------|------|------|
| `caddy-manager` | `cm` / `caddy-manager` | Caddy 交互式反代管理 |
| `forward` | `fw` / `forward` | iptables 安全端口转发 |

```bash
bash <(curl -fsSL https://sh.misk.cc) proxy
```

### tools — 开发工具 / 切换器

| 脚本 | 命令 | 说明 |
|------|------|------|
| `codex-switch` | `sw` / `codex-switch` | Codex CLI 多配置切换 |
| `claude-switch` | `cw` / `claude-switch` | Claude Code 网关切换 |
| `proxy-setup` | `proxy` / `proxy-setup` | 代理环境一键配置 |

```bash
bash <(curl -fsSL https://sh.misk.cc) tools
```

### bench — 服务器测试

| 脚本 | 命令 | 说明 |
|------|------|------|
| `nodequality` | `nq` / `nodequality` | NodeQuality 服务器质量测试 |
| `fusion-bench` | `fjg` / `fusion-bench` | 融合怪 VPS 综合测试 |
| `yabs` | `yabs` | YABS 服务器性能测试 |
| `bench-sh` | `bench` / `bench-sh` | bench.sh 基础性能测试 |
| `ip-quality` | `ipq` / `ip-quality` | Check.Place IP 质量测试 |
| `unlock-test` | `unlock` / `unlock-test` | 流媒体解锁测试 |
| `return-route` | `route` / `return-route` | 回程路由测试 |
| `nws` | `nws` | nws 综合测速 |

```bash
bash <(curl -fsSL https://sh.misk.cc) bench
```

### agent — 助手常用脚本

| 脚本 | 命令 | 说明 |
|------|------|------|
| `agent-status` | `ast` / `agent-status` | 快速状态面板 |
| `agent-restart` | `ars` / `agent-restart` | 常用服务重启入口 |
| `agent-sync` | `asg` / `agent-sync` | 刷新 / 同步入口 |

```bash
bash <(curl -fsSL https://sh.misk.cc) agent
```

### 规划中

| 分类 | 说明 |
|------|------|
| `monitor` | 内存/磁盘/端口监控预警 |
| `security` | SSH 加固、fail2ban、防火墙收口 |
| `bootstrap` | Debian/Ubuntu 新机初始化 |
| `backup` | 目录打包、推送到文件中心、数据库导出 |

## 安装与卸载

```bash
# 安装
bash <(curl -fsSL https://sh.misk.cc) <脚本名>       # 单个
bash <(curl -fsSL https://sh.misk.cc) <分类>          # 整类
bash <(curl -fsSL https://sh.misk.cc) all              # 全部

# 卸载
bash <(curl -fsSL https://sh.misk.cc) --uninstall <目标>

# 查看
bash <(curl -fsSL https://sh.misk.cc) --list
bash <(curl -fsSL https://sh.misk.cc) --help
```

自定义安装目录：

```bash
TARGET_DIR="$HOME/.local/bin" bash <(curl -fsSL https://sh.misk.cc) tools
```

## 各脚本详细文档

- [Codex Switch](docs/codex-switch.md)
- [Claude Switch](docs/claude-switch.md)

## Caddy 反代部署

`caddy-manager` 适合在服务器上交互式部署 Caddy 反代。常用流程：

```bash
bash <(curl -fsSL https://sh.misk.cc) caddy-manager
cm
```

选 `一键反代` → 输入域名 → 输入上游 → 预览确认。

Caddy 自动处理 HTTPS，前提：
- 域名已解析到当前服务器公网 IP
- 服务器 `80/443` 端口可访问
- 没有其他服务占用 `80/443`

## Forward 转发脚本

```bash
bash <(curl -fsSL https://sh.misk.cc) forward
fw --help
```

常见示例：

```bash
fw -a -s 8080 -t 192.168.1.100 -p 80 -P tcp    # 单端口 TCP
fw -a -s 7001 -t 1.2.3.4 -p 7001 -P all         # TCP+UDP
fw --all -t 1.2.3.4                               # 全端口转发
fw --list                                         # 查看规则
fw --flush                                        # 清理规则
/root/forward-rollback.sh                         # 回滚
```

## Codex Switch 常用命令

```bash
sw --list
sw --show
sw --add work https://api.example.com/v1 sk-xxx gpt-5.4
sw --activate work
sw --official
sw --test
sw --delete work
```

详见 [docs/codex-switch.md](docs/codex-switch.md)。

## Claude Switch 常用命令

```bash
cw --list
cw --show
cw --add router https://xxx.xx sk-xxx
cw --activate router
cw --official
cw --test
cw --delete router
```

详见 [docs/claude-switch.md](docs/claude-switch.md)。

## 注意

- `caddy_manager.sh` 建议 `root` 运行。
- `forward.sh` / `fw` 需要 `root`，依赖 `iptables`；执行前自动备份并生成 `/root/forward-rollback.sh`。
- `codex-switch.sh` / `claude-switch.sh` 依赖 `bash`、`curl`、`jq`；安装器会自动补依赖。
- 不要提交私钥、API Key、OAuth Token、生产配置文件。

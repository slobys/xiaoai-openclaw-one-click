# XiaoAI OpenClaw One-Click

小爱音箱 Pro / Xiaomi 智能音箱 Pro 接入 Open-XiaoAI、OpenClaw 和大模型的一键部署脚本。

> 适用机型：小爱音箱 Pro（LX06）和 Xiaomi 智能音箱 Pro（OH2P）。其他型号不要直接刷 Open-XiaoAI 固件。

## 一键菜单

NAS / 普通 Linux 用户：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

root / iStoreOS / OpenWrt 用户：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

国内 / Gitee（root 用户）：

```sh
curl -fsSL https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

完整项目方式：

```sh
git clone https://github.com/slobys/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sh bootstrap.sh
```

## 直接命令

在 OpenClaw 所在设备上部署 OpenClaw API bridge：

```sh
sh install-openclaw-bridge.sh
```

只部署服务器端：

```sh
sh install.sh --server-only
```

只初始化音箱端 Client：

```sh
sh install.sh --client-only --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
```

服务器和音箱端一起部署：

```sh
sh install.sh --all --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
```

## 部署结构

- 音箱端：刷入 Open-XiaoAI 补丁固件后，运行 Rust client，连接 `ws://服务器IP:4399`
- 服务器端：运行 `idootop/open-xiaoai-migpt:latest` Docker 容器，挂载 `config.ts` 和 `.env`
- 大模型端：默认使用 `slobys/xiaoai` 的 `config.ts`，支持 DeepSeek、OpenAI、Gemini、Ollama，也支持 OpenAI-compatible 地址
- OpenClaw：如果 OpenClaw 和 MiGPT 服务器不在同一台设备，在 OpenClaw 设备上运行本项目的 `openclaw-llm-bridge`，让 MiGPT 服务器通过 HTTP 调用它
- Ollama：如果 Gemma / Qwen 等模型在局域网电脑上运行，MiGPT 服务器可以直接调用 Ollama 的 OpenAI-compatible `/v1` 接口

典型三设备拓扑：

```text
小爱音箱  ->  ws://软路由或NAS:4399  ->  open-xiaoai-migpt Docker
                                      ->  http://OpenClaw设备IP:11435/v1
                                      ->  openclaw agent --session-key agent:main:xiaoai
```

## 前置条件

1. 音箱已经按 Open-XiaoAI 教程刷好补丁固件，并能 SSH 登录。
2. 服务器/NAS 能被音箱局域网访问，开放 TCP `4399`。
3. 如果直连云模型，至少准备一个模型 API Key：DeepSeek / OpenAI / Gemini。Ollama 局域网调用不需要真实 API Key。
4. 如果接入 OpenClaw，OpenClaw 所在设备要能被 MiGPT 服务器局域网访问，开放 TCP `11435`。
5. 如果接入 Ollama，Ollama 所在电脑要能被 MiGPT 服务器局域网访问，开放 TCP `11434`。

## 语音前缀

默认不需要额外前缀，说话会直接进入当前模式。可用口令：

```text
设置前缀小爱
查看前缀
关闭前缀
```

设置前缀后，普通问答必须先说这个前缀，例如“小爱太阳有多大”。`开启AI`、`切换ollama`、`关闭前缀` 这类管理口令不受前缀限制。

## Ollama 局域网模型

如果你的模型跑在局域网电脑的 Ollama 上，先在那台电脑确认模型名：

```sh
ollama list
```

当前默认按你的局域网拓扑写入：

```sh
OPENCLAW_BASE_URL=http://192.168.2.238:11435/v1
OPENCLAW_API_KEY=xiaoai-local
OPENCLAW_DISPLAY_MODEL=open
OLLAMA_BASE_URL=http://192.168.2.193:11434/v1
OLLAMA_MODEL=qwen3:4b
```

如果你要测试其他模型，只改 `OLLAMA_MODEL`，例如 `qwen3:8b`。

然后重建 MiGPT server 容器：

```sh
xiaoai-openclaw
```

菜单选：

```text
1) 一键部署服务器端 Docker
```

也可以在运行菜单时直接传入配置，脚本会覆盖 `/opt/xiaoai-openclaw/.env` 里的旧 Ollama 值：

```sh
OLLAMA_BASE_URL=http://192.168.2.193:11434/v1 OLLAMA_MODEL=qwen3:4b xiaoai-openclaw
```

对小爱说：

```text
开启AI
切换ollama
测试模型
```

可用口令包括：`切换ollama`、`切换欧拉拉`、`切换奥拉马`、`切换gemma`、`切换电脑`、`切换本地电脑`。

如果 Ollama 只监听本机，需要在 Ollama 电脑上允许局域网访问，例如 Linux systemd 环境可设置 `OLLAMA_HOST=0.0.0.0:11434` 后重启 Ollama；Windows / macOS 也要确保防火墙放行 `11434`。

## OpenClaw 不同设备部署

如果你的 OpenClaw 在电脑 / 独立服务器上，而小爱项目跑在软路由或 NAS 上，按这个方式做：

1. 在 OpenClaw 所在设备运行：

```sh
cd xiaoai-openclaw-one-click
sh install-openclaw-bridge.sh
```

bridge 默认使用 OpenClaw Agent 模式，并绑定固定会话 `agent:main:xiaoai`，这样小爱连续对话会进入同一个 OpenClaw 会话，而不是每次都变成无上下文的一次性模型调用。

常用可选项：

```sh
OPENCLAW_SESSION_KEY=agent:main:xiaoai \
sh install-openclaw-bridge.sh
```

默认不强制指定模型，使用 OpenClaw 当前配置的默认 Agent 模型。如果确实要指定模型，再额外传 `OPENCLAW_MODEL=模型名`。

如果只想跑无上下文的一次性模型调用，可以加 `OPENCLAW_BRIDGE_MODE=infer`。

2. 在 MiGPT 服务器的 `/opt/xiaoai-openclaw/.env` 里设置：

```sh
OPENCLAW_BASE_URL=http://192.168.2.238:11435/v1
OPENCLAW_API_KEY=任意字符串
OPENCLAW_DISPLAY_MODEL=open
```

`OPENAI_BASE_URL` / `OPENAI_API_KEY` 仍然保留给真正的 OpenAI 使用。OpenClaw 使用单独的 `open` 口令，不占用 OpenAI 位置。MiGPT 服务器上的 `OPENCLAW_DISPLAY_MODEL` 只影响日志和口播显示，不是真实模型名。

3. 重新创建 MiGPT server 容器，让新的 `.env` 注入容器：

```sh
xiaoai-openclaw
```

然后在菜单里选择：

```text
1) 一键部署服务器端 Docker
```

直接执行命令也可以：

```sh
sh install.sh --server-only
```

注意：`docker restart xiaoai-openclaw` 不会重新读取 `--env-file`，改过 `/opt/xiaoai-openclaw/.env` 后必须重建容器。

4. 对小爱说：

```text
开启AI
切换open
测试模型
```

`openclaw-llm-bridge` 同时兼容 `/v1/responses` 和 `/v1/chat/completions`。`slobys/xiaoai` 的 OpenAI 分支默认会调用 `/responses`，所以这里重点支持了 Responses 格式。健康检查可用 `curl http://OpenClaw设备IP:11435/health`，正常会返回 `mode`、`model` 和 `sessionKey`。

安全建议：bridge 默认只适合局域网。公网使用必须套内网 VPN / Tailscale / 防火墙白名单，或者设置 `OPENCLAW_BRIDGE_TOKEN`。

## 安装后文件

- 工作目录：`/opt/xiaoai-openclaw`
- 配置文件：`/opt/xiaoai-openclaw/config.ts`
- 环境变量：`/opt/xiaoai-openclaw/.env`
- 管理命令：`xiaoai-openclaw`
- OpenClaw bridge：`/opt/openclaw-llm-bridge`

## 常用语音命令

- `开启AI`
- `开启小爱`
- `切换open`
- `切换ollama`
- `切换deepseek`
- `切换openai`
- `切换谷歌`
- `测试模型`
- `停止` / `闭嘴`

## 已知边界

Open-XiaoAI 上游仓库已在 2026-04-04 归档停止维护，但 Docker 镜像和 client artifact 仍可用。这个一键项目会尽量只做部署编排，不改刷机流程。

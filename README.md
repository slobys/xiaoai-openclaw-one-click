# XiaoAI OpenClaw One-Click

小爱音箱接入 OpenClaw、DeepSeek、OpenAI、Gemini、Ollama 的一键脚本。

现在同时保留两条路线：

- 免刷机版：小米账号登录，不需要 SSH 音箱，不刷 Open-XiaoAI 固件。
- 刷机版：沿用已刷 Open-XiaoAI 固件的旧版体验。

## 一键菜单

国内网络优先用 Gitee：

```sh
curl -fsSL https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && XIAOAI_OPENCLAW_BASE_URL=https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main xiaoai-openclaw
```

GitHub：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

NAS / 普通 Linux 非 root 下载到临时目录：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

完整项目方式：

```sh
git clone https://github.com/slobys/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sh bootstrap.sh
```

## 免刷机版

```sh
# 配置小米账号并启动免刷机服务
sh install-noflash.sh --install

# 修改小米账号、passToken、音箱名称等基础信息
sh install-noflash.sh --configure

# 修改 .env 或 config.ts 后重建容器
sh install-noflash.sh --restart
```

免刷机版工作目录：

```text
/opt/open-xiaoai-migpt/.env
/opt/open-xiaoai-migpt/config.ts
```

`.env` 保留现在刷机版已经优化好的模型参数布局，同时增加小米账号、passToken、音箱 DID/名称。`config.ts` 继续保留多模型切换、测试模型、上下文和错误提示逻辑。

## 结构

```text
免刷机版：
小爱音箱账号登录  ->  mi-gpt Docker  ->  DeepSeek / OpenAI / Gemini / Ollama / OpenClaw API Bridge

刷机版：
小爱音箱 Open-XiaoAI Client  ->  ws://软路由或NAS:4399  ->  open-xiaoai-migpt Docker
```

免刷机版需要准备：

- 小米 ID、密码或浏览器 Cookie 里的 `passToken`
- 米家中的音箱名称或设备 DID
- 云模型至少配置一个 API Key，或局域网 OpenClaw/Ollama 地址

刷机版额外需要：

- 音箱已刷 Open-XiaoAI 补丁固件，并能 SSH 登录。
- MiGPT 服务器开放 TCP `4399`。

## 刷机版直接部署

```sh
# 只部署 MiGPT 服务器端
sh install.sh --server-only

# 只初始化音箱端 client
sh install.sh --client-only --speaker-ip 192.168.31.227 --server-ip 192.168.31.10

# 服务器和音箱端一起部署
sh install.sh --all --speaker-ip 192.168.31.227 --server-ip 192.168.31.10

# 在 OpenClaw 设备上部署 API bridge
sh install-openclaw-bridge.sh
```

刷机版服务器端启动后会显示 `ws://...:4399`。这个地址必须是音箱能访问的局域网 IP。识别不准时手动指定：

```sh
SERVER_IP=192.168.2.1 xiaoai-openclaw
```

刷机版配置文件在 `/opt/xiaoai-openclaw/.env` 和 `/opt/xiaoai-openclaw/config.ts`，改完后用菜单 `10) 重启/重建刷机版服务器端 Docker`。

默认保留最近 6 轮上下文，连续追问会接上前面的内容。需要关闭时改：

```env
CONVERSATION_TURNS=0
```

## DeepSeek

免刷机版在 `/opt/open-xiaoai-migpt/.env` 设置；刷机版在 `/opt/xiaoai-openclaw/.env` 设置：

```env
DEEPSEEK_API_KEY=sk-xxxx
DEEPSEEK_MODEL=deepseek-v4-flash
```

## OpenClaw

OpenClaw 不在 MiGPT 同一台设备时，在 OpenClaw 设备运行：

```sh
sh install-openclaw-bridge.sh
```

然后在 MiGPT 服务器的 `.env` 设置：

```env
OPENCLAW_BASE_URL=http://OpenClaw设备IP:11435/v1
OPENCLAW_API_KEY=xiaoai-local
OPENCLAW_DISPLAY_MODEL=open
OPENCLAW_TIMEOUT_MS=90000
OPENCLAW_TEST_TIMEOUT_MS=30000
```

bridge 默认使用 OpenClaw Agent 模式，并绑定会话 `agent:main:xiaoai`，连续对话会进入同一个会话。只想跑一次性模型调用时再设置：

```sh
OPENCLAW_BRIDGE_MODE=infer sh install-openclaw-bridge.sh
```

健康检查：

```sh
curl http://OpenClaw设备IP:11435/health
```

## Ollama

先确认模型名：

```sh
ollama list
```

在 MiGPT 服务器的 `.env` 设置：

```env
OLLAMA_BASE_URL=http://电脑IP:11434/v1
OLLAMA_MODEL=qwen3:4b
```

Ollama 如果只监听本机，需要设置 `OLLAMA_HOST=0.0.0.0:11434` 并放行防火墙。

也可以运行菜单时直接覆盖：

```sh
OLLAMA_BASE_URL=http://192.168.2.193:11434/v1 OLLAMA_MODEL=qwen3:4b xiaoai-openclaw
```

## 语音命令

```text
开启AI
开启小爱
关闭AI
原生小爱
问AI你是谁
切换open
切换ollama
切换deepseek
切换openai
切换谷歌
测试模型
清空上下文
停止
闭嘴
```

免刷机版默认是原生小爱模式，普通问题先交给原生小爱。说 `开启AI` 后进入 AI 模式，后续普通问题交给 AI；说 `开启小爱`、`关闭AI` 或 `原生小爱` 回到原生小爱。原生模式下也可以用 `问AI...` 做单次 AI 问答。

Ollama 也兼容这些口令：`切换欧拉拉`、`切换奥拉马`、`切换gemma`、`切换电脑`、`切换本地电脑`。

## 播报丢字

如果日志完整但音箱播报漏字，调 MiGPT 服务器的 `.env`：

```env
SPEAK_CHUNK_LEN=28
SPEAK_MS_PER_CHAR=220
SPEAK_CHUNK_GAP_MS=260
```

仍然漏字时，先把 `SPEAK_CHUNK_LEN` 调到 `20`，或把 `SPEAK_CHUNK_GAP_MS` 调到 `400`，然后重建服务器端 Docker。

## 文件位置

- 免刷机工作目录：`/opt/open-xiaoai-migpt`
- 免刷机配置：`/opt/open-xiaoai-migpt/config.ts`
- 免刷机环境变量：`/opt/open-xiaoai-migpt/.env`
- 刷机版工作目录：`/opt/xiaoai-openclaw`
- 刷机版配置：`/opt/xiaoai-openclaw/config.ts`
- 刷机版环境变量：`/opt/xiaoai-openclaw/.env`
- 管理命令：`xiaoai-openclaw`
- OpenClaw bridge：`/opt/openclaw-llm-bridge`

## 注意

Open-XiaoAI 上游仓库已在 2026-04-04 归档停止维护。本项目只做部署编排，不包含刷机流程。

首次拉取 `idootop/mi-gpt:latest` 或 `idootop/open-xiaoai-migpt:latest` 可能比较慢，软路由和 NAS 上尤其明显。

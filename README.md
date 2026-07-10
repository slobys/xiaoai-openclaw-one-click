# XiaoAI OpenClaw One-Click

小爱音箱接入 OpenClaw、DeepSeek、OpenAI、Gemini、Ollama 的一键脚本。

现在同时保留两条路线：

- 免刷机版：小米账号登录，不需要 SSH 音箱，不刷 Open-XiaoAI 固件。
- 刷机版：沿用已刷 Open-XiaoAI 固件的旧版体验。
- Raw Audio 实验版：音箱麦克风 PCM -> VAD/KWS -> 本地 ASR -> 大模型。

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

Raw Audio 实验版：
小爱音箱 Open-XiaoAI Client  ->  ws://软路由或NAS:4499  ->  open-xiaoai-bridge Docker  ->  DeepSeek / OpenAI / Gemini / Ollama / OpenClaw API Bridge
OpenWrt bridge 网络 DNS/NAT 异常时，也可切到 host 模式：ws://软路由:4399
```

免刷机版需要准备：

- 小米 ID、密码或浏览器 Cookie 里的 `passToken`
- 米家中的音箱名称或设备 DID
- 云模型至少配置一个 API Key，或局域网 OpenClaw/Ollama 地址

刷机版额外需要：

- 音箱已刷 Open-XiaoAI 补丁固件，并能 SSH 登录。
- 如果在 OpenWrt 上初始化音箱端遇到 `No matching algo hostkey`，脚本会自动尝试安装 `openssh-client`；OpenWrt 25.12+ 使用 `apk`，旧版使用 `opkg`。
- MiGPT 服务器开放 TCP `4399`。

Raw Audio 实验版额外需要：

- 音箱已刷 Open-XiaoAI 补丁固件，并能 SSH 登录。
- 如果在 OpenWrt 上初始化音箱端遇到 `No matching algo hostkey`，脚本会自动尝试安装 `openssh-client`；OpenWrt 25.12+ 使用 `apk`，旧版使用 `opkg`。
- 服务器开放 TCP `4499`，这是 Raw Audio 默认 WebSocket 端口，避免和刷机版 `4399` 冲突。
- 如果 OpenWrt Docker bridge 网络里无法解析外部 API，可在 Raw Audio `.env` 设置 `XIAOAI_DOCKER_NETWORK_MODE=host`。host 模式不走端口映射，WebSocket 会直接使用宿主机 `4399`，不能和普通刷机版服务同时占用。
- 首次部署会下载 VAD/KWS/ASR 模型包，体积较大，建议放在空间充足的设备上。

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

## Raw Audio 实验版

Raw Audio 版是第三条独立路线，不替换现有免刷机版和刷机版。它使用 Open-XiaoAI Client 采集音箱麦克风 PCM，在服务端做 VAD、KWS、自定义唤醒词、本地 ASR，再把文字交给 OpenAI-compatible 大模型。

```sh
# 只部署 Raw Audio 服务端
sh install-rawaudio.sh --server-only

# 只把音箱端 Client 指向 Raw Audio 服务端
sh install-rawaudio.sh --client-only --speaker-ip 192.168.31.227 --server-ip 192.168.31.10

# 服务端和音箱端一起部署
sh install-rawaudio.sh --all --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
```

Raw Audio 工作目录：

```text
/opt/xiaoai-rawaudio-bridge/.env
/opt/xiaoai-rawaudio-bridge/config.py
/opt/xiaoai-rawaudio-bridge/models
```

默认唤醒词是：

```env
RAWAUDIO_WAKE_KEYWORDS=你好小黑,小黑小黑
```

OpenWrt 上如果宿主机能解析 `api.deepseek.com`，但容器内不能解析：

```sh
nslookup api.deepseek.com
docker exec xiaoai-rawaudio-bridge getent hosts api.deepseek.com
```

可以把 Raw Audio 改成 host 网络：

```env
XIAOAI_DOCKER_NETWORK_MODE=host
```

然后用菜单 `20` 重建服务端，再用菜单 `18` 重新初始化音箱端 Client。host 模式下音箱会连接 `ws://软路由IP:4399`，HTTP API 默认仍是 `9093`。

默认模型来源是 DeepSeek。也可以在 `.env` 改成：

```env
RAWAUDIO_DEFAULT_PROVIDER=ollama
OLLAMA_BASE_URL=http://电脑IP:11434/v1
OLLAMA_MODEL=qwen3:4b
```

可选值：

```text
deepseek / openai / gemini / ollama / openclaw / custom
```

Raw Audio 会按当前 `RAWAUDIO_DEFAULT_PROVIDER` 和模型变量自动生成身份提示，避免问“你是什么模型”时误答成豆包或其他模型。需要完全自定义身份时再设置：

```env
XIAOAI_SYSTEM_PROMPT=你是运行在小爱音箱上的语音助手。回答要口语化、简短，不要 markdown。
```

Gemini 走 Google 官方 OpenAI-compatible 接口：

```env
RAWAUDIO_DEFAULT_PROVIDER=gemini
GEMINI_API_KEY=你的 Gemini Key
GEMINI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/
GEMINI_MODEL=gemini-3.5-flash
```

这条路线是完全接管音频输入的高级模式，适合测试自定义唤醒词和不用小米 ASR 的方案。只想“保留小爱同学唤醒和小米 ASR，只换大脑”时，优先研究 Native ASR Bridge。

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

AI 模式会启用 MiGPT 的连续对话保活，用静音/唤醒状态尽量压住原生小爱抢答；回到原生小爱模式后会退出保活。免刷机版默认把消息轮询和保活间隔调到 `500ms`，并内置静音 mp3 做保活；`开启AI`、`切换AI`、`AI模式` 都会进入保活并用短句确认切换成功。需要自定义静音音频时，可在 `.env` 里配置音箱可访问的 `XIAOAI_AUDIO_SILENT` URL。

如果确实不想听模式切换确认，可设置 `XIAOAI_DISABLE_MODE_CONFIRM=true`；默认建议保持开启，避免第一遍切换没有反馈。

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
- Raw Audio 工作目录：`/opt/xiaoai-rawaudio-bridge`
- Raw Audio 配置：`/opt/xiaoai-rawaudio-bridge/config.py`
- Raw Audio 环境变量：`/opt/xiaoai-rawaudio-bridge/.env`
- 管理命令：`xiaoai-openclaw`
- OpenClaw bridge：`/opt/openclaw-llm-bridge`

## 注意

Open-XiaoAI 上游仓库已在 2026-04-04 归档停止维护。本项目只做部署编排，不包含刷机流程。

首次拉取 `idootop/mi-gpt:latest` 或 `idootop/open-xiaoai-migpt:latest` 可能比较慢，软路由和 NAS 上尤其明显。

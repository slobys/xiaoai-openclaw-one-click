# XiaoAI OpenClaw One-Click

小爱音箱接入 DeepSeek / OpenAI / Gemini / OpenClaw / Ollama 的一键脚本。

现在包含两套入口：

- **免刷机版**：小米账号/passToken 登录，不需要 SSH 音箱，不需要刷 Open-XiaoAI 固件。
- **刷机版**：保留原 `v1.0.0` Open-XiaoAI 固件方案，需要音箱端 client。

## 一键菜单

OpenWrt / iStoreOS / root 用户优先用 Gitee：

```sh
opkg update
opkg install ca-bundle wget-ssl
wget -O /tmp/xiaoai-openclaw https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh
chmod +x /tmp/xiaoai-openclaw
XIAOAI_OPENCLAW_BASE_URL=https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main sh /tmp/xiaoai-openclaw
```

NAS / 普通 Linux：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

iStoreOS / OpenWrt / root 用户：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

国内网络优先用 Gitee：

```sh
curl -fsSL https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

完整项目方式：

```sh
git clone https://github.com/slobys/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sh bootstrap.sh
```

## 免刷机版

第一次运行菜单选：

```text
1) 配置账号并部署免刷机服务
```

它只填写基础信息：

- 小米 ID，不是手机号或邮箱
- 小米账号密码，或浏览器已登录小米账号后的 `passToken`
- 米家中的音箱名称或 DID
- 音箱型号代码，例如 `LX06`、`L05B`、`OH2P`
- 是否开启连续对话

模型配置仍按旧视频方式编辑：

```sh
vi /opt/open-xiaoai-migpt/config.ts
```

改完 `config.ts` 后回菜单选：

```text
3) 重建免刷机服务（修改 config.ts 后用）
```

免刷机版文件位置：

- 工作目录：`/opt/open-xiaoai-migpt`
- 主配置：`/opt/open-xiaoai-migpt/config.ts`
- 小米账号和基础运行参数：`/opt/open-xiaoai-migpt/migpt.env`
- 小米登录缓存：`/opt/open-xiaoai-migpt/.mi.json`

`config.ts` 顶部保留独立模型区块：

```ts
defaultProvider: "deepseek",

providers: {
  deepseek: {
    baseURL: "https://api.deepseek.com/v1",
    apiKey: "sk-...",
    model: "deepseek-chat",
  },
  openai: {
    baseURL: "https://api.openai.com/v1",
    apiKey: "sk-...",
    model: "gpt-4o-mini",
  },
  gemini: {
    apiKey: "...",
    model: "gemini-2.0-flash",
  },
  openclaw: {
    baseURL: "http://OpenClaw设备IP:11435/v1",
    apiKey: "xiaoai-local",
    model: "open",
  },
  ollama: {
    baseURL: "http://电脑IP:11434/v1",
    apiKey: "ollama",
    model: "qwen3:4b",
  },
},
```

如果小米账号触发异地登录验证，先停容器：

```sh
docker stop xiaoai-openclaw
```

在浏览器完成日志里的 `micoapi` 和 `xiaomiio` 验证，等待生效后再运行菜单 `3` 重建。也可以在菜单 `2` 填浏览器 Cookie 里的 `passToken`，密码留空。

## 直接部署

```sh
# 免刷机版：配置账号并部署
sh install-noflash.sh --install

# 免刷机版：只修改小米账号/音箱基础信息
sh install-noflash.sh --configure

# 免刷机版：重建容器
sh install-noflash.sh --restart

# 只部署 MiGPT 服务器端
sh install.sh --server-only

# 只初始化音箱端 client
sh install.sh --client-only --speaker-ip 192.168.31.227 --server-ip 192.168.31.10

# 服务器和音箱端一起部署
sh install.sh --all --speaker-ip 192.168.31.227 --server-ip 192.168.31.10

# 在 OpenClaw 设备上部署 API bridge
sh install-openclaw-bridge.sh
```

服务器端启动后会显示 `ws://...:4399`。这个地址必须是音箱能访问的局域网 IP。识别不准时手动指定：

```sh
SERVER_IP=192.168.2.1 xiaoai-openclaw
```

## 刷机版结构

```text
小爱音箱  ->  ws://软路由或NAS:4399  ->  open-xiaoai-migpt Docker
                                      ->  DeepSeek / OpenAI / Gemini / Ollama
                                      ->  OpenClaw API Bridge
```

刷机版需要准备：

- 音箱已刷 Open-XiaoAI 补丁固件，并能 SSH 登录
- MiGPT 服务器开放 TCP `4399`
- OpenClaw bridge 设备开放 TCP `11435`
- Ollama 电脑开放 TCP `11434`
- 云模型至少配置一个 API Key

刷机版配置文件在 `/opt/xiaoai-openclaw/.env`，改完后用菜单 `7) 重启/重建刷机版服务器端 Docker`。

默认保留最近 6 轮上下文，连续追问会接上前面的内容。需要关闭时改：

```env
CONVERSATION_TURNS=0
```

## OpenClaw

OpenClaw 不在 MiGPT 同一台设备时，在 OpenClaw 设备运行：

```sh
sh install-openclaw-bridge.sh
```

免刷机版在 `/opt/open-xiaoai-migpt/config.ts` 的 `openclaw` 区块设置：

```ts
openclaw: {
  baseURL: "http://OpenClaw设备IP:11435/v1",
  apiKey: "xiaoai-local",
  model: "open",
},
```

刷机版在 MiGPT 服务器的 `/opt/xiaoai-openclaw/.env` 设置：

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

免刷机版在 `/opt/open-xiaoai-migpt/config.ts` 的 `ollama` 区块设置：

```ts
ollama: {
  baseURL: "http://电脑IP:11434/v1",
  apiKey: "ollama",
  model: "qwen3:4b",
},
```

刷机版在 `/opt/xiaoai-openclaw/.env` 设置：

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

Ollama 也兼容这些口令：`切换欧拉拉`、`切换奥拉马`、`切换gemma`、`切换电脑`、`切换本地电脑`。

## 播报丢字

如果日志完整但音箱播报漏字，调 `/opt/xiaoai-openclaw/.env`：

```env
SPEAK_CHUNK_LEN=28
SPEAK_MS_PER_CHAR=220
SPEAK_CHUNK_GAP_MS=260
```

仍然漏字时，先把 `SPEAK_CHUNK_LEN` 调到 `20`，或把 `SPEAK_CHUNK_GAP_MS` 调到 `400`，然后重建服务器端 Docker。

## 文件位置

- 免刷机版工作目录：`/opt/open-xiaoai-migpt`
- 免刷机版主配置：`/opt/open-xiaoai-migpt/config.ts`
- 免刷机版基础配置：`/opt/open-xiaoai-migpt/migpt.env`
- 刷机版工作目录：`/opt/xiaoai-openclaw`
- 刷机版 MiGPT 配置：`/opt/xiaoai-openclaw/config.ts`
- 刷机版环境变量：`/opt/xiaoai-openclaw/.env`
- 管理命令：`xiaoai-openclaw`
- OpenClaw bridge：`/opt/openclaw-llm-bridge`

## 注意

Open-XiaoAI 上游仓库已在 2026-04-04 归档停止维护。本项目保留刷机版部署编排，同时新增免刷机版账号登录方案。

首次拉取 `idootop/open-xiaoai-migpt:latest` 可能比较慢，软路由和 NAS 上尤其明显。

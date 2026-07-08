# XiaoAI OpenClaw One-Click

免刷机把小爱音箱接入 OpenClaw 或其他 OpenAI 兼容大模型。

项目通过小米账号读取音箱对话记录并调用音箱 TTS，不需要刷固件、不需要音箱 SSH，也不限制音箱必须和服务器处于同一局域网。

## 一键安装

NAS / 普通 Linux：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

国内网络：

```sh
curl -fsSL https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

OpenWrt：

```sh
opkg update
opkg install ca-bundle wget-ssl
wget -O /tmp/xiaoai-openclaw https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh
chmod +x /tmp/xiaoai-openclaw
XIAOAI_OPENCLAW_BASE_URL=https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main sh /tmp/xiaoai-openclaw
```

完整项目方式：

```sh
git clone https://github.com/slobys/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sudo sh bootstrap.sh
```

菜单选择 `1`，按提示填写：

- 小米 ID：不是手机号或邮箱，可在小米账号个人信息中查看
- 小米账号密码，或已登录浏览器里的 `passToken` Cookie
- 米家中的音箱名称或 DID
- 音箱型号代码，例如 `LX06`、`L05B`、`OH2P`
- 是否开启连续对话

账号配置保存在 `/opt/xiaoai-openclaw/.env`，小米登录缓存保存在 `/opt/xiaoai-openclaw/.mi.json`，文件权限默认为仅 root 可读。

## 使用

默认语音命令：

```text
问AI今天天气怎么样
问小爱你是谁
打开AI
开启AI
开启小爱
关闭AI
```

`问AI`、`问小爱` 用于单次提问。部分小爱会把“问AI”识别成“揾AI”或“文AI”，脚本已内置这些误识别别名。`打开AI`、`开启AI`、`开启小爱` 用于进入连续对话。

如果连续对话没有接管，先用单次问答测试：

```text
问AI你是谁
```

部分音箱连续对话异常时，可在配置中设置：

```env
XIAOAI_STREAM_RESPONSE=false
```

修改后运行菜单 `3` 重建服务。

## 小米账号安全验证

首次在 OpenWrt、NAS 或新公网 IP 登录时，小米可能会提示异地登录安全验证。日志里通常会出现 `micoapi` 和 `xiaomiio` 两个验证链接。

如果不想在 OpenWrt 上直接用密码触发异地登录，可以在电脑浏览器登录小米账号后，从浏览器开发者工具的 Cookie 中复制 `passToken` 值。重新运行菜单选 `2`，小米账号密码可留空，把 `passToken` 填到“小米 passToken Cookie”。脚本会生成 MiGPT 的登录缓存并挂载到容器里。

处理步骤：

```sh
docker stop xiaoai-openclaw
```

在浏览器打开日志里的验证链接并完成授权。两个服务都提示时，两个链接都要完成。授权后通常需要等待一段时间才会生效；生效后重新运行菜单选 `3` 重建免刷机服务。

不要在验证未完成时反复重建服务，否则可能持续触发小米风控。

## 接入 OpenClaw

在安装了 OpenClaw 的设备运行菜单 `4` 部署 API bridge，然后把免刷机服务配置为：

```env
XIAOAI_DEFAULT_PROVIDER=openclaw
OPENCLAW_BASE_URL=http://OpenClaw设备IP:11435/v1
OPENCLAW_API_KEY=xiaoai-local
OPENCLAW_DISPLAY_MODEL=open
```

修改后运行菜单 `3` 重建服务。

## 多模型切换

免刷机版已移植旧刷机版的多模型入口。配置文件是 `/opt/xiaoai-openclaw/.env`，改完后运行菜单 `3` 重建服务。

菜单 `1` / `2` 只配置小米账号、passToken、音箱名称、型号和连续对话开关。模型不要在交互菜单里填，直接编辑 `.env` 更直观。

```sh
vi /opt/xiaoai-openclaw/.env
```

`.env` 里模型配置按来源分开填写，不要把 DeepSeek 填到 OpenClaw 段，也不要把 OpenClaw bridge 填到 OpenAI 段。

默认使用哪个模型：

```env
XIAOAI_DEFAULT_PROVIDER=deepseek
```

OpenClaw：

```env
OPENCLAW_BASE_URL=http://OpenClaw设备IP:11435/v1
OPENCLAW_API_KEY=xiaoai-local
OPENCLAW_DISPLAY_MODEL=open
```

OpenAI：

```env
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
```

DeepSeek：

```env
DEEPSEEK_BASE_URL=https://api.deepseek.com/v1
DEEPSEEK_API_KEY=sk-...
DEEPSEEK_MODEL=deepseek-chat
```

Gemini：

```env
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-2.0-flash
```

Ollama：

```env
OLLAMA_BASE_URL=http://电脑IP:11434/v1
OLLAMA_API_KEY=ollama
OLLAMA_MODEL=qwen3:4b
```

如果你的旧 `.env` 里字段混在一起，重新拉最新脚本后运行菜单 `2` 或 `3`，脚本会在保留现有值的前提下把 `.env` 整理成分区格式。

语音口令：

```text
切换open
切换ollama
切换deepseek
切换openai
切换gemini
当前模型
测试模型
清空上下文
```

## 兼容性

已内置常见型号指令：

```text
OH2P LX06 S12 L15A LX5A LX05 X10A L17A L06A LX01
L05B L05C L09A LX04 ASX4B X6A X08E
```

兼容性取决于小米云端是否返回该音箱的对话记录，以及机型是否支持对应 TTS 指令。个别型号可能只能单次问答，少数型号完全不支持。

## 能力边界

- 免刷机模式依赖小米云端接口，响应速度和打断效果不如刷机方案。
- 普通小爱命令会先由原生小爱处理，项目只能在云端记录出现后接管回答。
- 当前只支持小爱音箱。天猫精灵、小度、Alexa 等品牌没有通用账号接口，需要分别开发官方 Skill 或品牌适配器。
- 小米账号密码会保存在本机，请只部署在可信设备上。
- 上游 MiGPT 已于 2026 年 4 月归档，后续需要逐步把账号适配能力迁移到本项目维护。

## 文件位置

- 账号和模型配置：`/opt/xiaoai-openclaw/.env`
- MiGPT 配置：`/opt/xiaoai-openclaw/.migpt.js`
- OpenClaw bridge：`/opt/openclaw-llm-bridge`

本项目使用 [MiGPT](https://github.com/idootop/mi-gpt) 提供的免刷机小米云端能力。

## 版本切换

- `v2.0.0-account`：当前免刷机账号版
- `v1.0.0-flash`：原 Open-XiaoAI 刷机版

切换到免刷机版：

```sh
git switch main
```

切换到原刷机版：

```sh
git switch legacy-flash
```

标签用于固定历史版本，分支用于继续维护对应版本。

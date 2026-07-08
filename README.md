# XiaoAI OpenClaw One-Click

小爱音箱接入 DeepSeek / OpenAI / Gemini / OpenClaw / Ollama 的一键脚本。

这是原刷机版 `open-xiaoai-migpt` 方案的免刷机版：保留原来的 `config.ts`、多模型配置、语音切换和软路由部署思路，把“音箱刷补丁 + SSH client”替换成“小米账号 + MiGPT 云端免刷机登录”。

## 一键菜单

OpenWrt / iStoreOS / root 用户优先用 Gitee：

```sh
opkg update
opkg install ca-bundle wget-ssl
wget -O /tmp/xiaoai-openclaw https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh
chmod +x /tmp/xiaoai-openclaw
XIAOAI_OPENCLAW_BASE_URL=https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main sh /tmp/xiaoai-openclaw
```

普通 Linux / NAS：

```sh
curl -fsSL https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

国内网络：

```sh
curl -fsSL https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh -o /tmp/xiaoai-openclaw && chmod +x /tmp/xiaoai-openclaw && sudo /tmp/xiaoai-openclaw
```

完整项目方式：

```sh
git clone https://github.com/slobys/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sh bootstrap.sh
```

## 菜单怎么用

第一次运行选：

```text
1) 配置账号并部署免刷机服务
```

它只负责基础信息：

- 小米 ID，不是手机号或邮箱
- 小米账号密码，或浏览器已登录小米账号后的 `passToken`
- 米家中的音箱名称或 DID
- 音箱型号代码，例如 `LX06`、`L05B`、`OH2P`
- 是否开启连续对话

后续修改基础信息选：

```text
2) 修改小米账号/音箱基础配置
```

这个菜单不会再问 DeepSeek、OpenAI、Gemini、OpenClaw、Ollama 的 Key。模型配置按旧教程直接编辑：

```sh
vi /opt/open-xiaoai-migpt/config.ts
```

改完后选：

```text
3) 重建免刷机服务
```

## 文件位置

- 工作目录：`/opt/open-xiaoai-migpt`
- 模型配置：`/opt/open-xiaoai-migpt/config.ts`
- 账号和免刷机基础配置：`/opt/open-xiaoai-migpt/migpt.env`
- MiGPT 兼容入口：`/opt/open-xiaoai-migpt/.migpt.js`，指向 `config.ts`
- 小米登录缓存：`/opt/open-xiaoai-migpt/.mi.json`
- OpenClaw bridge：`/opt/openclaw-llm-bridge`

历史新版目录 `/opt/xiaoai-openclaw/.env` 会在首次运行时自动迁移到 `/opt/open-xiaoai-migpt/migpt.env`。

## 模型配置

打开 `/opt/open-xiaoai-migpt/config.ts`，在文件顶部的 `CONFIG.providers` 里填写。

默认模型：

```ts
defaultProvider: "deepseek",
```

DeepSeek：

```ts
deepseek: {
  baseURL: "https://api.deepseek.com/v1",
  apiKey: "sk-...",
  model: "deepseek-chat",
},
```

OpenAI：

```ts
openai: {
  baseURL: "https://api.openai.com/v1",
  apiKey: "sk-...",
  model: "gpt-4o-mini",
},
```

Gemini：

```ts
gemini: {
  apiKey: "...",
  model: "gemini-2.0-flash",
},
```

OpenClaw：

```ts
openclaw: {
  baseURL: "http://OpenClaw设备IP:11435/v1",
  apiKey: "xiaoai-local",
  model: "open",
},
```

Ollama：

```ts
ollama: {
  baseURL: "http://电脑IP:11434/v1",
  apiKey: "ollama",
  model: "qwen3:4b",
},
```

## OpenClaw Bridge

在安装了 OpenClaw 的设备运行菜单：

```text
4) 部署 OpenClaw API Bridge（在 OpenClaw 设备运行）
```

然后在软路由/NAS 的 `/opt/open-xiaoai-migpt/config.ts` 填：

```ts
openclaw: {
  baseURL: "http://OpenClaw设备IP:11435/v1",
  apiKey: "xiaoai-local",
  model: "open",
},
```

健康检查：

```sh
curl http://OpenClaw设备IP:11435/health
```

## 语音命令

先唤醒小爱同学，再说：

```text
开启小爱
开启AI
切换deepseek
切换openai
切换谷歌
切换open
切换ollama
当前模型
测试模型
清空上下文
关闭AI
```

也支持单次问答：

```text
问AI你是谁
问小爱你是谁
```

部分小爱会把“问AI”识别成“揾AI”或“文AI”，脚本已内置这些别名。

## 小米账号安全验证

首次在 OpenWrt、NAS 或新公网 IP 登录，小米可能触发异地登录验证。日志里通常会出现 `micoapi` 和 `xiaomiio` 两个验证链接。

如果不想在 OpenWrt 上直接用密码触发验证，可以在电脑浏览器登录小米账号后，从浏览器 Cookie 里复制 `passToken`。重新运行菜单选 `2`，密码可以留空，把 `passToken` 填进去。

遇到验证时先停容器：

```sh
docker stop xiaoai-openclaw
```

完成网页授权后等待一段时间，再运行菜单 `3` 重建。验证没完成前不要反复重建，否则可能持续触发风控。

## 能力边界

- 免刷机版依赖小米云端接口，不需要音箱刷机，也不需要 SSH 到音箱。
- 免刷机版的响应速度、打断效果通常不如刷机版。
- 普通小爱命令会先由原生小爱处理，项目在云端记录出现后接管回答。
- 账号、Key 和登录缓存只保存在本机，请部署在可信设备上。

## 版本

- `main`：免刷机版，继承旧刷机版的多模型配置和语音命令。
- `legacy-flash` / `v1.0.0-flash`：原 Open-XiaoAI 刷机版。

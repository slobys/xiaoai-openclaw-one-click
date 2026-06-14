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

完整项目方式：

```sh
git clone https://github.com/slobys/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sudo sh bootstrap.sh
```

菜单选择 `1`，按提示填写：

- 小米 ID：不是手机号或邮箱，可在小米账号个人信息中查看
- 小米账号密码
- 米家中的音箱名称或 DID
- 音箱型号代码，例如 `LX06`、`L05B`、`OH2P`
- OpenClaw bridge 或其他 OpenAI 兼容模型接口

账号配置保存在 `/opt/xiaoai-openclaw/.env`，文件权限默认为仅 root 可读。

## 使用

默认语音命令：

```text
问AI今天天气怎么样
打开AI
关闭AI
```

`问AI` 用于单次提问。部分音箱支持说 `打开AI` 后连续对话；需要在配置中设置：

```env
XIAOAI_STREAM_RESPONSE=true
```

如果连续对话异常，请保持 `false`。

## 接入 OpenClaw

在安装了 OpenClaw 的设备运行菜单 `4` 部署 API bridge，然后把免刷机服务配置为：

```env
OPENAI_BASE_URL=http://OpenClaw设备IP:11435/v1
OPENAI_API_KEY=xiaoai-local
OPENAI_MODEL=open
```

修改后运行菜单 `3` 重建服务。

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

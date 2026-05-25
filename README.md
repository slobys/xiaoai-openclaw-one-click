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
- 大模型端：默认使用 `slobys/xiaoai` 的 `config.ts`，支持 DeepSeek、OpenAI、Gemini，也支持 OpenAI-compatible 地址
- OpenClaw：如果 OpenClaw 和 MiGPT 服务器不在同一台设备，在 OpenClaw 设备上运行本项目的 `openclaw-llm-bridge`，让 MiGPT 服务器通过 HTTP 调用它

典型三设备拓扑：

```text
小爱音箱  ->  ws://软路由或NAS:4399  ->  open-xiaoai-migpt Docker
                                      ->  http://OpenClaw设备IP:11435/v1
                                      ->  openclaw infer model run
```

## 前置条件

1. 音箱已经按 Open-XiaoAI 教程刷好补丁固件，并能 SSH 登录。
2. 服务器/NAS 能被音箱局域网访问，开放 TCP `4399`。
3. 如果直连模型，至少准备一个模型 API Key：DeepSeek / OpenAI / Gemini。
4. 如果接入 OpenClaw，OpenClaw 所在设备要能被 MiGPT 服务器局域网访问，开放 TCP `11435`。

## OpenClaw 不同设备部署

如果你的 OpenClaw 在电脑 / 独立服务器上，而小爱项目跑在软路由或 NAS 上，按这个方式做：

1. 在 OpenClaw 所在设备运行：

```sh
cd xiaoai-openclaw-one-click
OPENCLAW_MODEL=openai/gpt-5.4 sh install-openclaw-bridge.sh
```

2. 在 MiGPT 服务器的 `/opt/xiaoai-openclaw/.env` 里设置：

```sh
OPENCLAW_BASE_URL=http://OpenClaw设备IP:11435/v1
OPENCLAW_API_KEY=任意字符串
OPENCLAW_MODEL=openclaw
```

`OPENAI_BASE_URL` / `OPENAI_API_KEY` 仍然保留给真正的 OpenAI 使用。OpenClaw 使用单独的 `openclaw` 供应商，不占用 OpenAI 位置。

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
切换openclaw
测试模型
```

`openclaw-llm-bridge` 同时兼容 `/v1/responses` 和 `/v1/chat/completions`。`slobys/xiaoai` 的 OpenAI 分支默认会调用 `/responses`，所以这里重点支持了 Responses 格式。

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
- `切换openclaw`
- `切换deepseek`
- `切换openai`
- `切换谷歌`
- `测试模型`
- `停止` / `闭嘴`

## 已知边界

Open-XiaoAI 上游仓库已在 2026-04-04 归档停止维护，但 Docker 镜像和 client artifact 仍可用。这个一键项目会尽量只做部署编排，不改刷机流程。

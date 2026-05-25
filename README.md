# XiaoAI OpenClaw One-Click

小爱音箱 Pro / Xiaomi 智能音箱 Pro 接入 Open-XiaoAI、OpenClaw 和大模型的一键部署脚本。

> 适用机型：小爱音箱 Pro（LX06）和 Xiaomi 智能音箱 Pro（OH2P）。其他型号不要直接刷 Open-XiaoAI 固件。

## 一键菜单

海外 / GitHub：

```sh
curl -fsSL https://raw.githubusercontent.com/naiyou88/xiaoai-openclaw-one-click/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

国内 / Gitee：

```sh
curl -fsSL https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/bootstrap.sh -o /usr/bin/xiaoai-openclaw && chmod +x /usr/bin/xiaoai-openclaw && xiaoai-openclaw
```

完整项目方式：

```sh
git clone https://github.com/naiyou88/xiaoai-openclaw-one-click.git
cd xiaoai-openclaw-one-click
sh bootstrap.sh
```

## 直接命令

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
- OpenClaw：推荐第一版通过 OpenClaw 外部可调用的 OpenAI-compatible 网关接入；如果要直接调用本机 `openclaw infer model run`，后续走宿主机 Node 模式，不建议放 Docker 里

## 前置条件

1. 音箱已经按 Open-XiaoAI 教程刷好补丁固件，并能 SSH 登录。
2. 服务器/NAS 能被音箱局域网访问，开放 TCP `4399`。
3. 至少准备一个模型 API Key：DeepSeek / OpenAI / Gemini。

## 安装后文件

- 工作目录：`/opt/xiaoai-openclaw`
- 配置文件：`/opt/xiaoai-openclaw/config.ts`
- 环境变量：`/opt/xiaoai-openclaw/.env`
- 管理命令：`xiaoai-openclaw`

## 常用语音命令

- `开启AI`
- `开启小爱`
- `切换deepseek`
- `切换openai`
- `切换谷歌`
- `测试模型`
- `停止` / `闭嘴`

## 已知边界

Open-XiaoAI 上游仓库已在 2026-04-04 归档停止维护，但 Docker 镜像和 client artifact 仍可用。这个一键项目会尽量只做部署编排，不改刷机流程。


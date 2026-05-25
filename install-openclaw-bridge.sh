#!/bin/sh
set -eu

APP_NAME="openclaw-llm-bridge"
WORK_DIR="/opt/${APP_NAME}"
PORT="${OPENCLAW_BRIDGE_PORT:-11435}"
HOST="${OPENCLAW_BRIDGE_HOST:-0.0.0.0}"
MODEL="${OPENCLAW_MODEL:-openai/gpt-5.4}"
TOKEN="${OPENCLAW_BRIDGE_TOKEN:-}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 运行，或用 sudo sh install-openclaw-bridge.sh ..." >&2
    exit 1
  fi
}

fetch() {
  url="$1"
  out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  else
    wget -qO "$out" "$url"
  fi
}

detect_source_file() {
  script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  if [ -f "$script_dir/bridge/openclaw-llm-bridge.js" ]; then
    echo "$script_dir/bridge/openclaw-llm-bridge.js"
    return 0
  fi
  echo ""
}

install_node_if_needed() {
  command -v node >/dev/null 2>&1 && return 0
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y nodejs
  elif command -v opkg >/dev/null 2>&1; then
    opkg update
    opkg install node
  else
    echo "缺少 node，请先手动安装 Node.js" >&2
    exit 1
  fi
}

install_bridge() {
  need_root
  command -v openclaw >/dev/null 2>&1 || {
    echo "当前设备找不到 openclaw 命令。这个脚本必须运行在 OpenClaw 所在设备上。" >&2
    exit 1
  }
  install_node_if_needed
  mkdir -p "$WORK_DIR"
  src=$(detect_source_file)
  if [ -n "$src" ]; then
    cp "$src" "$WORK_DIR/openclaw-llm-bridge.js"
  else
    base="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
    fetch "$base/bridge/openclaw-llm-bridge.js" "$WORK_DIR/openclaw-llm-bridge.js"
  fi
  chmod +x "$WORK_DIR/openclaw-llm-bridge.js"

  cat > "$WORK_DIR/env" <<EOF
OPENCLAW_BRIDGE_HOST=${HOST}
OPENCLAW_BRIDGE_PORT=${PORT}
OPENCLAW_MODEL=${MODEL}
OPENCLAW_BRIDGE_TOKEN=${TOKEN}
OPENCLAW_TIMEOUT_MS=${OPENCLAW_TIMEOUT_MS:-60000}
EOF
  chmod 600 "$WORK_DIR/env"

  if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/${APP_NAME}.service <<EOF
[Unit]
Description=OpenClaw OpenAI-compatible LLM Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${WORK_DIR}/env
ExecStart=$(command -v node) ${WORK_DIR}/openclaw-llm-bridge.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "${APP_NAME}"
  else
    nohup node "$WORK_DIR/openclaw-llm-bridge.js" >> "$WORK_DIR/bridge.log" 2>&1 &
  fi

  ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
  [ -n "$ip_addr" ] || ip_addr="OpenClaw设备IP"
  echo "OpenClaw bridge 已启动: http://${ip_addr}:${PORT}/v1"
  echo "MiGPT 服务器 .env 里设置：OPENAI_BASE_URL=http://${ip_addr}:${PORT}/v1"
  if [ -n "$TOKEN" ]; then
    echo "MiGPT 服务器 .env 里设置：OPENAI_API_KEY=${TOKEN}"
  else
    echo "未设置 OPENCLAW_BRIDGE_TOKEN，局域网内可直接调用；仅建议内网使用。"
  fi
}

case "${1:-install}" in
  install) install_bridge ;;
  status) systemctl status "$APP_NAME" 2>/dev/null || ps | grep openclaw-llm-bridge | grep -v grep || true ;;
  logs) journalctl -u "$APP_NAME" -f 2>/dev/null || tail -f "$WORK_DIR/bridge.log" ;;
  uninstall)
    need_root
    systemctl disable --now "$APP_NAME" 2>/dev/null || true
    rm -f /etc/systemd/system/${APP_NAME}.service
    rm -rf "$WORK_DIR"
    ;;
  *) echo "用法: sh install-openclaw-bridge.sh [install|status|logs|uninstall]" ;;
esac

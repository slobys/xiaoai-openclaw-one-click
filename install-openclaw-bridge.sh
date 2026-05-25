#!/bin/sh
set -eu

APP_NAME="openclaw-llm-bridge"
WORK_DIR="/opt/${APP_NAME}"
PORT="${OPENCLAW_BRIDGE_PORT:-11435}"
HOST="${OPENCLAW_BRIDGE_HOST:-0.0.0.0}"
MODEL="${OPENCLAW_MODEL:-}"
TOKEN="${OPENCLAW_BRIDGE_TOKEN:-}"
BRIDGE_MODE="${OPENCLAW_BRIDGE_MODE:-agent}"
AGENT="${OPENCLAW_AGENT:-main}"
SESSION_KEY="${OPENCLAW_SESSION_KEY:-agent:${AGENT}:xiaoai}"
THINKING="${OPENCLAW_THINKING:-}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 运行，或用 sudo sh install-openclaw-bridge.sh ..." >&2
    exit 1
  fi
}

run_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}

run_home() {
  user="$1"
  if [ "$user" = "$(id -un)" ]; then
    printf '%s\n' "${HOME:-}"
    return 0
  fi
  awk -F: -v u="$user" '$1 == u { print $6; exit }' /etc/passwd
}

detect_openclaw_bin() {
  user="$1"
  home="$2"
  if [ -n "${OPENCLAW_BIN:-}" ] && [ -x "$OPENCLAW_BIN" ]; then
    echo "$OPENCLAW_BIN"
    return 0
  fi
  for candidate in \
    "$(command -v openclaw 2>/dev/null || true)" \
    "$home/.npm-global/bin/openclaw" \
    "$home/.local/bin/openclaw" \
    "/usr/local/bin/openclaw" \
    "/usr/bin/openclaw"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  if command -v su >/dev/null 2>&1; then
    candidate=$(su - "$user" -c 'command -v openclaw 2>/dev/null || true' 2>/dev/null || true)
    if [ -n "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  fi
  return 1
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

cache_bust_url() {
  case "$1" in
    *\?*) printf '%s&ts=%s\n' "$1" "$(date +%s)" ;;
    *) printf '%s?ts=%s\n' "$1" "$(date +%s)" ;;
  esac
}

detect_lan_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show scope global 2>/dev/null | awk '
      $2 ~ /^(docker|br-|veth|tailscale|tun|wg)/ { next }
      {
        split($4, a, "/")
        ip = a[1]
        if (ip ~ /^10\./ || ip ~ /^192\.168\./ || ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {
          print ip
          exit
        }
      }
    '
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

stop_existing_bridge() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$APP_NAME" 2>/dev/null || true
  fi

  if command -v pgrep >/dev/null 2>&1; then
    pids=$(pgrep -f "${WORK_DIR}/openclaw-llm-bridge.js" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      echo "发现旧 OpenClaw bridge 进程，正在停止..."
      kill $pids 2>/dev/null || true
      sleep 1
      pids=$(pgrep -f "${WORK_DIR}/openclaw-llm-bridge.js" 2>/dev/null || true)
      [ -z "$pids" ] || kill -9 $pids 2>/dev/null || true
    fi
  fi
}

install_bridge() {
  need_root
  stop_existing_bridge
  service_user=$(run_user)
  service_home=$(run_home "$service_user")
  openclaw_bin=$(detect_openclaw_bin "$service_user" "$service_home") || {
    echo "当前设备找不到 openclaw 命令。" >&2
    echo "请确认 OpenClaw 已安装，并且普通用户能执行：command -v openclaw" >&2
    echo "如果命令在特殊路径，可这样安装：OPENCLAW_BIN=/完整路径/openclaw sudo -E /tmp/xiaoai-openclaw" >&2
    exit 1
  }
  install_node_if_needed
  mkdir -p "$WORK_DIR"
  src=$(detect_source_file)
  if [ -n "$src" ]; then
    cp "$src" "$WORK_DIR/openclaw-llm-bridge.js"
  else
    base="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
    fetch "$(cache_bust_url "$base/bridge/openclaw-llm-bridge.js")" "$WORK_DIR/openclaw-llm-bridge.js"
  fi
  chmod +x "$WORK_DIR/openclaw-llm-bridge.js"

  cat > "$WORK_DIR/env" <<EOF
OPENCLAW_BRIDGE_HOST=${HOST}
OPENCLAW_BRIDGE_PORT=${PORT}
OPENCLAW_MODEL=${MODEL}
OPENCLAW_BRIDGE_MODE=${BRIDGE_MODE}
OPENCLAW_AGENT=${AGENT}
OPENCLAW_SESSION_KEY=${SESSION_KEY}
OPENCLAW_THINKING=${THINKING}
OPENCLAW_BRIDGE_TOKEN=${TOKEN}
OPENCLAW_TIMEOUT_MS=${OPENCLAW_TIMEOUT_MS:-60000}
OPENCLAW_BIN=${openclaw_bin}
HOME=${service_home}
EOF
  chown -R "$service_user" "$WORK_DIR"
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
User=${service_user}
WorkingDirectory=${service_home}
ExecStart=$(command -v node) ${WORK_DIR}/openclaw-llm-bridge.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${APP_NAME}"
    systemctl restart "${APP_NAME}"
  else
    if [ "$service_user" = "$(id -un)" ]; then
      nohup node "$WORK_DIR/openclaw-llm-bridge.js" >> "$WORK_DIR/bridge.log" 2>&1 &
    else
      su - "$service_user" -c "OPENCLAW_BIN='$openclaw_bin' OPENCLAW_MODEL='$MODEL' OPENCLAW_BRIDGE_MODE='$BRIDGE_MODE' OPENCLAW_AGENT='$AGENT' OPENCLAW_SESSION_KEY='$SESSION_KEY' OPENCLAW_THINKING='$THINKING' OPENCLAW_BRIDGE_HOST='$HOST' OPENCLAW_BRIDGE_PORT='$PORT' OPENCLAW_TIMEOUT_MS='${OPENCLAW_TIMEOUT_MS:-60000}' nohup node '$WORK_DIR/openclaw-llm-bridge.js' >> '$WORK_DIR/bridge.log' 2>&1 &"
    fi
  fi

  ip_addr=$(detect_lan_ip || true)
  [ -n "$ip_addr" ] || ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
  [ -n "$ip_addr" ] || ip_addr="OpenClaw设备IP"
  echo "OpenClaw bridge 已启动: http://${ip_addr}:${PORT}/v1"
  echo "运行用户: ${service_user}"
  echo "OpenClaw 命令: ${openclaw_bin}"
  echo "OpenClaw 模式: ${BRIDGE_MODE}, 会话: ${SESSION_KEY}"
  echo "MiGPT 服务器 .env 里设置：OPENCLAW_BASE_URL=http://${ip_addr}:${PORT}/v1"
  if [ -n "$TOKEN" ]; then
    echo "MiGPT 服务器 .env 里设置：OPENCLAW_API_KEY=${TOKEN}"
  else
    echo "未设置 OPENCLAW_BRIDGE_TOKEN，局域网内可直接调用；仅建议内网使用。"
  fi
}

restart_bridge() {
  need_root
  if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/${APP_NAME}.service" ]; then
    systemctl restart "$APP_NAME"
    echo "OpenClaw bridge 已重启。"
    return 0
  fi

  stop_existing_bridge
  if [ ! -f "$WORK_DIR/env" ] || [ ! -f "$WORK_DIR/openclaw-llm-bridge.js" ]; then
    echo "OpenClaw bridge 未安装，正在执行安装..."
    install_bridge
    return 0
  fi

  set -a
  . "$WORK_DIR/env"
  set +a
  nohup node "$WORK_DIR/openclaw-llm-bridge.js" >> "$WORK_DIR/bridge.log" 2>&1 &
  echo "OpenClaw bridge 已重启。"
}

uninstall_bridge() {
  need_root
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "$APP_NAME" 2>/dev/null || true
  fi
  stop_existing_bridge
  rm -f /etc/systemd/system/${APP_NAME}.service
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
  echo "OpenClaw bridge 已清理。OpenClaw 主程序未改动。"
}

case "${1:-install}" in
  install) install_bridge ;;
  restart) restart_bridge ;;
  status) systemctl status "$APP_NAME" 2>/dev/null || ps | grep openclaw-llm-bridge | grep -v grep || true ;;
  logs) journalctl -u "$APP_NAME" -f 2>/dev/null || tail -f "$WORK_DIR/bridge.log" ;;
  uninstall|clean) uninstall_bridge ;;
  *) echo "用法: sh install-openclaw-bridge.sh [install|restart|status|logs|uninstall|clean]" ;;
esac

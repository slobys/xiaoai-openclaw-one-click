#!/bin/sh
set -eu

APP_NAME="xiaoai-openclaw"
WORK_DIR="/opt/${APP_NAME}"
CONTAINER_NAME="${APP_NAME}"
PORT="${XIAOAI_OPENCLAW_PORT:-4399}"
CONFIG_URL="${XIAOAI_CONFIG_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/config-openclaw.ts}"
CONFIG_CN_URL="${XIAOAI_CONFIG_CN_URL:-https://gh-proxy.com/https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/config-openclaw.ts}"
CLIENT_INIT_URL="${XIAOAI_CLIENT_INIT_URL:-https://gitee.com/idootop/artifacts/releases/download/open-xiaoai-client/init.sh}"
CLIENT_BOOT_URL="${XIAOAI_CLIENT_BOOT_URL:-https://gitee.com/idootop/artifacts/releases/download/open-xiaoai-client/boot.sh}"

MODE=""
SPEAKER_IP="${SPEAKER_IP:-}"
SERVER_IP="${SERVER_IP:-}"

log() { printf '%s\n' "$*"; }
die() { log "错误: $*" >&2; exit 1; }

usage() {
  cat <<EOF
用法:
  sh install.sh --server-only
  sh install.sh --client-only --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
  sh install.sh --all --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
  sh install.sh --status
  sh install.sh --logs
  sh install.sh --uninstall
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --server-only) MODE="server" ;;
    --client-only) MODE="client" ;;
    --all) MODE="all" ;;
    --status) MODE="status" ;;
    --logs) MODE="logs" ;;
    --uninstall) MODE="uninstall" ;;
    --speaker-ip) shift; SPEAKER_IP="${1:-}" ;;
    --server-ip) shift; SERVER_IP="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

[ -n "$MODE" ] || MODE="server"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行，或用 sudo sh install.sh ..."
  fi
}

fetch() {
  url="$1"
  out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    die "缺少 curl/wget"
  fi
}

fetch_with_fallback() {
  primary="$1"
  fallback="$2"
  out="$3"
  if fetch "$primary" "$out"; then
    return 0
  fi
  log "主下载失败，尝试备用地址..."
  fetch "$fallback" "$out"
}

detect_server_ip() {
  if [ -n "$SERVER_IP" ]; then
    return 0
  fi
  SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
  if [ -z "$SERVER_IP" ]; then
    printf "请输入服务器局域网 IP: "
    read -r SERVER_IP
  fi
  [ -n "$SERVER_IP" ] || die "服务器 IP 不能为空"
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi
  log "正在安装 Docker..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://get.docker.com | sh
  elif command -v yum >/dev/null 2>&1; then
    yum install -y yum-utils curl
    curl -fsSL https://get.docker.com | sh
  else
    die "未识别的系统，请先手动安装 Docker"
  fi
  systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
}

write_env_if_missing() {
  env_file="$WORK_DIR/.env"
  if [ -f "$env_file" ]; then
    append_env_if_missing "$env_file" "OPENCLAW_BASE_URL" "${OPENCLAW_BASE_URL:-}"
    append_env_if_missing "$env_file" "OPENCLAW_API_KEY" "${OPENCLAW_API_KEY:-xiaoai-local}"
    append_env_if_missing "$env_file" "OPENCLAW_MODEL" "${OPENCLAW_MODEL:-open}"
    if ! grep -q '^# 如果 OpenClaw 在另一台设备，OPENCLAW_BASE_URL 设置为:' "$env_file"; then
      printf '%s\n' '# 如果 OpenClaw 在另一台设备，OPENCLAW_BASE_URL 设置为: http://OpenClaw设备IP:11435/v1' >> "$env_file"
    fi
    return 0
  fi
  log "创建环境变量文件: $env_file"
  umask 077
  {
    printf 'DEEPSEEK_API_KEY=%s\n' "${DEEPSEEK_API_KEY:-}"
    printf 'OPENAI_API_KEY=%s\n' "${OPENAI_API_KEY:-}"
    printf 'GEMINI_API_KEY=%s\n' "${GEMINI_API_KEY:-}"
    printf 'OPENAI_BASE_URL=%s\n' "${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    printf 'OPENCLAW_BASE_URL=%s\n' "${OPENCLAW_BASE_URL:-}"
    printf 'OPENCLAW_API_KEY=%s\n' "${OPENCLAW_API_KEY:-xiaoai-local}"
    printf 'OPENCLAW_MODEL=%s\n' "${OPENCLAW_MODEL:-open}"
    printf '# 如果 OpenClaw 在另一台设备，OPENCLAW_BASE_URL 设置为: http://OpenClaw设备IP:11435/v1\n'
  } > "$env_file"
  log "如果没有通过环境变量传入 Key，请编辑 $env_file 后重新运行服务器端部署以重建容器。"
  log "如果要接入远端 OpenClaw，请把 OPENCLAW_BASE_URL 改成 http://OpenClaw设备IP:11435/v1，并说“切换open”。"
}

append_env_if_missing() {
  env_file="$1"
  key="$2"
  value="$3"
  if grep -q "^${key}=" "$env_file"; then
    return 0
  fi
  printf '%s=%s\n' "$key" "$value" >> "$env_file"
  log "已补充 ${key} 到 $env_file"
}

install_server() {
  need_root
  mkdir -p "$WORK_DIR"
  install_docker_if_needed
  fetch_with_fallback "$CONFIG_URL" "$CONFIG_CN_URL" "$WORK_DIR/config.ts"
  write_env_if_missing

  log "拉取并启动 Docker 容器..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${PORT}:4399" \
    --env-file "$WORK_DIR/.env" \
    -v "$WORK_DIR/config.ts:/app/config.ts:ro" \
    idootop/open-xiaoai-migpt:latest >/dev/null

  detect_server_ip
  log "服务器端已启动: ws://${SERVER_IP}:${PORT}"
  log "配置目录: $WORK_DIR"
}

ask_client_inputs() {
  if [ -z "$SPEAKER_IP" ]; then
    printf "请输入小爱音箱 IP: "
    read -r SPEAKER_IP
  fi
  detect_server_ip
  [ -n "$SPEAKER_IP" ] || die "小爱音箱 IP 不能为空"
}

install_client() {
  ask_client_inputs
  command -v ssh >/dev/null 2>&1 || die "本机缺少 ssh"
  ws_url="ws://${SERVER_IP}:${PORT}"
  log "正在配置音箱端 Client: root@${SPEAKER_IP} -> ${ws_url}"
  ssh -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=accept-new "root@${SPEAKER_IP}" "
    set -e
    mkdir -p /data/open-xiaoai
    echo '${ws_url}' > /data/open-xiaoai/server.txt
    if command -v curl >/dev/null 2>&1; then
      curl -L -o /data/init.sh '${CLIENT_BOOT_URL}'
      curl -sSfL '${CLIENT_INIT_URL}' | sh
    else
      wget -O /data/init.sh '${CLIENT_BOOT_URL}'
      wget -qO- '${CLIENT_INIT_URL}' | sh
    fi
    chmod +x /data/init.sh
  "
  log "音箱端已配置。重启音箱后会自启动；当前也已尝试启动 Client。"
}

show_status() {
  if command -v docker >/dev/null 2>&1; then
    docker ps -a --filter "name=${CONTAINER_NAME}"
  else
    log "Docker 未安装"
  fi
  [ -f "$WORK_DIR/.env" ] && log "环境变量文件: $WORK_DIR/.env"
  [ -f "$WORK_DIR/config.ts" ] && log "配置文件: $WORK_DIR/config.ts"
}

show_logs() {
  command -v docker >/dev/null 2>&1 || die "Docker 未安装"
  docker logs -f --tail=120 "$CONTAINER_NAME"
}

uninstall_server() {
  need_root
  if command -v docker >/dev/null 2>&1; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  log "容器已删除。配置目录保留在 $WORK_DIR，如需删除请手动处理。"
}

case "$MODE" in
  server) install_server ;;
  client) install_client ;;
  all) install_server; install_client ;;
  status) show_status ;;
  logs) show_logs ;;
  uninstall) uninstall_server ;;
  *) usage; exit 1 ;;
esac

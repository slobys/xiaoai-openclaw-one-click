#!/bin/sh
set -eu

APP_NAME="xiaoai-rawaudio-bridge"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_DIR="/opt/${APP_NAME}"
CONTAINER_NAME="${APP_NAME}"
PORT="${XIAOAI_RAWAUDIO_PORT:-4499}"
API_PORT="${XIAOAI_RAWAUDIO_API_PORT:-9093}"
IMAGE="${XIAOAI_RAWAUDIO_IMAGE:-ghcr.io/coderzc/open-xiaoai-bridge:latest}"
CONFIG_URL="${XIAOAI_RAWAUDIO_CONFIG_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/config-rawaudio.py}"
CONFIG_CN_URL="${XIAOAI_RAWAUDIO_CONFIG_CN_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/templates/config-rawaudio.py}"
CONFIG_PROXY_URL="${XIAOAI_RAWAUDIO_CONFIG_PROXY_URL:-https://gh-proxy.com/https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/config-rawaudio.py}"
ENV_URL="${XIAOAI_RAWAUDIO_ENV_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/env-rawaudio.example}"
ENV_CN_URL="${XIAOAI_RAWAUDIO_ENV_CN_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/templates/env-rawaudio.example}"
ENV_PROXY_URL="${XIAOAI_RAWAUDIO_ENV_PROXY_URL:-https://gh-proxy.com/https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/env-rawaudio.example}"
MODELS_URL="${XIAOAI_RAWAUDIO_MODELS_URL:-https://github.com/coderzc/open-xiaoai-bridge/releases/download/vad-kws-asr-models/models.zip}"
CLIENT_INIT_URL="${XIAOAI_CLIENT_INIT_URL:-https://gitee.com/idootop/artifacts/releases/download/open-xiaoai-client/init.sh}"
CLIENT_BOOT_URL="${XIAOAI_CLIENT_BOOT_URL:-https://gitee.com/idootop/artifacts/releases/download/open-xiaoai-client/boot.sh}"

MODE=""
SPEAKER_IP="${SPEAKER_IP:-}"
SERVER_IP="${SERVER_IP:-}"
SKIP_MODELS="${XIAOAI_RAWAUDIO_SKIP_MODELS:-false}"
DOCKER_DNS_ARGS=""

log() { printf '%s\n' "$*"; }
die() { log "错误: $*" >&2; exit 1; }

usage() {
  cat <<EOF
用法:
  sh install-rawaudio.sh --server-only
  sh install-rawaudio.sh --client-only --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
  sh install-rawaudio.sh --all --speaker-ip 192.168.31.227 --server-ip 192.168.31.10
  sh install-rawaudio.sh --restart
  sh install-rawaudio.sh --status
  sh install-rawaudio.sh --logs
  sh install-rawaudio.sh --uninstall

说明:
  Raw Audio 实验版使用独立目录 ${WORK_DIR} 和独立容器 ${CONTAINER_NAME}。
  默认 WebSocket 端口为 ${PORT}，避免和现有刷机版 4399 冲突。
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --server-only) MODE="server" ;;
    --client-only) MODE="client" ;;
    --all) MODE="all" ;;
    --restart|--recreate) MODE="restart" ;;
    --status) MODE="status" ;;
    --logs) MODE="logs" ;;
    --uninstall) MODE="uninstall" ;;
    --skip-models) SKIP_MODELS="true" ;;
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
    die "请使用 root 运行，或用 sudo sh install-rawaudio.sh ..."
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

fetch_with_fallback_chain() {
  out="$1"
  shift
  first=1
  for url in "$@"; do
    if fetch "$url" "$out"; then
      return 0
    fi
    if [ "$first" -eq 1 ]; then
      log "主下载失败，尝试备用地址..."
      first=0
    else
      log "备用地址失败，继续尝试下一地址..."
    fi
  done
  return 1
}

cache_bust_url() {
  case "$1" in
    *\?*) printf '%s&ts=%s\n' "$1" "$(date +%s)" ;;
    *) printf '%s?ts=%s\n' "$1" "$(date +%s)" ;;
  esac
}

detect_lan_ip() {
  if command -v ip >/dev/null 2>&1; then
    detected_ip=$(ip -o -4 addr show dev br-lan scope global 2>/dev/null | awk '
      {
        split($4, a, "/")
        ip = a[1]
        if (ip ~ /^10\./ || ip ~ /^192\.168\./ || ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {
          print ip
          exit
        }
      }
    ')
    if [ -n "$detected_ip" ]; then
      printf '%s\n' "$detected_ip"
      return 0
    fi
    ip -o -4 addr show scope global 2>/dev/null | awk '
      $2 ~ /^(docker|docker0|veth|tailscale|tun|wg|zt|ppp)/ { next }
      $2 ~ /^br-/ && $2 != "br-lan" { next }
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

detect_server_ip() {
  if [ -n "$SERVER_IP" ]; then
    return 0
  fi
  SERVER_IP=$(detect_lan_ip || true)
  if [ -z "$SERVER_IP" ]; then
    printf "未能自动识别局域网 IP，请输入服务器局域网 IP（音箱能访问的地址）: "
    read -r SERVER_IP
  fi
  [ -n "$SERVER_IP" ] || die "服务器 IP 不能为空"
}

run_speaker_ssh() {
  target="$1"
  shift
  ssh_version=$(ssh -V 2>&1 || true)
  if printf '%s\n' "$ssh_version" | grep -qi 'OpenSSH'; then
    ssh \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o PubkeyAcceptedAlgorithms=+ssh-rsa \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$target" "$@"
  else
    ssh "$target" "$@"
  fi
}

explain_speaker_ssh_failure() {
  cat <<EOF
音箱 SSH 初始化失败。

如果你在 Windows/macOS 上可以用下面命令登录音箱：
  ssh -o HostKeyAlgorithms=+ssh-rsa root@${SPEAKER_IP}

但在 OpenWrt 上失败并出现 "No matching algo hostkey"，说明 OpenWrt 自带的精简 SSH
客户端不支持 LX06/OH2P 固件使用的旧 ssh-rsa hostkey 算法。

处理方式：
  1) 在 OpenWrt 上安装完整版 OpenSSH 客户端后重试菜单 18：
     opkg update
     opkg install openssh-client

  2) 或者在 Windows/macOS 已登录音箱的 SSH 窗口中手动执行：
     mkdir -p /data/open-xiaoai
     echo 'ws://${SERVER_IP}:${PORT}' > /data/open-xiaoai/server.txt
     wget -O /data/init.sh '${CLIENT_BOOT_URL}'
     chmod +x /data/init.sh
     wget -O /tmp/open-xiaoai-init.sh '${CLIENT_INIT_URL}'
     sh /tmp/open-xiaoai-init.sh
EOF
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

build_docker_dns_args() {
  DOCKER_DNS_ARGS=""
  dns_list="${XIAOAI_DOCKER_DNS:-}"
  [ -z "$dns_list" ] && [ -f "$WORK_DIR/.env" ] && dns_list=$(awk -F= '$1=="XIAOAI_DOCKER_DNS" { print $2; exit }' "$WORK_DIR/.env")
  [ -z "$dns_list" ] && return 0
  old_ifs="$IFS"
  IFS=", "
  for dns in $dns_list; do
    [ -n "$dns" ] || continue
    DOCKER_DNS_ARGS="${DOCKER_DNS_ARGS} --dns ${dns}"
  done
  IFS="$old_ifs"
}

ensure_config() {
  mkdir -p "$WORK_DIR"
  if [ ! -f "$WORK_DIR/config.py" ]; then
    log "下载 Raw Audio 配置模板: $WORK_DIR/config.py"
    if [ -f "$SCRIPT_DIR/templates/config-rawaudio.py" ]; then
      cp "$SCRIPT_DIR/templates/config-rawaudio.py" "$WORK_DIR/config.py"
    else
      fetch_with_fallback_chain "$WORK_DIR/config.py" \
        "$(cache_bust_url "$CONFIG_URL")" \
        "$(cache_bust_url "$CONFIG_CN_URL")" \
        "$(cache_bust_url "$CONFIG_PROXY_URL")" || die "下载 config-rawaudio.py 失败"
    fi
  fi
  if [ ! -f "$WORK_DIR/.env" ]; then
    log "创建环境变量文件: $WORK_DIR/.env"
    umask 077
    if [ -f "$SCRIPT_DIR/templates/env-rawaudio.example" ]; then
      cp "$SCRIPT_DIR/templates/env-rawaudio.example" "$WORK_DIR/.env"
    else
      fetch_with_fallback_chain "$WORK_DIR/.env" \
        "$(cache_bust_url "$ENV_URL")" \
        "$(cache_bust_url "$ENV_CN_URL")" \
        "$(cache_bust_url "$ENV_PROXY_URL")" || die "下载 env-rawaudio.example 失败"
    fi
    log "请按需编辑 $WORK_DIR/.env 后重启；默认使用 DeepSeek。"
  fi
}

ensure_models() {
  [ "$SKIP_MODELS" = "true" ] && return 0
  mkdir -p "$WORK_DIR/models"
  if [ -f "$WORK_DIR/models/silero_vad.onnx" ] && [ -f "$WORK_DIR/models/encoder.onnx" ] && [ -f "$WORK_DIR/models/tokens.txt" ]; then
    return 0
  fi
  command -v unzip >/dev/null 2>&1 || die "缺少 unzip，无法解压 Raw Audio 模型包"
  tmp_zip="$WORK_DIR/models/models.zip"
  log "下载 VAD/KWS/ASR 模型包，文件较大，可能需要几分钟..."
  fetch "$MODELS_URL" "$tmp_zip" || die "模型下载失败，可手动下载后解压到 $WORK_DIR/models，或临时使用 --skip-models"
  unzip -o "$tmp_zip" -d "$WORK_DIR/models" >/dev/null
  rm -f "$tmp_zip"
  if [ -d "$WORK_DIR/models/models" ]; then
    find "$WORK_DIR/models/models" -mindepth 1 -maxdepth 1 -exec mv {} "$WORK_DIR/models/" \;
    rmdir "$WORK_DIR/models/models" 2>/dev/null || true
  fi
}

start_server() {
  need_root
  install_docker_if_needed
  ensure_config
  ensure_models
  build_docker_dns_args

  log "启动 Raw Audio 实验版容器..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${PORT}:4399" \
    -p "${API_PORT}:9092" \
    $DOCKER_DNS_ARGS \
    --env-file "$WORK_DIR/.env" \
    -e OPENAI_ENABLE=1 \
    -e API_SERVER_ENABLE=1 \
    -e API_SERVER_HOST=0.0.0.0 \
    -e AUDIO_INPUT_ENABLE=true \
    -e CONFIG_PATH=/app/config.py \
    -v "$WORK_DIR/config.py:/app/config.py:ro" \
    -v "$WORK_DIR/models:/app/core/models" \
    -v "$WORK_DIR/openclaw:/app/openclaw" \
    "$IMAGE" >/dev/null

  detect_server_ip
  log "Raw Audio 服务端已启动: ws://${SERVER_IP}:${PORT}"
  log "HTTP API: http://${SERVER_IP}:${API_PORT}"
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
  if ! run_speaker_ssh "root@${SPEAKER_IP}" "
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
  "; then
    explain_speaker_ssh_failure
    die "音箱端 Client 初始化失败"
  fi
  log "音箱端 Client 已指向 Raw Audio 服务端。"
}

show_status() {
  if command -v docker >/dev/null 2>&1; then
    docker ps -a --filter "name=${CONTAINER_NAME}"
  else
    log "Docker 未安装"
  fi
  [ -f "$WORK_DIR/.env" ] && log "环境变量文件: $WORK_DIR/.env"
  [ -f "$WORK_DIR/config.py" ] && log "配置文件: $WORK_DIR/config.py"
  [ -d "$WORK_DIR/models" ] && log "模型目录: $WORK_DIR/models"
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
  log "容器已删除。配置和模型保留在 $WORK_DIR。"
}

case "$MODE" in
  server) start_server ;;
  client) install_client ;;
  all) start_server; install_client ;;
  restart) start_server ;;
  status) show_status ;;
  logs) show_logs ;;
  uninstall) uninstall_server ;;
  *) usage; exit 1 ;;
esac

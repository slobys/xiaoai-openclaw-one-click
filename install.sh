#!/bin/sh
set -eu

APP_NAME="xiaoai-openclaw"
WORK_DIR="${XIAOAI_OPENCLAW_WORK_DIR:-/opt/${APP_NAME}}"
CONTAINER_NAME="${APP_NAME}"
IMAGE="${MIGPT_IMAGE:-idootop/mi-gpt:latest}"
BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
CN_BASE_URL="${XIAOAI_OPENCLAW_CN_BASE_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main}"
MODE="${1:---install}"

log() { printf '%s\n' "$*"; }
die() { log "错误: $*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] && return 0
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  die "当前用户无 Docker 权限，请使用 root 或 sudo sh install.sh"
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

fetch_template() {
  path="$1"
  out="$2"
  script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  if [ -f "$script_dir/$path" ]; then
    cp "$script_dir/$path" "$out"
  elif ! fetch "$BASE_URL/$path?ts=$(date +%s)" "$out"; then
    fetch "$CN_BASE_URL/$path?ts=$(date +%s)" "$out"
  fi
}

start_docker_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker 2>/dev/null || true
  fi
  if [ -x /etc/init.d/dockerd ]; then
    /etc/init.d/dockerd enable 2>/dev/null || true
    /etc/init.d/dockerd restart 2>/dev/null || /etc/init.d/dockerd start 2>/dev/null || true
  fi
  if [ -x /etc/init.d/docker ]; then
    /etc/init.d/docker enable 2>/dev/null || true
    /etc/init.d/docker restart 2>/dev/null || /etc/init.d/docker start 2>/dev/null || true
  fi
  service docker start 2>/dev/null || true
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 && return 0
    start_docker_service
    docker info >/dev/null 2>&1 && return 0
  fi

  log "正在安装 Docker..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl
    curl -fsSL https://get.docker.com | sh
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
    curl -fsSL https://get.docker.com | sh
  elif command -v opkg >/dev/null 2>&1; then
    opkg update
    opkg install ca-bundle wget-ssl dockerd docker
  else
    die "未识别的系统，请先手动安装 Docker"
  fi

  start_docker_service
  docker info >/dev/null 2>&1 || die "Docker 未正常运行，请检查 dockerd 服务和 OpenWrt 存储空间"
}

env_value() {
  key="$1"
  [ -f "$WORK_DIR/.env" ] || return 0
  sed -n "s/^${key}=//p" "$WORK_DIR/.env" | tail -n 1
}

set_env() {
  key="$1"
  value="$2"
  tmp="$WORK_DIR/.env.tmp.$$"
  found=0
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*)
        if [ "$found" -eq 0 ]; then
          printf '%s=%s\n' "$key" "$value" >> "$tmp"
          found=1
        fi
        ;;
      *) printf '%s\n' "$line" >> "$tmp" ;;
    esac
  done < "$WORK_DIR/.env"
  [ "$found" -eq 1 ] || printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$WORK_DIR/.env"
  chmod 600 "$WORK_DIR/.env"
}

ask() {
  key="$1"
  prompt="$2"
  default=$(env_value "$key")
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default" >&2
  else
    printf "%s: " "$prompt" >&2
  fi
  read -r value
  [ -n "$value" ] || value="$default"
  set_env "$key" "$value"
}

ask_secret() {
  key="$1"
  prompt="$2"
  current=$(env_value "$key")
  if [ -n "$current" ]; then
    printf "%s [直接回车保持不变]: " "$prompt" >&2
  else
    printf "%s: " "$prompt" >&2
  fi
  if command -v stty >/dev/null 2>&1; then
    stty -echo 2>/dev/null || true
    read -r value
    stty echo 2>/dev/null || true
    printf '\n' >&2
  else
    read -r value
  fi
  [ -n "$value" ] || value="$current"
  set_env "$key" "$value"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

cookie_value() {
  name="$1"
  raw="$2"
  printf '%s' "$raw" | tr ';' '\n' | sed 's/^[[:space:]]*//' | sed -n "s/^${name}=//p" | tail -n 1
}

prepare_mi_cache() {
  pass_token=$(env_value "MI_PASS_TOKEN")
  [ -n "$pass_token" ] || return 0

  case "$pass_token" in
    *passToken=*) pass_token=$(cookie_value "passToken" "$pass_token") ;;
  esac
  [ -n "$pass_token" ] || die "MI_PASS_TOKEN 未解析到 passToken"

  user_id=$(env_value "MI_USER")
  did=$(env_value "MI_DID")
  password=$(env_value "MI_PASS")
  [ -n "$password" ] || password="__cookie_login__"
  device_id=$(env_value "MI_DEVICE_ID")
  [ -n "$device_id" ] || device_id="android_$(date +%s)$$"

  user_id_json=$(json_escape "$user_id")
  did_json=$(json_escape "$did")
  password_json=$(json_escape "$password")
  device_id_json=$(json_escape "$device_id")
  pass_token_json=$(json_escape "$pass_token")

  umask 077
  cat > "$WORK_DIR/.mi.json" <<EOF
{
  "mina": {
    "sid": "micoapi",
    "deviceId": "$device_id_json",
    "userId": "$user_id_json",
    "password": "$password_json",
    "did": "$did_json",
    "pass": {
      "passToken": "$pass_token_json"
    }
  },
  "miiot": {
    "sid": "xiaomiio",
    "deviceId": "$device_id_json",
    "userId": "$user_id_json",
    "password": "$password_json",
    "did": "$did_json",
    "pass": {
      "passToken": "$pass_token_json"
    }
  }
}
EOF
  chmod 600 "$WORK_DIR/.mi.json"
}

prepare_files() {
  mkdir -p "$WORK_DIR"
  if [ ! -f "$WORK_DIR/.env" ]; then
    fetch_template "templates/env.example" "$WORK_DIR/.env"
    chmod 600 "$WORK_DIR/.env"
  fi
  fetch_template "templates/migpt-account.js" "$WORK_DIR/.migpt.js"
  [ -s "$WORK_DIR/.mi.json" ] || printf '{}\n' > "$WORK_DIR/.mi.json"
  chmod 600 "$WORK_DIR/.mi.json"
}

configure() {
  prepare_files
  log "填写小米账号和音箱信息。小米 ID 不是手机号或邮箱。"
  ask "MI_USER" "小米 ID"
  ask_secret "MI_PASS" "小米账号密码（使用 passToken Cookie 时可留空）"
  ask_secret "MI_PASS_TOKEN" "小米 passToken Cookie（可选，建议从已登录浏览器复制）"
  ask "MI_DID" "米家中的音箱名称或 DID"
  ask "XIAOAI_HARDWARE" "音箱型号代码（例如 LX06、L05B、OH2P）"
  ask "XIAOAI_STREAM_RESPONSE" "是否开启连续对话（true/false）"
  log "配置已保存到 $WORK_DIR/.env"
  log "模型配置请直接编辑 $WORK_DIR/.env，然后运行菜单 3 重建服务。"
  log "已有服务时，请运行重建服务使新配置生效。"
}

validate_config() {
  for key in MI_USER MI_DID; do
    [ -n "$(env_value "$key")" ] || die "$key 未配置，请先运行配置账号"
  done
  [ -n "$(env_value "MI_PASS")" ] || [ -n "$(env_value "MI_PASS_TOKEN")" ] || die "MI_PASS 和 MI_PASS_TOKEN 至少配置一个"
}

start_container() {
  need_root
  prepare_files
  validate_config
  prepare_mi_cache
  install_docker_if_needed
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart on-failure:5 \
    --network host \
    --env-file "$WORK_DIR/.env" \
    -v "$WORK_DIR/.migpt.js:/app/.migpt.js:ro" \
    -v "$WORK_DIR/.mi.json:/app/.mi.json" \
    "$IMAGE" >/dev/null
  log "免刷机小爱服务已启动。首次登录可能需要稍等片刻。"
  log "如果日志提示小米账号安全验证，请先完成网页授权，等待生效后再运行重建服务。"
  log "查看日志: docker logs -f $CONTAINER_NAME"
}

case "$MODE" in
  --install) configure; start_container ;;
  --configure) configure ;;
  --restart) start_container ;;
  --status) docker ps -a --filter "name=${CONTAINER_NAME}" ;;
  --logs) docker logs -f --tail=120 "$CONTAINER_NAME" ;;
  --uninstall)
    need_root
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    log "容器已删除，账号配置仍保留在 $WORK_DIR"
    ;;
  -h|--help)
    echo "用法: sh install.sh [--install|--configure|--restart|--status|--logs|--uninstall]"
    ;;
  *) die "未知参数: $MODE" ;;
esac

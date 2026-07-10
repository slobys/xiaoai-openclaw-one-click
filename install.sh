#!/bin/sh
set -eu

APP_NAME="xiaoai-openclaw"
WORK_DIR="/opt/${APP_NAME}"
CONTAINER_NAME="${APP_NAME}"
PORT="${XIAOAI_OPENCLAW_PORT:-4399}"
CONFIG_URL="${XIAOAI_CONFIG_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/config-openclaw.ts}"
CONFIG_CN_URL="${XIAOAI_CONFIG_CN_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/templates/config-openclaw.ts}"
CONFIG_PROXY_URL="${XIAOAI_CONFIG_PROXY_URL:-https://gh-proxy.com/https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main/templates/config-openclaw.ts}"
CLIENT_INIT_URL="${XIAOAI_CLIENT_INIT_URL:-https://gitee.com/idootop/artifacts/releases/download/open-xiaoai-client/init.sh}"
CLIENT_BOOT_URL="${XIAOAI_CLIENT_BOOT_URL:-https://gitee.com/idootop/artifacts/releases/download/open-xiaoai-client/boot.sh}"

MODE=""
SPEAKER_IP="${SPEAKER_IP:-}"
SERVER_IP="${SERVER_IP:-}"
DOCKER_DNS_ARGS=""
DOCKER_NETWORK_ARGS=""
DOCKER_PORT_ARGS=""
SPEAKER_SSH_BIN="${XIAOAI_SSH_BIN:-}"

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
  sh install.sh --restart
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
    --restart|--recreate) MODE="restart" ;;
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
  die "下载失败: $out"
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

get_ssh_bin() {
  candidate="$1"
  if [ -n "$candidate" ]; then
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    command -v "$candidate" 2>/dev/null && return 0
    return 1
  fi
  command -v ssh 2>/dev/null
}

ssh_bin_is_openssh() {
  candidate=$(get_ssh_bin "$1" 2>/dev/null || true)
  [ -n "$candidate" ] || return 1
  ssh_version=$("$candidate" -V 2>&1 || true)
  printf '%s\n' "$ssh_version" | grep -qi 'OpenSSH'
}

find_openssh_client() {
  for candidate in "${XIAOAI_SSH_BIN:-}" ssh /usr/bin/ssh /usr/sbin/ssh /usr/bin/ssh.openssh /usr/sbin/ssh.openssh /opt/bin/ssh; do
    [ -n "$candidate" ] || continue
    if ssh_bin_is_openssh "$candidate"; then
      get_ssh_bin "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_speaker_ssh_client() {
  command -v ssh >/dev/null 2>&1 || die "本机缺少 ssh"
  if SPEAKER_SSH_BIN=$(find_openssh_client 2>/dev/null); then
    return 0
  fi
  if command -v opkg >/dev/null 2>&1; then
    log "检测到 OpenWrt 精简 SSH，正在安装完整版 OpenSSH 客户端以兼容 LX06/OH2P 的 ssh-rsa..."
    opkg update || die "opkg update 失败，请检查 OpenWrt 软件源和网络"
    opkg install openssh-client || die "安装 openssh-client 失败，请确认软件源可用且剩余空间足够"
    hash -r 2>/dev/null || true
  fi
  if SPEAKER_SSH_BIN=$(find_openssh_client 2>/dev/null); then
    return 0
  fi
  if [ -z "$SPEAKER_SSH_BIN" ]; then
    SPEAKER_SSH_BIN=$(get_ssh_bin ssh 2>/dev/null || true)
  fi
  if ! ssh_bin_is_openssh "$SPEAKER_SSH_BIN"; then
    log "警告: 当前 ssh 仍不是 OpenSSH，若后续出现 No matching algo hostkey，请先安装 openssh-client。"
  fi
}

run_speaker_ssh() {
  target="$1"
  shift
  ssh_bin="${SPEAKER_SSH_BIN:-$(get_ssh_bin ssh)}"
  if ssh_bin_is_openssh "$ssh_bin"; then
    "$ssh_bin" \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o PubkeyAcceptedAlgorithms=+ssh-rsa \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$target" "$@"
  else
    "$ssh_bin" "$target" "$@"
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
  1) 脚本会在 OpenWrt 上自动尝试安装完整版 OpenSSH 客户端；如果自动安装失败，请手动执行后重试音箱端初始化：
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

build_docker_network_args() {
  network_mode="${XIAOAI_DOCKER_NETWORK_MODE:-}"
  [ -z "$network_mode" ] && [ -f "$WORK_DIR/.env" ] && network_mode=$(awk -F= '$1=="XIAOAI_DOCKER_NETWORK_MODE" { print $2; exit }' "$WORK_DIR/.env")
  [ -z "$network_mode" ] && network_mode="bridge"
  DOCKER_NETWORK_ARGS=""
  DOCKER_PORT_ARGS="-p ${PORT}:4399"
  case "$network_mode" in
    host)
      DOCKER_NETWORK_ARGS="--network host"
      DOCKER_PORT_ARGS=""
      DOCKER_DNS_ARGS=""
      ;;
    bridge|"")
      ;;
    *)
      die "XIAOAI_DOCKER_NETWORK_MODE 只支持 bridge 或 host"
      ;;
  esac
}

write_env_if_missing() {
  env_file="$WORK_DIR/.env"
  if [ -f "$env_file" ]; then
    append_env_if_missing "$env_file" "DEEPSEEK_MODEL" "${DEEPSEEK_MODEL:-deepseek-v4-flash}"
    append_env_if_missing "$env_file" "DEEPSEEK_BASE_URL" "${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
    append_env_if_missing "$env_file" "XIAOAI_DOCKER_DNS" "${XIAOAI_DOCKER_DNS:-}"
    append_env_if_missing "$env_file" "XIAOAI_DOCKER_NETWORK_MODE" "${XIAOAI_DOCKER_NETWORK_MODE:-bridge}"
    append_env_if_missing "$env_file" "OPENCLAW_BASE_URL" "${OPENCLAW_BASE_URL:-http://192.168.2.238:11435/v1}"
    append_env_if_missing "$env_file" "OPENCLAW_API_KEY" "${OPENCLAW_API_KEY:-xiaoai-local}"
    append_env_if_missing "$env_file" "OPENCLAW_DISPLAY_MODEL" "${OPENCLAW_DISPLAY_MODEL:-open}"
    append_env_if_missing "$env_file" "OPENCLAW_TIMEOUT_MS" "${OPENCLAW_TIMEOUT_MS:-90000}"
    append_env_if_missing "$env_file" "OPENCLAW_TEST_TIMEOUT_MS" "${OPENCLAW_TEST_TIMEOUT_MS:-30000}"
    append_env_if_missing "$env_file" "SPEAK_CHUNK_LEN" "${SPEAK_CHUNK_LEN:-28}"
    append_env_if_missing "$env_file" "SPEAK_MS_PER_CHAR" "${SPEAK_MS_PER_CHAR:-220}"
    append_env_if_missing "$env_file" "SPEAK_CHUNK_GAP_MS" "${SPEAK_CHUNK_GAP_MS:-260}"
    append_env_if_missing "$env_file" "CONVERSATION_TURNS" "${CONVERSATION_TURNS:-6}"
    append_env_if_missing "$env_file" "OLLAMA_BASE_URL" "${OLLAMA_BASE_URL:-http://192.168.2.193:11434/v1}"
    append_env_if_missing "$env_file" "OLLAMA_MODEL" "${OLLAMA_MODEL:-qwen3:4b}"
    remove_env_key "$env_file" "PREFIX_GATE_MODE"
    remove_env_key "$env_file" "OLLAMA_TIMEOUT_MS"
    remove_env_key "$env_file" "OLLAMA_NUM_PREDICT"
    remove_env_key "$env_file" "OLLAMA_KEEP_ALIVE"
    update_env_if_provided "$env_file" "DEEPSEEK_MODEL" "${DEEPSEEK_MODEL:-}"
    update_env_if_provided "$env_file" "DEEPSEEK_BASE_URL" "${DEEPSEEK_BASE_URL:-}"
    update_env_if_provided "$env_file" "XIAOAI_DOCKER_DNS" "${XIAOAI_DOCKER_DNS:-}"
    update_env_if_provided "$env_file" "XIAOAI_DOCKER_NETWORK_MODE" "${XIAOAI_DOCKER_NETWORK_MODE:-}"
    update_env_if_provided "$env_file" "OPENCLAW_BASE_URL" "${OPENCLAW_BASE_URL:-}"
    update_env_if_provided "$env_file" "OPENCLAW_API_KEY" "${OPENCLAW_API_KEY:-}"
    update_env_if_provided "$env_file" "OPENCLAW_DISPLAY_MODEL" "${OPENCLAW_DISPLAY_MODEL:-}"
    update_env_if_provided "$env_file" "OPENCLAW_TIMEOUT_MS" "${OPENCLAW_TIMEOUT_MS:-}"
    update_env_if_provided "$env_file" "OPENCLAW_TEST_TIMEOUT_MS" "${OPENCLAW_TEST_TIMEOUT_MS:-}"
    update_env_if_provided "$env_file" "SPEAK_CHUNK_LEN" "${SPEAK_CHUNK_LEN:-}"
    update_env_if_provided "$env_file" "SPEAK_MS_PER_CHAR" "${SPEAK_MS_PER_CHAR:-}"
    update_env_if_provided "$env_file" "SPEAK_CHUNK_GAP_MS" "${SPEAK_CHUNK_GAP_MS:-}"
    update_env_if_provided "$env_file" "CONVERSATION_TURNS" "${CONVERSATION_TURNS:-}"
    update_env_if_provided "$env_file" "OLLAMA_BASE_URL" "${OLLAMA_BASE_URL:-}"
    update_env_if_provided "$env_file" "OLLAMA_MODEL" "${OLLAMA_MODEL:-}"
    update_env_if_blank_or_value "$env_file" "OPENCLAW_BASE_URL" "http://192.168.2.238:11435/v1" ""
    update_env_if_blank_or_value "$env_file" "OLLAMA_BASE_URL" "http://192.168.2.193:11434/v1" ""
    update_env_if_blank_or_value "$env_file" "OLLAMA_MODEL" "qwen3:4b" ""
    update_env_if_blank_or_value "$env_file" "OLLAMA_MODEL" "qwen3:4b" "gemma3:latest"
    update_env_if_blank_or_value "$env_file" "DEEPSEEK_MODEL" "deepseek-v4-flash" ""
    update_env_if_blank_or_value "$env_file" "DEEPSEEK_MODEL" "deepseek-v4-flash" "deepseek-chat"
    update_env_if_blank_or_value "$env_file" "DEEPSEEK_BASE_URL" "https://api.deepseek.com" ""
    update_env_if_blank_or_value "$env_file" "DEEPSEEK_BASE_URL" "https://api.deepseek.com" "https://api.deepseek.com/v1"
    annotate_env_file "$env_file"
    return 0
  fi
  log "创建环境变量文件: $env_file"
  umask 077
  {
    printf '# DEEPSEEK_API_KEY：DeepSeek 官方 API Key；说“切换 deepseek”后使用。\n'
    printf 'DEEPSEEK_API_KEY=%s\n' "${DEEPSEEK_API_KEY:-}"
    printf '# DEEPSEEK_MODEL：DeepSeek 模型名；默认使用 deepseek-v4-flash。\n'
    printf 'DEEPSEEK_MODEL=%s\n' "${DEEPSEEK_MODEL:-deepseek-v4-flash}"
    printf '# DEEPSEEK_BASE_URL：DeepSeek OpenAI 兼容接口地址；官方默认不带 /v1。\n'
    printf 'DEEPSEEK_BASE_URL=%s\n' "${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
    printf '# XIAOAI_DOCKER_DNS：可选，容器 DNS；OpenWrt 出现 EAI_AGAIN 时可填 223.5.5.5,119.29.29.29。\n'
    printf 'XIAOAI_DOCKER_DNS=%s\n' "${XIAOAI_DOCKER_DNS:-}"
    printf '# XIAOAI_DOCKER_NETWORK_MODE：容器网络模式；OpenWrt 代理/分流不接管 bridge 容器时可改 host。\n'
    printf 'XIAOAI_DOCKER_NETWORK_MODE=%s\n' "${XIAOAI_DOCKER_NETWORK_MODE:-bridge}"
    printf '# OPENAI_API_KEY：OpenAI 官方或兼容接口 API Key；说“切换 openai”后使用。\n'
    printf 'OPENAI_API_KEY=%s\n' "${OPENAI_API_KEY:-}"
    printf '# GEMINI_API_KEY：Gemini API Key；说“切换 gemini”后使用。\n'
    printf 'GEMINI_API_KEY=%s\n' "${GEMINI_API_KEY:-}"
    printf '# OPENAI_BASE_URL：OpenAI 接口地址；兼容服务可改成自己的 /v1 地址。\n'
    printf 'OPENAI_BASE_URL=%s\n' "${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    printf '# CONVERSATION_TURNS：连续对话保留轮数；0 表示不保留上下文。\n'
    printf 'CONVERSATION_TURNS=%s\n' "${CONVERSATION_TURNS:-6}"
    printf '\n'
    printf '# OPENCLAW_BASE_URL：OpenClaw API Bridge 地址；OpenClaw 在另一台设备时改成 http://OpenClaw设备IP:11435/v1。\n'
    printf 'OPENCLAW_BASE_URL=%s\n' "${OPENCLAW_BASE_URL:-http://192.168.2.238:11435/v1}"
    printf '# OPENCLAW_API_KEY：OpenClaw API Bridge 鉴权 Key；需和部署 Bridge 时的 OPENCLAW_BRIDGE_TOKEN 一致，默认本地测试可用 xiaoai-local。\n'
    printf 'OPENCLAW_API_KEY=%s\n' "${OPENCLAW_API_KEY:-xiaoai-local}"
    printf '# OPENCLAW_DISPLAY_MODEL：语音里显示/切换用的模型名；默认说“切换 open”即可使用 OpenClaw。\n'
    printf 'OPENCLAW_DISPLAY_MODEL=%s\n' "${OPENCLAW_DISPLAY_MODEL:-open}"
    printf '# OPENCLAW_TIMEOUT_MS：OpenClaw 正常问答超时时间，单位毫秒；OpenClaw 响应慢时可适当调大。\n'
    printf 'OPENCLAW_TIMEOUT_MS=%s\n' "${OPENCLAW_TIMEOUT_MS:-90000}"
    printf '# OPENCLAW_TEST_TIMEOUT_MS：“测试模型”命令的超时时间，单位毫秒；一般保持 30000 即可。\n'
    printf 'OPENCLAW_TEST_TIMEOUT_MS=%s\n' "${OPENCLAW_TEST_TIMEOUT_MS:-30000}"
    printf '\n'
    printf '# SPEAK_CHUNK_LEN：每段最多字符数；越小越不容易漏字，但回答会被切成更多段。\n'
    printf 'SPEAK_CHUNK_LEN=%s\n' "${SPEAK_CHUNK_LEN:-28}"
    printf '# SPEAK_MS_PER_CHAR：每个字预估播报耗时，单位毫秒；音箱抢播/漏字时可调大。\n'
    printf 'SPEAK_MS_PER_CHAR=%s\n' "${SPEAK_MS_PER_CHAR:-220}"
    printf '# SPEAK_CHUNK_GAP_MS：每段播报之间的额外间隔，单位毫秒；仍漏字时可从 260 调到 400。\n'
    printf 'SPEAK_CHUNK_GAP_MS=%s\n' "${SPEAK_CHUNK_GAP_MS:-260}"
    printf '# OLLAMA_BASE_URL：Ollama OpenAI 兼容地址；Ollama 在局域网电脑时改成 http://电脑IP:11434/v1。\n'
    printf 'OLLAMA_BASE_URL=%s\n' "${OLLAMA_BASE_URL:-http://192.168.2.193:11434/v1}"
    printf '# OLLAMA_MODEL：Ollama 模型名；必须和 ollama list 里的模型名一致，说“切换 ollama”后使用。\n'
    printf 'OLLAMA_MODEL=%s\n' "${OLLAMA_MODEL:-qwen3:4b}"
  } > "$env_file"
  log "如果没有通过环境变量传入 Key，请编辑 $env_file 后重新运行服务器端部署以重建容器。"
  log "如果要接入远端 OpenClaw，请把 OPENCLAW_BASE_URL 改成 http://OpenClaw设备IP:11435/v1，并说“切换open”。"
  log "如果要接入局域网 Ollama，请把 OLLAMA_BASE_URL 改成 http://电脑IP:11434/v1，OLLAMA_MODEL 改成实际模型名，并说“切换ollama”。"
}

annotate_env_file() {
  env_file="$1"
  tmp_file="${env_file}.tmp.$$"
  awk '
    BEGIN {
      note["DEEPSEEK_API_KEY"] = "DeepSeek 官方 API Key；说“切换 deepseek”后使用。"
      note["DEEPSEEK_MODEL"] = "DeepSeek 模型名；默认使用 deepseek-v4-flash。"
      note["DEEPSEEK_BASE_URL"] = "DeepSeek OpenAI 兼容接口地址；官方默认不带 /v1。"
      note["XIAOAI_DOCKER_DNS"] = "可选，容器 DNS；OpenWrt 出现 EAI_AGAIN 时可填 223.5.5.5,119.29.29.29。"
      note["XIAOAI_DOCKER_NETWORK_MODE"] = "容器网络模式；OpenWrt 代理/分流不接管 bridge 容器时可改 host。"
      note["OPENAI_API_KEY"] = "OpenAI 官方或兼容接口 API Key；说“切换 openai”后使用。"
      note["GEMINI_API_KEY"] = "Gemini API Key；说“切换 gemini”后使用。"
      note["OPENAI_BASE_URL"] = "OpenAI 接口地址；兼容服务可改成自己的 /v1 地址。"
      note["CONVERSATION_TURNS"] = "连续对话保留轮数；0 表示不保留上下文。"
      note["OPENCLAW_BASE_URL"] = "OpenClaw API Bridge 地址；OpenClaw 在另一台设备时改成 http://OpenClaw设备IP:11435/v1。"
      note["OPENCLAW_API_KEY"] = "OpenClaw API Bridge 鉴权 Key；需和 Bridge 的 OPENCLAW_BRIDGE_TOKEN 一致，默认本地测试可用 xiaoai-local。"
      note["OPENCLAW_DISPLAY_MODEL"] = "语音里显示/切换用的模型名；默认说“切换 open”即可使用 OpenClaw。"
      note["OPENCLAW_TIMEOUT_MS"] = "OpenClaw 正常问答超时时间，单位毫秒；OpenClaw 响应慢时可适当调大。"
      note["OPENCLAW_TEST_TIMEOUT_MS"] = "“测试模型”命令的超时时间，单位毫秒；一般保持 30000 即可。"
      note["SPEAK_CHUNK_LEN"] = "每段最多字符数；越小越不容易漏字，但回答会被切成更多段。"
      note["SPEAK_MS_PER_CHAR"] = "每个字预估播报耗时，单位毫秒；音箱抢播/漏字时可调大。"
      note["SPEAK_CHUNK_GAP_MS"] = "每段播报之间的额外间隔，单位毫秒；仍漏字时可从 260 调到 400。"
      note["OLLAMA_BASE_URL"] = "Ollama OpenAI 兼容地址；Ollama 在局域网电脑时改成 http://电脑IP:11434/v1。"
      note["OLLAMA_MODEL"] = "Ollama 模型名；必须和 ollama list 里的模型名一致，说“切换 ollama”后使用。"
    }
    /^# ===== 参数说明 =====/ { skip_notes = 1; next }
    skip_notes && /^# (DEEPSEEK_API_KEY|DEEPSEEK_MODEL|DEEPSEEK_BASE_URL|XIAOAI_DOCKER_DNS|XIAOAI_DOCKER_NETWORK_MODE|OPENAI_API_KEY|GEMINI_API_KEY|OPENAI_BASE_URL|CONVERSATION_TURNS|OPENCLAW_BASE_URL|OPENCLAW_API_KEY|OPENCLAW_DISPLAY_MODEL|OPENCLAW_TIMEOUT_MS|OPENCLAW_TEST_TIMEOUT_MS|SPEAK_CHUNK_LEN|SPEAK_MS_PER_CHAR|SPEAK_CHUNK_GAP_MS|PREFIX_GATE_MODE|OLLAMA_BASE_URL|OLLAMA_MODEL)：/ { next }
    skip_notes && /^$/ { next }
    skip_notes { skip_notes = 0 }
    /^# ===== (API Key 配置|OpenClaw 配置|小爱播报配置|Ollama 配置) =====/ { next }
    /^# 如果 OpenClaw 在另一台设备，OPENCLAW_BASE_URL 设置为:/ { next }
    /^# 如果 Ollama 在局域网电脑，OLLAMA_BASE_URL 设置为:/ { next }
    /^# (DeepSeek 官方 API Key|DeepSeek 模型名|DeepSeek OpenAI 兼容接口地址|可选，容器 DNS|容器网络模式|OpenAI 官方或兼容接口 API Key|Gemini API Key|OpenAI 接口地址|连续对话保留轮数|OpenClaw API Bridge 地址|OpenClaw API Bridge 鉴权 Key|语音里显示\/切换用的模型名|OpenClaw 正常问答超时时间|“测试模型”命令的超时时间|每段最多字符数|每个字预估播报耗时|每段播报之间的额外间隔|前缀识别方式|Ollama OpenAI 兼容地址|Ollama 模型名)/ { next }
    /^# (DEEPSEEK_API_KEY|DEEPSEEK_MODEL|DEEPSEEK_BASE_URL|XIAOAI_DOCKER_DNS|XIAOAI_DOCKER_NETWORK_MODE|OPENAI_API_KEY|GEMINI_API_KEY|OPENAI_BASE_URL|CONVERSATION_TURNS|OPENCLAW_BASE_URL|OPENCLAW_API_KEY|OPENCLAW_DISPLAY_MODEL|OPENCLAW_TIMEOUT_MS|OPENCLAW_TEST_TIMEOUT_MS|SPEAK_CHUNK_LEN|SPEAK_MS_PER_CHAR|SPEAK_CHUNK_GAP_MS|PREFIX_GATE_MODE|OLLAMA_BASE_URL|OLLAMA_MODEL)：/ { next }
    /^[A-Z0-9_]+=/ {
      key = $0
      sub(/=.*/, "", key)
      if (key in note) {
        print "# " key "：" note[key]
      }
      print
      next
    }
    { print }
  ' "$env_file" > "$tmp_file"
  mv "$tmp_file" "$env_file"
  log "已按变量位置补充参数备注到 $env_file"
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

remove_env_key() {
  env_file="$1"
  key="$2"
  if ! grep -q "^${key}=" "$env_file"; then
    return 0
  fi
  tmp_file="${env_file}.tmp.$$"
  awk -v key="$key" '$0 !~ "^" key "=" { print }' "$env_file" > "$tmp_file"
  mv "$tmp_file" "$env_file"
  log "已移除 ${key}"
}

update_env_if_provided() {
  env_file="$1"
  key="$2"
  value="$3"
  if [ -z "$value" ]; then
    return 0
  fi
  tmp_file="${env_file}.tmp.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) print key "=" value
    }
  ' "$env_file" > "$tmp_file"
  mv "$tmp_file" "$env_file"
  log "已更新 ${key} 到 $env_file"
}

update_env_if_blank_or_value() {
  env_file="$1"
  key="$2"
  new_value="$3"
  old_value="$4"
  if ! grep -q "^${key}=${old_value}$" "$env_file"; then
    return 0
  fi
  update_env_if_provided "$env_file" "$key" "$new_value"
}

patch_existing_config_defaults() {
  config_file="$WORK_DIR/config.ts"
  [ -f "$config_file" ] || return 0
  if grep -q 'deepseek: { model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1" }' "$config_file"; then
    tmp_file="${config_file}.tmp.$$"
    sed 's/deepseek: { model: "deepseek-chat", baseURL: "https:\/\/api.deepseek.com\/v1" }/deepseek: { model: process.env.DEEPSEEK_MODEL || "deepseek-v4-flash", baseURL: process.env.DEEPSEEK_BASE_URL || "https:\/\/api.deepseek.com" }/' "$config_file" > "$tmp_file"
    mv "$tmp_file" "$config_file"
    log "已更新 config.ts 中的 DeepSeek 默认模型和接口地址"
  elif grep -q 'deepseek: { model: process.env.DEEPSEEK_MODEL || "deepseek-v4-flash", baseURL: "https://api.deepseek.com/v1" }' "$config_file"; then
    tmp_file="${config_file}.tmp.$$"
    sed 's/deepseek: { model: process.env.DEEPSEEK_MODEL || "deepseek-v4-flash", baseURL: "https:\/\/api.deepseek.com\/v1" }/deepseek: { model: process.env.DEEPSEEK_MODEL || "deepseek-v4-flash", baseURL: process.env.DEEPSEEK_BASE_URL || "https:\/\/api.deepseek.com" }/' "$config_file" > "$tmp_file"
    mv "$tmp_file" "$config_file"
    log "已更新 config.ts 中的 DeepSeek 接口地址"
  fi
  if ! grep -q 'FETCH_FAILED:' "$config_file" && grep -q 'const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(body), signal });' "$config_file"; then
    tmp_file="${config_file}.tmp.$$"
    awk '
      /const res = await fetch\(url, \{ method: "POST", headers, body: JSON.stringify\(body\), signal \}\);/ {
        print "  let res: Response;"
        print "  try {"
        print "    res = await fetch(url, { method: \"POST\", headers, body: JSON.stringify(body), signal });"
        print "  } catch (err: any) {"
        print "    const cause = err?.cause;"
        print "    const detail = cause?.code || cause?.message || err?.message || \"fetch failed\";"
        print "    throw new Error(`FETCH_FAILED:${detail}`);"
        print "  }"
        next
      }
      { print }
    ' "$config_file" > "$tmp_file"
    mv "$tmp_file" "$config_file"
    log "已增强 config.ts 中的网络错误日志"
  fi
}

install_server() {
  need_root
  mkdir -p "$WORK_DIR"
  install_docker_if_needed
  fetch_with_fallback_chain "$WORK_DIR/config.ts" \
    "$(cache_bust_url "$CONFIG_URL")" \
    "$(cache_bust_url "$CONFIG_CN_URL")" \
    "$(cache_bust_url "$CONFIG_PROXY_URL")"
  write_env_if_missing
  build_docker_dns_args
  build_docker_network_args

  log "拉取并启动 Docker 容器..."
  log "首次拉取 idootop/open-xiaoai-migpt:latest 会下载并解压多层镜像，在软路由/NAS 上可能持续几分钟。"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    $DOCKER_NETWORK_ARGS \
    $DOCKER_PORT_ARGS \
    $DOCKER_DNS_ARGS \
    --env-file "$WORK_DIR/.env" \
    -v "$WORK_DIR/config.ts:/app/config.ts:ro" \
    idootop/open-xiaoai-migpt:latest >/dev/null

  detect_server_ip
  log "服务器端已启动: ws://${SERVER_IP}:${PORT}"
  log "配置目录: $WORK_DIR"
}

start_server_from_existing_config() {
  need_root
  install_docker_if_needed
  [ -f "$WORK_DIR/.env" ] || die "缺少 $WORK_DIR/.env，请先部署服务器端"
  [ -f "$WORK_DIR/config.ts" ] || die "缺少 $WORK_DIR/config.ts，请先部署服务器端"
  write_env_if_missing
  patch_existing_config_defaults
  build_docker_dns_args
  build_docker_network_args

  log "正在重建 Docker 容器以加载最新配置..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    $DOCKER_NETWORK_ARGS \
    $DOCKER_PORT_ARGS \
    $DOCKER_DNS_ARGS \
    --env-file "$WORK_DIR/.env" \
    -v "$WORK_DIR/config.ts:/app/config.ts:ro" \
    idootop/open-xiaoai-migpt:latest >/dev/null

  detect_server_ip
  log "服务器端已重建: ws://${SERVER_IP}:${PORT}"
  log "已加载配置: $WORK_DIR/.env 和 $WORK_DIR/config.ts"
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
  ensure_speaker_ssh_client
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
    die "音箱端初始化失败"
  fi
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
  restart) start_server_from_existing_config ;;
  uninstall) uninstall_server ;;
  *) usage; exit 1 ;;
esac

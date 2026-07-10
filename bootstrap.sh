#!/bin/sh
set -eu

PROJECT_NAME="xiaoai-openclaw"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SH="$SCRIPT_DIR/install.sh"
NOFLASH_SH="$SCRIPT_DIR/install-noflash.sh"
RAWAUDIO_SH="$SCRIPT_DIR/install-rawaudio.sh"
BRIDGE_SH=""
BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
CN_BASE_URL="${XIAOAI_OPENCLAW_CN_BASE_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main}"
GH_BASE_URL="https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main"
GH_PROXY_BASE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main"
TMP_DIR="/tmp/${PROJECT_NAME}-one-click"

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

fetch_from_mirrors() {
  path="$1"
  out="$2"
  for base in "$BASE_URL" "$CN_BASE_URL" "$GH_BASE_URL" "$GH_PROXY_BASE_URL"; do
    [ -n "$base" ] || continue
    if fetch "$(cache_bust_url "$base/$path")" "$out" 2>/dev/null; then
      return 0
    fi
  done
  echo "下载失败: $path" >&2
  return 1
}

if [ ! -f "$INSTALL_SH" ]; then
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  fetch_from_mirrors "install.sh" "$TMP_DIR/install.sh"
  chmod +x "$TMP_DIR/install.sh"
  INSTALL_SH="$TMP_DIR/install.sh"
fi

if [ ! -f "$NOFLASH_SH" ]; then
  mkdir -p "$TMP_DIR"
  fetch_from_mirrors "install-noflash.sh" "$TMP_DIR/install-noflash.sh"
  chmod +x "$TMP_DIR/install-noflash.sh"
  NOFLASH_SH="$TMP_DIR/install-noflash.sh"
fi

if [ ! -f "$RAWAUDIO_SH" ]; then
  mkdir -p "$TMP_DIR"
  fetch_from_mirrors "install-rawaudio.sh" "$TMP_DIR/install-rawaudio.sh"
  chmod +x "$TMP_DIR/install-rawaudio.sh"
  RAWAUDIO_SH="$TMP_DIR/install-rawaudio.sh"
fi

ensure_bridge_sh() {
  BRIDGE_SH="$SCRIPT_DIR/install-openclaw-bridge.sh"
  if [ ! -f "$BRIDGE_SH" ]; then
    mkdir -p "$TMP_DIR"
    fetch_from_mirrors "install-openclaw-bridge.sh" "$TMP_DIR/install-openclaw-bridge.sh"
    BRIDGE_SH="$TMP_DIR/install-openclaw-bridge.sh"
  fi
}

show_menu() {
  clear 2>/dev/null || true
  echo "======================================"
  echo " XiaoAI OpenClaw One-Click"
  echo "======================================"
  echo "免刷机版（小米账号登录，不需要 SSH 音箱）"
  echo "1) 配置账号并部署免刷机服务"
  echo "2) 修改小米账号/音箱基础配置"
  echo "3) 重建免刷机服务（修改 config.ts 后用）"
  echo "4) 查看免刷机服务状态"
  echo "5) 查看免刷机服务日志"
  echo "6) 卸载免刷机容器（保留配置）"
  echo
  echo "刷机版（已刷 Open-XiaoAI 固件）"
  echo "7) 一键部署服务器端 Docker"
  echo "8) 初始化音箱端 Client"
  echo "9) 服务器 + 音箱端一起部署"
  echo "10) 重启/重建刷机版服务器端 Docker"
  echo "11) 查看刷机版服务器端状态"
  echo "12) 查看刷机版服务器端日志"
  echo "13) 卸载刷机版服务器端容器（保留配置）"
  echo
  echo "OpenClaw API Bridge"
  echo "14) 部署 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "15) 重启 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "16) 清理 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo
  echo "Raw Audio 实验版（PCM -> VAD/KWS -> 本地 ASR -> LLM）"
  echo "17) 部署 Raw Audio 服务端 Docker"
  echo "18) 初始化音箱端 Client 到 Raw Audio 服务"
  echo "19) Raw Audio 服务端 + 音箱端一起部署"
  echo "20) 重启/重建 Raw Audio 服务端 Docker"
  echo "21) 查看 Raw Audio 服务端状态"
  echo "22) 查看 Raw Audio 服务端日志"
  echo "23) 卸载 Raw Audio 服务端容器（保留配置和模型）"
  echo "0) 退出"
  echo
}

while true; do
  show_menu
  printf "请选择: "
  read -r choice
  case "$choice" in
    1) sh "$NOFLASH_SH" --install ;;
    2) sh "$NOFLASH_SH" --configure ;;
    3) sh "$NOFLASH_SH" --restart ;;
    4) sh "$NOFLASH_SH" --status ;;
    5) sh "$NOFLASH_SH" --logs ;;
    6) sh "$NOFLASH_SH" --uninstall ;;
    7) sh "$INSTALL_SH" --server-only ;;
    8) sh "$INSTALL_SH" --client-only ;;
    9) sh "$INSTALL_SH" --all ;;
    10) sh "$INSTALL_SH" --restart ;;
    11) sh "$INSTALL_SH" --status ;;
    12) sh "$INSTALL_SH" --logs ;;
    13) sh "$INSTALL_SH" --uninstall ;;
    14)
      ensure_bridge_sh
      sh "$BRIDGE_SH"
      ;;
    15)
      ensure_bridge_sh
      sh "$BRIDGE_SH" restart
      ;;
    16)
      ensure_bridge_sh
      sh "$BRIDGE_SH" clean
      ;;
    17) sh "$RAWAUDIO_SH" --server-only ;;
    18) sh "$RAWAUDIO_SH" --client-only ;;
    19) sh "$RAWAUDIO_SH" --all ;;
    20) sh "$RAWAUDIO_SH" --restart ;;
    21) sh "$RAWAUDIO_SH" --status ;;
    22) sh "$RAWAUDIO_SH" --logs ;;
    23) sh "$RAWAUDIO_SH" --uninstall ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
  echo
  printf "按回车返回菜单..."
  read -r _
done

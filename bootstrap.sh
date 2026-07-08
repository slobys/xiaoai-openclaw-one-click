#!/bin/sh
set -eu

PROJECT_NAME="xiaoai-openclaw"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SH="$SCRIPT_DIR/install.sh"
NOFLASH_SH="$SCRIPT_DIR/install-noflash.sh"
BRIDGE_SH=""
BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
CN_BASE_URL="${XIAOAI_OPENCLAW_CN_BASE_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main}"
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
  if ! fetch "$(cache_bust_url "$BASE_URL/$path")" "$out"; then
    fetch "$(cache_bust_url "$CN_BASE_URL/$path")" "$out"
  fi
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
  echo
  echo "刷机版（已刷 Open-XiaoAI 固件）"
  echo "4) 一键部署服务器端 Docker"
  echo "5) 初始化音箱端 Client"
  echo "6) 服务器 + 音箱端一起部署"
  echo "7) 重启/重建刷机版服务器端 Docker"
  echo
  echo "通用"
  echo "8) 查看服务状态"
  echo "9) 查看服务日志"
  echo "10) 卸载服务容器（保留配置）"
  echo "11) 部署 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "12) 重启 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "13) 清理 OpenClaw API Bridge（在 OpenClaw 设备运行）"
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
    4) sh "$INSTALL_SH" --server-only ;;
    5) sh "$INSTALL_SH" --client-only ;;
    6) sh "$INSTALL_SH" --all ;;
    7) sh "$INSTALL_SH" --restart ;;
    8) sh "$NOFLASH_SH" --status || sh "$INSTALL_SH" --status ;;
    9) sh "$NOFLASH_SH" --logs ;;
    10) sh "$NOFLASH_SH" --uninstall ;;
    11)
      ensure_bridge_sh
      sh "$BRIDGE_SH"
      ;;
    12)
      ensure_bridge_sh
      sh "$BRIDGE_SH" restart
      ;;
    13)
      ensure_bridge_sh
      sh "$BRIDGE_SH" clean
      ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
  echo
  printf "按回车返回菜单..."
  read -r _
done

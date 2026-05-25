#!/bin/sh
set -eu

PROJECT_NAME="xiaoai-openclaw"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SH="$SCRIPT_DIR/install.sh"
BRIDGE_SH=""

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

if [ ! -f "$INSTALL_SH" ]; then
  TMP_DIR="/tmp/${PROJECT_NAME}-one-click"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
  fetch "$(cache_bust_url "$BASE_URL/install.sh")" "$TMP_DIR/install.sh"
  chmod +x "$TMP_DIR/install.sh"
  INSTALL_SH="$TMP_DIR/install.sh"
fi

ensure_bridge_sh() {
  BRIDGE_SH="$SCRIPT_DIR/install-openclaw-bridge.sh"
  if [ ! -f "$BRIDGE_SH" ]; then
    TMP_DIR="/tmp/${PROJECT_NAME}-one-click"
    mkdir -p "$TMP_DIR"
    BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
    fetch "$(cache_bust_url "$BASE_URL/install-openclaw-bridge.sh")" "$TMP_DIR/install-openclaw-bridge.sh"
    BRIDGE_SH="$TMP_DIR/install-openclaw-bridge.sh"
  fi
}

show_menu() {
  clear 2>/dev/null || true
  echo "======================================"
  echo " XiaoAI OpenClaw One-Click"
  echo "======================================"
  echo "1) 一键部署服务器端 Docker"
  echo "2) 初始化音箱端 Client"
  echo "3) 服务器 + 音箱端一起部署"
  echo "4) 部署 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "5) 重启/重建服务器端 Docker（修改配置后用）"
  echo "6) 查看服务器端状态"
  echo "7) 查看服务器端日志"
  echo "8) 卸载服务器端容器（保留配置）"
  echo "9) 重启 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "10) 清理 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "0) 退出"
  echo
}

while true; do
  show_menu
  printf "请选择: "
  read -r choice
  case "$choice" in
    1) sh "$INSTALL_SH" --server-only ;;
    2) sh "$INSTALL_SH" --client-only ;;
    3) sh "$INSTALL_SH" --all ;;
    4)
      ensure_bridge_sh
      sh "$BRIDGE_SH"
      ;;
    5) sh "$INSTALL_SH" --restart ;;
    6) sh "$INSTALL_SH" --status ;;
    7) sh "$INSTALL_SH" --logs ;;
    8) sh "$INSTALL_SH" --uninstall ;;
    9)
      ensure_bridge_sh
      sh "$BRIDGE_SH" restart
      ;;
    10)
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

#!/bin/sh
set -eu

PROJECT_NAME="xiaoai-openclaw"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SH="$SCRIPT_DIR/install.sh"
BRIDGE_SH=""
BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
CN_BASE_URL="${XIAOAI_OPENCLAW_CN_BASE_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main}"

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
  TMP_DIR="/tmp/${PROJECT_NAME}-one-click"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  fetch_from_mirrors "install.sh" "$TMP_DIR/install.sh"
  chmod +x "$TMP_DIR/install.sh"
  INSTALL_SH="$TMP_DIR/install.sh"
fi

ensure_bridge_sh() {
  BRIDGE_SH="$SCRIPT_DIR/install-openclaw-bridge.sh"
  if [ ! -f "$BRIDGE_SH" ]; then
    TMP_DIR="/tmp/${PROJECT_NAME}-one-click"
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
  echo "1) 配置账号并部署免刷机服务"
  echo "2) 修改小米账号/音箱/模型配置"
  echo "3) 重建免刷机服务"
  echo "4) 部署 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "5) 查看服务状态"
  echo "6) 查看服务日志"
  echo "7) 卸载服务容器（保留账号配置）"
  echo "8) 重启 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "9) 清理 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "0) 退出"
  echo
}

while true; do
  show_menu
  printf "请选择: "
  read -r choice
  case "$choice" in
    1) sh "$INSTALL_SH" --install ;;
    2) sh "$INSTALL_SH" --configure ;;
    3) sh "$INSTALL_SH" --restart ;;
    4)
      ensure_bridge_sh
      sh "$BRIDGE_SH"
      ;;
    5) sh "$INSTALL_SH" --status ;;
    6) sh "$INSTALL_SH" --logs ;;
    7) sh "$INSTALL_SH" --uninstall ;;
    8)
      ensure_bridge_sh
      sh "$BRIDGE_SH" restart
      ;;
    9)
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

#!/bin/sh
set -eu

PROJECT_NAME="xiaoai-openclaw"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SH="$SCRIPT_DIR/install.sh"

if [ ! -f "$INSTALL_SH" ]; then
  TMP_DIR="/tmp/${PROJECT_NAME}-one-click"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  fetch() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$url" -o "$out"
    else
      wget -qO "$out" "$url"
    fi
  }
  BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
  fetch "$BASE_URL/install.sh" "$TMP_DIR/install.sh"
  chmod +x "$TMP_DIR/install.sh"
  INSTALL_SH="$TMP_DIR/install.sh"
fi

show_menu() {
  clear 2>/dev/null || true
  echo "======================================"
  echo " XiaoAI OpenClaw One-Click"
  echo "======================================"
  echo "1) 一键部署服务器端 Docker"
  echo "2) 初始化音箱端 Client"
  echo "3) 服务器 + 音箱端一起部署"
  echo "4) 部署 OpenClaw API Bridge（在 OpenClaw 设备运行）"
  echo "5) 查看状态"
  echo "6) 查看日志"
  echo "7) 卸载服务器端"
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
      BRIDGE_SH="$SCRIPT_DIR/install-openclaw-bridge.sh"
      if [ ! -f "$BRIDGE_SH" ]; then
        TMP_DIR="/tmp/${PROJECT_NAME}-one-click"
        mkdir -p "$TMP_DIR"
        BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
        fetch "$BASE_URL/install-openclaw-bridge.sh" "$TMP_DIR/install-openclaw-bridge.sh"
        BRIDGE_SH="$TMP_DIR/install-openclaw-bridge.sh"
      fi
      sh "$BRIDGE_SH"
      ;;
    5) sh "$INSTALL_SH" --status ;;
    6) sh "$INSTALL_SH" --logs ;;
    7) sh "$INSTALL_SH" --uninstall ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
  echo
  printf "按回车返回菜单..."
  read -r _
done

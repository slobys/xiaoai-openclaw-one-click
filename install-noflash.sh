#!/bin/sh
set -eu

APP_NAME="xiaoai-openclaw"
WORK_DIR="${XIAOAI_OPENCLAW_WORK_DIR:-/opt/open-xiaoai-migpt}"
OLD_WORK_DIR="/opt/${APP_NAME}"
ENV_FILE="$WORK_DIR/.env"
LEGACY_ENV_FILE="$WORK_DIR/migpt.env"
CONFIG_FILE="$WORK_DIR/config.ts"
CONTAINER_NAME="${APP_NAME}"
IMAGE="${MIGPT_IMAGE:-idootop/mi-gpt:latest}"
BASE_URL="${XIAOAI_OPENCLAW_BASE_URL:-https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main}"
CN_BASE_URL="${XIAOAI_OPENCLAW_CN_BASE_URL:-https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main}"
GH_BASE_URL="https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main"
GH_PROXY_BASE_URL="https://gh-proxy.com/https://raw.githubusercontent.com/slobys/xiaoai-openclaw-one-click/main"
MODE="${1:---install}"

log() { printf '%s\n' "$*"; }
die() { log "错误: $*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] && return 0
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  die "当前用户无 Docker 权限，请使用 root 或 sudo sh install-noflash.sh"
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

write_fallback_config_template() {
  out="$1"
  cat > "$out" <<'EOF'
const env = process.env;
const hardwareMap = {
  OH2P: { tts: [7, 3], wake: [7, 1] },
  LX06: { tts: [5, 1], wake: [5, 3] },
  S12: { tts: [5, 1], wake: [5, 3] },
  L05B: { tts: [5, 3], wake: [5, 1] },
};
const hardware = String(env.XIAOAI_HARDWARE || "LX06").toUpperCase();
const speakerCommands = hardwareMap[hardware] || hardwareMap.LX06;
const state = globalThis.__xiaoai_noflash_state || { provider: env.XIAOAI_DEFAULT_PROVIDER || "deepseek", messages: [] };
globalThis.__xiaoai_noflash_state = state;
const systemPrompt = env.XIAOAI_SYSTEM_PROMPT || "你是运行在小爱音箱上的语音助手，由大模型驱动。口播规则：口语化、简短；不要markdown；不要念URL；解释类优先两句话内。";
const turns = Number.parseInt(env.CONVERSATION_TURNS || "6", 10);
function envInt(name, fallback) {
  const n = Number.parseInt(env[name] || "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
const heartbeatMs = envInt("XIAOAI_HEARTBEAT_MS", 500);
const keepAliveIntervalMs = envInt("XIAOAI_KEEPALIVE_INTERVAL_MS", 500);
const exitKeepAliveAfter = envInt("XIAOAI_EXIT_KEEPALIVE_AFTER", 300);
const checkTTSStatusAfter = envInt("XIAOAI_CHECK_TTS_STATUS_AFTER", 1);
const defaultAudioSilentUrl = "https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/assets/silent.mp3";
const audioSilent = env.XIAOAI_AUDIO_SILENT || env.AUDIO_SILENT || (env.XIAOAI_DISABLE_DEFAULT_SILENT === "true" ? undefined : defaultAudioSilentUrl);
function compact(text) {
  return String(text || "").replace(/\s+/g, " ").trim();
}
function norm(text) {
  return compact(text).normalize("NFKC").replace(/\s+/g, "").replace(/[，。！？；：、,.!?;:~`"'“”‘’（）()【】[\]{}<>《》]/g, "").toLowerCase();
}
const noflashMode = globalThis.__xiaoai_noflash_mode || { mode: norm(env.XIAOAI_DEFAULT_MODE || "native") === "ai" ? "ai" : "native" };
globalThis.__xiaoai_noflash_mode = noflashMode;
function list(value, fallback) {
  return `${value || ""},${fallback.join(",")}`.split(/[,，\s]+/).map((x) => x.trim()).filter(Boolean);
}
function promptList(value, fallback) {
  const raw = String(value || "").trim();
  if (/^(none|off|false|0|关闭|无)$/i.test(raw)) return [];
  return raw ? list(value, []) : fallback;
}
function modeKeywords(items, mode) {
  const arr = [...items];
  arr.some = function someWithMode(callback, thisArg) {
    const matched = Array.prototype.some.call(this, callback, thisArg);
    if (matched) noflashMode.mode = mode;
    return matched;
  };
  return arr;
}
const enterAIPrompts = promptList(env.XIAOAI_ENTER_AI_PROMPT, ["好"]);
const exitAIPrompts = promptList(env.XIAOAI_EXIT_AI_PROMPT, ["好"]);
const providers = {
  deepseek: { label: "deepseek", baseURL: env.DEEPSEEK_BASE_URL || "https://api.deepseek.com", apiKey: env.DEEPSEEK_API_KEY || "", model: env.DEEPSEEK_MODEL || "deepseek-v4-flash", kind: "openai" },
  openai: { label: "openai", baseURL: env.OPENAI_BASE_URL || "https://api.openai.com/v1", apiKey: env.OPENAI_API_KEY || "", model: env.OPENAI_MODEL || "gpt-4o-mini", kind: "openai" },
  openclaw: { label: "open", baseURL: env.OPENCLAW_BASE_URL || "", apiKey: env.OPENCLAW_API_KEY || "xiaoai-local", model: env.OPENCLAW_DISPLAY_MODEL || "open", kind: "openai" },
  ollama: { label: "ollama", baseURL: env.OLLAMA_BASE_URL || "", apiKey: env.OLLAMA_API_KEY || "ollama", model: env.OLLAMA_MODEL || "qwen3:4b", kind: "openai" },
  gemini: { label: "gemini", apiKey: env.GEMINI_API_KEY || "", model: env.GEMINI_MODEL || "gemini-3.1-flash-lite-preview", kind: "gemini" },
};
function providerName(name) {
  return providers[name]?.label || name;
}
function normalizeProvider(text) {
  const c = norm(text);
  if (["deepseek", "ds"].includes(c)) return "deepseek";
  if (["openai", "chatgpt", "gpt"].includes(c)) return "openai";
  if (["gemini", "google", "谷歌", "gmini"].includes(c)) return "gemini";
  if (["open", "openclaw", "opencall", "opencloud", "爪子", "本地模型", "本地ai"].includes(c)) return "openclaw";
  if (["ollama", "olama", "欧拉拉", "欧拉马", "欧拉玛", "奥拉马", "奥拉玛", "gemma", "伽马", "电脑", "本地电脑", "局域网模型"].includes(c)) return "ollama";
  return "";
}
function history() {
  return turns > 0 ? state.messages.slice(-turns * 2) : [];
}
function remember(user, assistant) {
  if (turns <= 0) return;
  state.messages.push({ role: "user", content: compact(user) }, { role: "assistant", content: compact(assistant) });
  state.messages = state.messages.slice(-turns * 2);
}
function explain(err) {
  const msg = String(err?.message || err || "未知错误");
  if (msg.includes("EAI_AGAIN")) return `${msg}（DNS 解析临时失败）`;
  if (msg.includes("ENOTFOUND")) return `${msg}（DNS 解析失败）`;
  if (msg.includes("ETIMEDOUT")) return `${msg}（连接超时）`;
  return msg;
}
async function fetchJson(url, options, timeoutMs) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...options, signal: ctrl.signal });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.error) throw new Error(data?.error?.message || `HTTP ${res.status}`);
    return data;
  } catch (err) {
    const cause = err?.cause;
    if (cause?.code) throw new Error(`FETCH_FAILED:${cause.code}`);
    throw err;
  } finally {
    clearTimeout(timer);
  }
}
async function callLLM(name, text, testing = false) {
  const p = providers[name] || providers.deepseek;
  const timeoutMs = name === "openclaw" ? envInt(testing ? "OPENCLAW_TEST_TIMEOUT_MS" : "OPENCLAW_TIMEOUT_MS", testing ? 30000 : 90000) : envInt(testing ? "TEST_TIMEOUT_MS" : "LLM_TIMEOUT_MS", testing ? 6000 : 20000);
  if (p.kind === "gemini") {
    if (!p.apiKey) throw new Error("gemini 还没配置 Key");
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(p.model)}:generateContent?key=${encodeURIComponent(p.apiKey)}`;
    const data = await fetchJson(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: `${systemPrompt}\n\n用户：${text}` }] }] }) }, timeoutMs);
    return compact(data?.candidates?.[0]?.content?.parts?.map((x) => x.text || "").join("") || "");
  }
  if (!p.baseURL) throw new Error(`${providerName(name)} 还没配置接口地址`);
  if (!p.apiKey && name !== "ollama") throw new Error(`${providerName(name)} 还没配置 Key`);
  const url = `${String(p.baseURL).replace(/\/+$/, "")}/chat/completions`;
  const messages = [{ role: "system", content: systemPrompt }, ...history(), { role: "user", content: text }];
  const headers = { "content-type": "application/json" };
  if (p.apiKey) headers.authorization = `Bearer ${p.apiKey}`;
  const data = await fetchJson(url, { method: "POST", headers, body: JSON.stringify({ model: p.model, messages, temperature: 0.7 }) }, timeoutMs);
  return compact(data?.choices?.[0]?.message?.content || data?.output_text || "");
}
function action(text) {
  const c = norm(text);
  if (["开启ai", "打开ai", "切换ai", "ai模式"].includes(c)) return { type: "ai-mode" };
  if (["开启小爱", "切换小爱", "原生模式", "原生小爱", "关闭ai", "退出ai", "关闭小爱"].includes(c)) return { type: "native-mode" };
  if (["当前模型", "查看模型", "当前模式"].includes(c)) return { type: "current" };
  if (["清空上下文", "清除上下文", "清空对话"].includes(c)) return { type: "clear" };
  if (["测试模型", "测试当前模型"].includes(c)) return { type: "test" };
  if (c.startsWith("切换到")) return { type: "switch", provider: normalizeProvider(c.slice(3)) };
  if (c.startsWith("切换")) return { type: "switch", provider: normalizeProvider(c.slice(2)) };
  return null;
}
const commands = {
  match: (msg) => {
    const text = compact(msg.text);
    if (!text) return false;
    return !!action(text) || noflashMode.mode === "ai";
  },
  run: async (msg) => {
    const text = compact(msg.text);
    const a = action(msg.text);
    if (!a) {
      try { const answer = await callLLM(state.provider, text); remember(text, answer); return { text: answer || "我没听清，你能再说一次吗？" }; }
      catch (err) { return { text: `${providerName(state.provider)} 调用失败：${explain(err)}` }; }
    }
    if (a.type === "ai-mode") { noflashMode.mode = "ai"; state.messages = []; return { text: "已切换到AI模式。" }; }
    if (a.type === "native-mode") { noflashMode.mode = "native"; state.messages = []; return { text: "已切换到原生小爱模式。" }; }
    if (["switch", "test"].includes(a.type) && noflashMode.mode !== "ai") return { text: "请先说：开启AI。" };
    if (a.type === "current") return { text: `当前模型是 ${providerName(state.provider)}，模型名 ${providers[state.provider]?.model || ""}。` };
    if (a.type === "clear") { state.messages = []; return { text: "已清空上下文。" }; }
    if (a.type === "switch") { if (!a.provider) return { text: "没听清要切换到哪个模型。" }; state.provider = a.provider; state.messages = []; return { text: `已切换到 ${providerName(a.provider)}。` }; }
    if (a.type === "test") {
      const start = Date.now();
      try { const answer = await callLLM(state.provider, "请只回答 OK", true); return { text: `连通正常：${providerName(state.provider)}，${Date.now() - start}毫秒，返回：${answer}` }; }
      catch (err) { return { text: `测试失败：${explain(err)}` }; }
    }
  },
};
const speakerConfig = {
  callAIKeywords: list(env.XIAOAI_CALL_KEYWORD, ["问AI", "问 ai", "问小爱", "揾AI", "文AI"]),
  wakeUpKeywords: modeKeywords(list(env.XIAOAI_WAKE_KEYWORD, ["打开AI", "开启AI", "切换AI", "AI模式"]), "ai"),
  exitKeywords: modeKeywords(list(env.XIAOAI_EXIT_KEYWORD, ["关闭AI", "退出AI", "关闭小爱", "开启小爱", "切换小爱", "原生模式", "原生小爱"]), "native"),
  onEnterAI: enterAIPrompts,
  onExitAI: exitAIPrompts,
  onAIError: ["连接模型失败，请稍后再试"],
  commands: [commands],
  askAI: async (msg) => {
    const text = String(msg.text || "").replace(/^(问AI|问 ai|问小爱|揾AI|文AI)/i, "").trim();
    try { const answer = await callLLM(state.provider, text); remember(text, answer); return { text: answer || "我没听清，你能再说一次吗？" }; }
    catch (err) { return { text: `${providerName(state.provider)} 调用失败：${explain(err)}` }; }
  },
  ttsCommand: speakerCommands.tts,
  wakeUpCommand: speakerCommands.wake,
  heartbeat: heartbeatMs,
  checkInterval: keepAliveIntervalMs,
  exitKeepAliveAfter,
  checkTTSStatusAfter,
  audioSilent,
  streamResponse: env.XIAOAI_STREAM_RESPONSE !== "false",
  debug: env.XIAOAI_DEBUG === "true",
};
speakerConfig["user" + "Id"] = env.MI_USER;
speakerConfig["pass" + "word"] = env.MI_PASS || "__cookie_login__";
speakerConfig["di" + "d"] = env.MI_DID;
export default { systemTemplate: `${systemPrompt}\n\n最近对话：\n{{messages}}`, bot: { name: "AI助手", profile: "简洁、可靠的语音助手" }, master: { name: "用户", profile: "" }, speaker: speakerConfig };
EOF
}

fetch_template() {
  path="$1"
  out="$2"
  script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  if [ -f "$script_dir/$path" ]; then
    cp "$script_dir/$path" "$out"
    return 0
  fi
  for base in "$BASE_URL" "$CN_BASE_URL" "$GH_BASE_URL" "$GH_PROXY_BASE_URL"; do
    [ -n "$base" ] || continue
    if fetch "$base/$path?ts=$(date +%s)" "$out" 2>/dev/null; then
      return 0
    fi
  done
  if [ "$path" = "templates/config-noflash.ts" ]; then
    log "远程 config-noflash.ts 下载失败，使用安装脚本内置兜底配置。"
    write_fallback_config_template "$out"
    return 0
  fi
  die "下载失败: $path，请重新拉取最新 bootstrap 或检查网络"
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
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1
}

env_or_default() {
  key="$1"
  fallback="$2"
  value=$(env_value "$key")
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

is_known_env_key() {
  case "$1" in
    MI_USER|MI_PASS|MI_PASS_TOKEN|MI_DID|MI_DEVICE_ID|XIAOAI_HARDWARE|\
    XIAOAI_DEFAULT_MODE|XIAOAI_CALL_KEYWORD|XIAOAI_WAKE_KEYWORD|XIAOAI_EXIT_KEYWORD|XIAOAI_STREAM_RESPONSE|XIAOAI_DEBUG|XIAOAI_SYSTEM_PROMPT|\
    XIAOAI_HEARTBEAT_MS|XIAOAI_KEEPALIVE_INTERVAL_MS|XIAOAI_EXIT_KEEPALIVE_AFTER|XIAOAI_CHECK_TTS_STATUS_AFTER|XIAOAI_AUDIO_SILENT|AUDIO_SILENT|XIAOAI_DISABLE_DEFAULT_SILENT|XIAOAI_ENTER_AI_PROMPT|XIAOAI_EXIT_AI_PROMPT|\
    XIAOAI_DEFAULT_PROVIDER|CONVERSATION_TURNS|LLM_TIMEOUT_MS|TEST_TIMEOUT_MS|\
    XIAOAI_DOCKER_DNS|XIAOAI_DOCKER_NETWORK_MODE|\
    SPEAK_CHUNK_LEN|SPEAK_MS_PER_CHAR|SPEAK_CHUNK_GAP_MS|\
    OPENCLAW_BASE_URL|OPENCLAW_API_KEY|OPENCLAW_DISPLAY_MODEL|OPENCLAW_MODEL|OPENCLAW_TIMEOUT_MS|OPENCLAW_TEST_TIMEOUT_MS|\
    OPENAI_BASE_URL|OPENAI_API_KEY|OPENAI_MODEL|\
    DEEPSEEK_BASE_URL|DEEPSEEK_API_KEY|DEEPSEEK_MODEL|\
    GEMINI_API_KEY|GEMINI_MODEL|\
    OLLAMA_BASE_URL|OLLAMA_API_KEY|OLLAMA_MODEL|OLLAMA_TIMEOUT_MS)
      return 0
      ;;
  esac
  return 1
}

append_env_line() {
  key="$1"
  fallback="$2"
  printf '%s=%s\n' "$key" "$(env_or_default "$key" "$fallback")" >> "$3"
}

append_env_value() {
  key="$1"
  value="$2"
  printf '%s=%s\n' "$key" "$value" >> "$3"
}

looks_like_openclaw_base() {
  case "$1" in
    *:11435*|*openclaw*|*OpenClaw*) return 0 ;;
  esac
  return 1
}

looks_like_deepseek_base() {
  case "$1" in
    *api.deepseek.com*) return 0 ;;
  esac
  return 1
}

normalize_deepseek_base_url() {
  printf '%s' "${1%/}"
}

normalize_env_file() {
  [ -f "$ENV_FILE" ] || return 0
  tmp="$ENV_FILE.tmp.$$"
  : > "$tmp"

  openclaw_base=$(env_value "OPENCLAW_BASE_URL")
  openclaw_key=$(env_value "OPENCLAW_API_KEY")
  openclaw_model=$(env_value "OPENCLAW_DISPLAY_MODEL")
  openai_base=$(env_value "OPENAI_BASE_URL")
  openai_key=$(env_value "OPENAI_API_KEY")
  openai_model=$(env_value "OPENAI_MODEL")
  deepseek_base=$(env_value "DEEPSEEK_BASE_URL")
  deepseek_key=$(env_value "DEEPSEEK_API_KEY")
  deepseek_model=$(env_value "DEEPSEEK_MODEL")

  # Older releases used OPENAI_* for the OpenClaw bridge. Move that legacy
  # shape into the OpenClaw section so the visible config stays unambiguous.
  if [ -z "$openclaw_base" ] && looks_like_openclaw_base "$openai_base"; then
    openclaw_base="$openai_base"
    [ -n "$openclaw_key" ] || openclaw_key="$openai_key"
    [ -n "$openclaw_model" ] || openclaw_model="$openai_model"
    openai_base=""
    openai_key=""
    openai_model=""
  fi

  # A short-lived menu version asked OpenClaw fields while the selected provider
  # was DeepSeek. Repair that common mistaken layout when it is obvious.
  if looks_like_deepseek_base "$openclaw_base"; then
    [ -n "$deepseek_base" ] || deepseek_base="$openclaw_base"
    case "$openclaw_key" in
      sk-*) [ -n "$deepseek_key" ] || deepseek_key="$openclaw_key" ;;
    esac
    [ -n "$deepseek_model" ] || deepseek_model="$openclaw_model"
    openclaw_base=""
    openclaw_key=""
    openclaw_model=""
  fi

  [ -n "$openclaw_key" ] || openclaw_key="xiaoai-local"
  [ -n "$openclaw_model" ] || openclaw_model="open"
  [ -n "$openai_base" ] || openai_base="https://api.openai.com/v1"
  [ -n "$openai_model" ] || openai_model="gpt-4o-mini"
  [ -n "$deepseek_base" ] || deepseek_base="https://api.deepseek.com"
  deepseek_base=$(normalize_deepseek_base_url "$deepseek_base")
  [ -n "$deepseek_model" ] || deepseek_model="deepseek-v4-flash"

  {
    printf '%s\n' '# ===== 免刷机账号配置 ====='
    printf '%s\n' '# MI_USER：小米 ID，不是手机号或邮箱。'
  } >> "$tmp"
  append_env_line "MI_USER" "" "$tmp"
  printf '%s\n' '# MI_PASS：小米账号密码；使用 passToken Cookie 时可留空。' >> "$tmp"
  append_env_line "MI_PASS" "" "$tmp"
  printf '%s\n' '# MI_PASS_TOKEN：浏览器已登录小米账号后的 passToken Cookie，可填 passToken 值或整段 Cookie。' >> "$tmp"
  append_env_line "MI_PASS_TOKEN" "" "$tmp"
  printf '%s\n' '# MI_DID：米家中的音箱名称或设备 DID。' >> "$tmp"
  append_env_line "MI_DID" "" "$tmp"
  printf '%s\n' '# XIAOAI_HARDWARE：音箱型号代码，例如 LX06、L05B、OH2P。' >> "$tmp"
  append_env_line "XIAOAI_HARDWARE" "LX06" "$tmp"
  if [ -n "$(env_value "MI_DEVICE_ID")" ]; then
    append_env_line "MI_DEVICE_ID" "" "$tmp"
  fi

  {
    printf '\n%s\n' '# ===== 语音触发 ====='
    printf '%s\n' '# XIAOAI_DEFAULT_MODE：默认 native，普通问题交给原生小爱；说“开启AI”后进入 AI 模式。'
    printf '%s\n' '# 问AI/问小爱：原生模式下单次交给 AI。'
    printf '%s\n' '# 开启AI：进入 AI；开启小爱/关闭AI/原生小爱：回到原生小爱。'
  } >> "$tmp"
  append_env_value "XIAOAI_DEFAULT_MODE" "native" "$tmp"
  append_env_line "XIAOAI_CALL_KEYWORD" "问AI" "$tmp"
  append_env_line "XIAOAI_WAKE_KEYWORD" "开启AI" "$tmp"
  append_env_line "XIAOAI_EXIT_KEYWORD" "关闭AI" "$tmp"
  append_env_value "XIAOAI_STREAM_RESPONSE" "true" "$tmp"
  append_env_line "XIAOAI_HEARTBEAT_MS" "500" "$tmp"
  append_env_line "XIAOAI_KEEPALIVE_INTERVAL_MS" "500" "$tmp"
  append_env_line "XIAOAI_EXIT_KEEPALIVE_AFTER" "300" "$tmp"
  append_env_line "XIAOAI_CHECK_TTS_STATUS_AFTER" "1" "$tmp"
  append_env_line "XIAOAI_DISABLE_DEFAULT_SILENT" "false" "$tmp"
  if [ -n "$(env_value "XIAOAI_ENTER_AI_PROMPT")" ]; then
    append_env_line "XIAOAI_ENTER_AI_PROMPT" "" "$tmp"
  fi
  if [ -n "$(env_value "XIAOAI_EXIT_AI_PROMPT")" ]; then
    append_env_line "XIAOAI_EXIT_AI_PROMPT" "" "$tmp"
  fi
  if [ -n "$(env_value "XIAOAI_AUDIO_SILENT")" ]; then
    append_env_line "XIAOAI_AUDIO_SILENT" "" "$tmp"
  fi
  if [ -n "$(env_value "AUDIO_SILENT")" ]; then
    append_env_line "AUDIO_SILENT" "" "$tmp"
  fi
  append_env_line "XIAOAI_DEBUG" "false" "$tmp"
  if [ -n "$(env_value "XIAOAI_SYSTEM_PROMPT")" ]; then
    append_env_line "XIAOAI_SYSTEM_PROMPT" "" "$tmp"
  fi

  {
    printf '\n%s\n' '# ===== 运行参数 ====='
    printf '%s\n' '# 模型来源、API Key 和模型名可直接改本文件，也可以改 /opt/open-xiaoai-migpt/config.ts。'
  } >> "$tmp"
  append_env_line "CONVERSATION_TURNS" "6" "$tmp"
  append_env_line "LLM_TIMEOUT_MS" "20000" "$tmp"
  append_env_line "TEST_TIMEOUT_MS" "6000" "$tmp"
  append_env_line "OPENCLAW_TIMEOUT_MS" "90000" "$tmp"
  append_env_line "OPENCLAW_TEST_TIMEOUT_MS" "30000" "$tmp"
  append_env_line "OLLAMA_TIMEOUT_MS" "90000" "$tmp"
  append_env_line "SPEAK_CHUNK_LEN" "28" "$tmp"
  append_env_line "SPEAK_MS_PER_CHAR" "220" "$tmp"
  append_env_line "SPEAK_CHUNK_GAP_MS" "260" "$tmp"

  compat_header_written=0
  append_compat_env() {
    key="$1"
    value="$2"
    if [ "$compat_header_written" -eq 0 ]; then
      {
        printf '\n%s\n' '# ===== 模型配置：沿用刷机版 .env ====='
        printf '%s\n' '# 这里保留当前刷机版已经优化好的模型参数，也可在 /opt/open-xiaoai-migpt/config.ts 里写死。'
      } >> "$tmp"
      compat_header_written=1
    fi
    append_env_value "$key" "$value" "$tmp"
  }
  append_compat_env "XIAOAI_DEFAULT_PROVIDER" "$(env_or_default "XIAOAI_DEFAULT_PROVIDER" "deepseek")"
  append_compat_env "DEEPSEEK_BASE_URL" "$deepseek_base"
  append_compat_env "DEEPSEEK_API_KEY" "$deepseek_key"
  append_compat_env "DEEPSEEK_MODEL" "$deepseek_model"
  append_compat_env "OPENAI_BASE_URL" "$openai_base"
  append_compat_env "OPENAI_API_KEY" "$openai_key"
  append_compat_env "OPENAI_MODEL" "$openai_model"
  append_compat_env "GEMINI_API_KEY" "$(env_value "GEMINI_API_KEY")"
  append_compat_env "GEMINI_MODEL" "$(env_or_default "GEMINI_MODEL" "gemini-3.1-flash-lite-preview")"
  append_compat_env "OPENCLAW_BASE_URL" "$openclaw_base"
  append_compat_env "OPENCLAW_API_KEY" "$openclaw_key"
  append_compat_env "OPENCLAW_DISPLAY_MODEL" "$openclaw_model"
  append_compat_env "OPENCLAW_MODEL" "$(env_value "OPENCLAW_MODEL")"
  append_compat_env "OLLAMA_BASE_URL" "$(env_or_default "OLLAMA_BASE_URL" "http://192.168.2.193:11434/v1")"
  append_compat_env "OLLAMA_API_KEY" "$(env_value "OLLAMA_API_KEY")"
  append_compat_env "OLLAMA_MODEL" "$(env_or_default "OLLAMA_MODEL" "qwen3:4b")"

  extra_header_written=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      *=*)
        key=${line%%=*}
        if ! is_known_env_key "$key"; then
          if [ "$extra_header_written" -eq 0 ]; then
            {
              printf '\n%s\n' '# ===== 其他自定义变量 ====='
            } >> "$tmp"
            extra_header_written=1
          fi
          printf '%s\n' "$line" >> "$tmp"
        fi
        ;;
    esac
  done < "$ENV_FILE"

  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

patch_config_for_migpt_openai_env() {
  [ -f "$CONFIG_FILE" ] || return 0
  if grep -q "applyProviderToMiGPTEnv" "$CONFIG_FILE"; then
    return 0
  fi
  tmp="$CONFIG_FILE.tmp.$$"
  awk '
    BEGIN { in_switch = 0; inserted_initial = 0; inserted_switch = 0 }
    {
      print
      if (!inserted_initial && $0 ~ /^globalThis\.__xiaoai_llm_state = llmState;$/) {
        print "applyProviderToMiGPTEnv(llmState.provider);"
        inserted_initial = 1
      }
      if ($0 ~ /^function switchProvider\(provider\)/) {
        in_switch = 1
      }
      if (in_switch && !inserted_switch && $0 ~ /llmState\.messages = \[\];/) {
        print "  applyProviderToMiGPTEnv(provider);"
        inserted_switch = 1
      }
      if (in_switch && $0 ~ /^}/) {
        in_switch = 0
      }
    }
    END {
      print ""
      print "function applyProviderToMiGPTEnv(provider) {"
      print "  const p = providers[provider];"
      print "  if (!p || p.kind !== \"openai\") return false;"
      print "  if (!p.baseURL || !p.model) return false;"
      print "  process.env.OPENAI_BASE_URL = p.baseURL;"
      print "  process.env.OPENAI_API_KEY = p.apiKey || \"dummy\";"
      print "  process.env.OPENAI_MODEL = p.model;"
      print "  return true;"
      print "}"
    }
  ' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log "已给 $CONFIG_FILE 补充 MiGPT 内置 OpenAI 环境同步逻辑"
}

patch_config_for_custom_qa_command() {
  [ -f "$CONFIG_FILE" ] || return 0
  if grep -q "fallbackQACommand" "$CONFIG_FILE"; then
    return 0
  fi
  grep -q "const callAIKeywords" "$CONFIG_FILE" || return 0
  grep -q "function stripCallKeyword" "$CONFIG_FILE" || return 0
  tmp="$CONFIG_FILE.tmp.$$"
  awk '
    {
      if ($0 ~ /^export default \{/) {
        print "const noflashMode = globalThis.__xiaoai_noflash_mode || {"
        print "  mode: normalizeCommand(process.env.XIAOAI_DEFAULT_MODE || \"native\") === \"ai\" ? \"ai\" : \"native\","
        print "};"
        print "globalThis.__xiaoai_noflash_mode = noflashMode;"
        print ""
        print "function hasCallAIKeyword(text) {"
        print "  const cmd = normalizeCommand(text);"
        print "  return callAIKeywords.some((keyword) => cmd.startsWith(normalizeCommand(keyword)));"
        print "}"
        print ""
        print "const fallbackQACommand = {"
        print "  match: (msg) => {"
        print "    const text = String(msg?.text || \"\").trim();"
        print "    if (!text) return false;"
        print "    return (noflashMode.mode === \"ai\" || hasCallAIKeyword(text)) && !commandAction(text);"
        print "  },"
        print "  run: async (msg) => {"
        print "    const userText = stripCallKeyword(msg.text);"
        print "    const provider = currentProvider();"
        print "    try {"
        print "      const answer = await callLLM(provider, userText);"
        print "      rememberTurn(userText, answer);"
        print "      return { text: answer };"
        print "    } catch (err) {"
        print "      return { text: `${providerName(provider)} 调用失败：${err?.message || \"未知错误\"}` };"
        print "    }"
        print "  },"
        print "};"
        print ""
      }
      if ($0 ~ /commands: \[providerCommands\],/) {
        sub(/commands: \[providerCommands\],/, "commands: [providerCommands, fallbackQACommand],")
      }
      print
    }
  ' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log "已给 $CONFIG_FILE 补充连续对话自定义问答逻辑"
}

patch_config_for_flash_like_mode_state() {
  [ -f "$CONFIG_FILE" ] || return 0
  if grep -q "XIAOAI_DEFAULT_MODE || \"native\"" "$CONFIG_FILE" && grep -q "请先说：开启AI" "$CONFIG_FILE" && grep -q "modeKeywords(wakeUpKeywords, \"ai\")" "$CONFIG_FILE" && grep -q "heartbeat: heartbeatMs" "$CONFIG_FILE" && grep -q "defaultAudioSilentUrl" "$CONFIG_FILE" && grep -q "function promptList" "$CONFIG_FILE" && grep -q '"切换AI", "AI模式"' "$CONFIG_FILE"; then
    return 0
  fi
  grep -q "function stripCallKeyword" "$CONFIG_FILE" || return 0
  if grep -q "function hasCallAIKeyword" "$CONFIG_FILE"; then
    has_call_helper=1
  else
    has_call_helper=0
  fi
  if grep -q "noflashMode" "$CONFIG_FILE"; then
    has_noflash_mode=1
  else
    has_noflash_mode=0
  fi
  if grep -q "function modeKeywords" "$CONFIG_FILE"; then
    has_mode_keywords=1
  else
    has_mode_keywords=0
  fi
  if grep -q "heartbeat: heartbeatMs" "$CONFIG_FILE"; then
    has_keepalive_tuning=1
  else
    has_keepalive_tuning=0
  fi
  tmp="$CONFIG_FILE.tmp.$$"
  awk -v has_call_helper="$has_call_helper" -v has_noflash_mode="$has_noflash_mode" -v has_mode_keywords="$has_mode_keywords" -v has_keepalive_tuning="$has_keepalive_tuning" '
    BEGIN { inserted_mode = has_noflash_mode; inserted_keywords = has_mode_keywords; inserted_tuning_consts = has_keepalive_tuning; inserted_tuning_fields = has_keepalive_tuning; inserted_actions = 0; inserted_run = 0; in_command_action = 0 }
    {
      if (!inserted_tuning_consts && $0 ~ /^const streamResponse = /) {
        print
        print "const heartbeatMs = envInt(\"XIAOAI_HEARTBEAT_MS\", 500);"
        print "const keepAliveIntervalMs = envInt(\"XIAOAI_KEEPALIVE_INTERVAL_MS\", 500);"
        print "const exitKeepAliveAfter = envInt(\"XIAOAI_EXIT_KEEPALIVE_AFTER\", 300);"
        print "const checkTTSStatusAfter = envInt(\"XIAOAI_CHECK_TTS_STATUS_AFTER\", 1);"
        inserted_tuning_consts = 1
        next
      }
      if (!inserted_mode && has_call_helper == 1 && $0 ~ /^function hasCallAIKeyword\(text\)/) {
        print "const noflashMode = globalThis.__xiaoai_noflash_mode || {"
        print "  mode: normalizeCommand(process.env.XIAOAI_DEFAULT_MODE || \"native\") === \"ai\" ? \"ai\" : \"native\","
        print "};"
        print "globalThis.__xiaoai_noflash_mode = noflashMode;"
        print ""
        inserted_mode = 1
      }
      if (!inserted_mode && has_call_helper == 0 && $0 ~ /^function stripCallKeyword\(text\)/) {
        print "const noflashMode = globalThis.__xiaoai_noflash_mode || {"
        print "  mode: normalizeCommand(process.env.XIAOAI_DEFAULT_MODE || \"native\") === \"ai\" ? \"ai\" : \"native\","
        print "};"
        print "globalThis.__xiaoai_noflash_mode = noflashMode;"
        print ""
        print "function hasCallAIKeyword(text) {"
        print "  const cmd = normalizeCommand(text);"
        print "  return callAIKeywords.some((keyword) => cmd.startsWith(normalizeCommand(keyword)));"
        print "}"
        print ""
        inserted_mode = 1
      }
      if (!inserted_keywords && $0 ~ /^function historyMessages\(\)/) {
        print "function modeKeywords(items, mode) {"
        print "  const arr = [...items];"
        print "  arr.some = function someWithMode(callback, thisArg) {"
        print "    const matched = Array.prototype.some.call(this, callback, thisArg);"
        print "    if (matched) noflashMode.mode = mode;"
        print "    return matched;"
        print "  };"
        print "  return arr;"
        print "}"
        print ""
        inserted_keywords = 1
      }
      if ($0 ~ /^function commandAction\(text\)/) {
        in_command_action = 1
      }
      if (in_command_action && !inserted_actions && $0 ~ /^  const cmd = normalizeCommand\(text\);$/) {
        print
        print "  if ([\"开启ai\", \"打开ai\", \"切换ai\", \"ai模式\"].includes(cmd)) return { type: \"ai-mode\" };"
        print "  if ([\"开启小爱\", \"切换小爱\", \"原生模式\", \"原生小爱\", \"关闭ai\", \"退出ai\", \"关闭小爱\"].includes(cmd)) return { type: \"native-mode\" };"
        inserted_actions = 1
        next
      }
      if (!inserted_run && $0 ~ /^    if \(!action\) return undefined;$/) {
        print
        print "    if (action.type === \"ai-mode\") {"
        print "      noflashMode.mode = \"ai\";"
        print "      llmState.messages = [];"
        print "      return { text: \"已切换到AI模式。\" };"
        print "    }"
        print "    if (action.type === \"native-mode\") {"
        print "      noflashMode.mode = \"native\";"
        print "      llmState.messages = [];"
        print "      return { text: \"已切换到原生小爱模式。\" };"
        print "    }"
        print "    if ([\"switch\", \"test\"].includes(action.type) && noflashMode.mode !== \"ai\") {"
        print "      return { text: \"请先说：开启AI。\" };"
        print "    }"
        inserted_run = 1
        next
      }
      if ($0 ~ /return hasCallAIKeyword\(text\) && !commandAction\(text\);/ || $0 ~ /return !commandAction\(text\);/) {
        print "    return (noflashMode.mode === \"ai\" || hasCallAIKeyword(text)) && !commandAction(text);"
        next
      }
      if ($0 ~ /^  wakeUpKeywords,$/ || $0 ~ /^  wakeUpKeywords: /) {
        print "  wakeUpKeywords: modeKeywords(wakeUpKeywords, \"ai\"),"
        next
      }
      if ($0 ~ /^  exitKeywords,$/ || $0 ~ /^  exitKeywords: /) {
        print "  exitKeywords: modeKeywords(exitKeywords, \"native\"),"
        next
      }
      if (!inserted_tuning_fields && $0 ~ /^  streamResponse,/) {
        print "  heartbeat: heartbeatMs,"
        print "  checkInterval: keepAliveIntervalMs,"
        print "  exitKeepAliveAfter,"
        print "  checkTTSStatusAfter,"
        print "  audioSilent: env.XIAOAI_AUDIO_SILENT || env.AUDIO_SILENT || undefined,"
        inserted_tuning_fields = 1
      }
      print
      if (in_command_action && $0 ~ /^}/) {
        in_command_action = 0
      }
    }
  ' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  tmp="$CONFIG_FILE.tmp.$$"
  sed \
    -e 's/process\.env\.XIAOAI_DEFAULT_MODE || "ai"/process.env.XIAOAI_DEFAULT_MODE || "native"/g' \
    -e 's/env\.XIAOAI_DEFAULT_MODE || "ai"/env.XIAOAI_DEFAULT_MODE || "native"/g' \
    -e 's/\["打开AI", "开启AI", "开启小爱"\]/["打开AI", "开启AI"]/g' \
    -e 's/\["打开AI", "开启AI"\]/["打开AI", "开启AI", "切换AI", "AI模式"]/g' \
    -e 's/\["关闭AI", "退出AI", "关闭小爱"\]/["关闭AI", "退出AI", "关闭小爱", "开启小爱", "切换小爱", "原生模式", "原生小爱"]/g' \
    -e 's/\["开启ai", "打开ai", "切换ai", "ai模式", "开启小爱"\]/["开启ai", "打开ai", "切换ai", "ai模式"]/g' \
    -e 's/\["关闭ai", "退出ai", "关闭小爱", "原生小爱", "原生模式", "切换小爱"\]/["开启小爱", "切换小爱", "原生模式", "原生小爱", "关闭ai", "退出ai", "关闭小爱"]/g' \
    -e 's/  onEnterAI: \["AI模式已开启"\],/  onEnterAI: ["好"],/g' \
    -e 's/  onExitAI: \["AI模式已关闭"\],/  onExitAI: ["好"],/g' \
    -e 's/const enterAIPrompts = keywords(env\.XIAOAI_ENTER_AI_PROMPT, \[\]);/const enterAIPrompts = promptList(env.XIAOAI_ENTER_AI_PROMPT, ["好"]);/g' \
    -e 's/const exitAIPrompts = keywords(env\.XIAOAI_EXIT_AI_PROMPT, \[\]);/const exitAIPrompts = promptList(env.XIAOAI_EXIT_AI_PROMPT, ["好"]);/g' \
    -e 's/  audioSilent: env\.XIAOAI_AUDIO_SILENT || env\.AUDIO_SILENT || undefined,/  audioSilent,/g' \
    "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  if ! grep -q "function promptList" "$CONFIG_FILE"; then
    tmp="$CONFIG_FILE.tmp.$$"
    awk '
      {
        print
        if ($0 ~ /^function keywords\(value, defaults\)/) {
          in_keywords = 1
        } else if (in_keywords && $0 ~ /^}$/) {
          print ""
          print "function promptList(value, defaults) {"
          print "  const raw = String(value || \"\").trim();"
          print "  if (/^(none|off|false|0|关闭|无)$/i.test(raw)) return [];"
          print "  return raw ? keywords(value, []) : defaults;"
          print "}"
          in_keywords = 0
        }
      }
    ' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
  fi
  if ! grep -q "defaultAudioSilentUrl" "$CONFIG_FILE"; then
    tmp="$CONFIG_FILE.tmp.$$"
    awk '
      {
        print
        if ($0 ~ /^const checkTTSStatusAfter = /) {
          print "const defaultAudioSilentUrl = \"https://gitee.com/naiyou88/xiaoai-openclaw-one-click/raw/main/assets/silent.mp3\";"
          print "const audioSilent ="
          print "  env.XIAOAI_AUDIO_SILENT ||"
          print "  env.AUDIO_SILENT ||"
          print "  (env.XIAOAI_DISABLE_DEFAULT_SILENT === \"true\" ? undefined : defaultAudioSilentUrl);"
        }
      }
    ' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
  fi
  chmod 600 "$CONFIG_FILE"
  log "已给 $CONFIG_FILE 启用免刷机刷机版同款模式状态机"
}

set_env() {
  key="$1"
  value="$2"
  tmp="$ENV_FILE.tmp.$$"
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
  done < "$ENV_FILE"
  [ "$found" -eq 1 ] || printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
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
  env_from_template=0
  if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$LEGACY_ENV_FILE" ]; then
      cp "$LEGACY_ENV_FILE" "$ENV_FILE"
      log "已从旧配置 $LEGACY_ENV_FILE 迁移到 $ENV_FILE"
    elif [ -f "$OLD_WORK_DIR/.env" ]; then
      cp "$OLD_WORK_DIR/.env" "$ENV_FILE"
      log "已从旧目录 $OLD_WORK_DIR/.env 迁移配置到 $ENV_FILE"
    else
      fetch_template "templates/env-noflash.example" "$ENV_FILE"
      env_from_template=1
    fi
    chmod 600 "$ENV_FILE"
  fi
  [ "$env_from_template" -eq 1 ] || normalize_env_file
  if [ ! -f "$CONFIG_FILE" ]; then
    fetch_template "templates/config-noflash.ts" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
  fi
  patch_config_for_migpt_openai_env
  patch_config_for_custom_qa_command
  patch_config_for_flash_like_mode_state
  ln -sf "$(basename "$CONFIG_FILE")" "$WORK_DIR/.migpt.js" 2>/dev/null || true
  ln -sf "$(basename "$ENV_FILE")" "$LEGACY_ENV_FILE" 2>/dev/null || true
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
  set_env "XIAOAI_DEFAULT_MODE" "native"
  set_env "XIAOAI_STREAM_RESPONSE" "true"
  log "基础配置已保存到 $ENV_FILE"
  log "模型配置继续使用 $ENV_FILE 和 $CONFIG_FILE，按旧教程添加 API Key 后运行菜单 3 重建服务。"
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
    --env-file "$ENV_FILE" \
    -v "$CONFIG_FILE:/app/.migpt.js:ro" \
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
  --status)
    command -v docker >/dev/null 2>&1 || die "Docker 未安装"
    docker ps -a --filter "name=${CONTAINER_NAME}"
    ;;
  --logs)
    command -v docker >/dev/null 2>&1 || die "Docker 未安装"
    docker logs -f --tail=120 "$CONTAINER_NAME"
    ;;
  --uninstall)
    need_root
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    log "容器已删除，配置仍保留在 $WORK_DIR"
    ;;
  -h|--help)
    echo "用法: sh install.sh [--install|--configure|--restart|--status|--logs|--uninstall]"
    ;;
  *) die "未知参数: $MODE" ;;
esac

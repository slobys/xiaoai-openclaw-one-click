#!/bin/sh
set -eu

APP_NAME="xiaoai-openclaw"
WORK_DIR="${XIAOAI_OPENCLAW_WORK_DIR:-/opt/open-xiaoai-migpt}"
OLD_WORK_DIR="/opt/${APP_NAME}"
ENV_FILE="$WORK_DIR/migpt.env"
CONFIG_FILE="$WORK_DIR/config.ts"
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

fetch_template() {
  path="$1"
  out="$2"
  script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  if [ -f "$script_dir/$path" ]; then
    cp "$script_dir/$path" "$out"
  elif fetch "$BASE_URL/$path?ts=$(date +%s)" "$out" 2>/dev/null; then
    return 0
  elif fetch "$CN_BASE_URL/$path?ts=$(date +%s)" "$out" 2>/dev/null; then
    return 0
  else
    case "$path" in
      templates/env-noflash.example) write_builtin_env_template "$out" ;;
      templates/config-noflash.ts) write_builtin_config_template "$out" ;;
      *) die "下载失败: $path" ;;
    esac
  fi
}

write_builtin_env_template() {
  out="$1"
  cat > "$out" <<'EOF_ENV'
# ===== 免刷机账号配置 =====
# MI_USER：小米 ID，不是手机号或邮箱。
MI_USER=
# MI_PASS：小米账号密码；使用 passToken Cookie 时可留空。
MI_PASS=
# MI_PASS_TOKEN：浏览器已登录小米账号后的 passToken Cookie，可填 passToken 值或整段 Cookie。
MI_PASS_TOKEN=
# MI_DID：米家中的音箱名称或设备 DID。
MI_DID=
# XIAOAI_HARDWARE：音箱型号代码，例如 LX06、L05B、OH2P。
XIAOAI_HARDWARE=LX06

# ===== 语音触发 =====
# 问AI/问小爱：单次问答；开启AI/开启小爱：进入连续对话。
XIAOAI_CALL_KEYWORD=问AI
XIAOAI_WAKE_KEYWORD=开启AI
XIAOAI_EXIT_KEYWORD=关闭AI
XIAOAI_STREAM_RESPONSE=true
XIAOAI_DEBUG=false

# ===== 运行参数 =====
# 模型来源、API Key 和模型名请改 /opt/open-xiaoai-migpt/config.ts。
CONVERSATION_TURNS=6
LLM_TIMEOUT_MS=30000
OPENCLAW_TIMEOUT_MS=90000
OPENCLAW_TEST_TIMEOUT_MS=30000
OLLAMA_TIMEOUT_MS=90000
EOF_ENV
}

write_builtin_config_template() {
  out="$1"
  cat > "$out" <<'EOF_CONFIG'
// /opt/open-xiaoai-migpt/config.ts
//
// 旧刷机版教程里的主配置入口。免刷机版仍然主要改这个文件：
// - 小米账号、音箱名称、passToken 等基础信息由菜单写入 migpt.env
// - DeepSeek / OpenAI / Gemini / OpenClaw / Ollama 在这里配置
// - Docker 会把这个文件挂载为 MiGPT 需要的 /app/.migpt.js

const env = process.env;
const DEFAULT_SYSTEM_PROMPT =
  "你是运行在智能音箱上的语音助手。请使用中文直接回答，内容准确、自然、简短，避免 Markdown 和冗长列表。";

const CONFIG = {
  // 默认模型来源：deepseek / openai / gemini / openclaw / ollama
  defaultProvider: "deepseek",

  systemPrompt: DEFAULT_SYSTEM_PROMPT,

  providers: {
    // 说“切换deepseek”后使用
    deepseek: {
      baseURL: "https://api.deepseek.com/v1",
      apiKey: "",
      model: "deepseek-chat",
    },

    // 说“切换openai”后使用；兼容服务可把 baseURL 改成自己的 /v1 地址
    openai: {
      baseURL: "https://api.openai.com/v1",
      apiKey: "",
      model: "gpt-4o-mini",
    },

    // 说“切换gemini”或“切换谷歌”后使用
    gemini: {
      apiKey: "",
      model: "gemini-2.0-flash",
    },

    // 说“切换open”后使用；菜单 11 部署 Bridge 后填 http://OpenClaw设备IP:11435/v1
    openclaw: {
      baseURL: "",
      apiKey: "xiaoai-local",
      model: "open",
    },

    // 说“切换ollama”后使用
    ollama: {
      baseURL: "",
      apiKey: "ollama",
      model: "qwen3:4b",
    },
  },
};

function pick(value, fallback) {
  return value === undefined || value === null || value === "" ? fallback : value;
}
function choose(configValue, envValue, defaultValue) {
  if (envValue && (configValue === undefined || configValue === null || configValue === "" || configValue === defaultValue)) {
    return envValue;
  }
  return pick(configValue, defaultValue);
}
function envInt(name, fallback) {
  const n = Number.parseInt(env[name] || "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
function compactText(text) {
  return String(text || "").replace(/\s+/g, " ").trim();
}
function normalizeCommand(raw) {
  return String(raw || "")
    .normalize("NFKC")
    .replace(/\s+/g, "")
    .replace(/[，。！？；：、,.!?;:~`"'“”‘’（）()【】[\]{}<>《》]/g, "")
    .toLowerCase();
}
function keywords(value, defaults) {
  const items = `${value || ""},${defaults.join(",")}`
    .split(/[,，\s]+/)
    .map((item) => item.trim())
    .filter(Boolean);
  return [...new Set(items)];
}

const commandMap = {
  OH2P: { tts: [7, 3], wake: [7, 1] },
  LX06: { tts: [5, 1], wake: [5, 3] },
  S12: { tts: [5, 1], wake: [5, 3] },
  L15A: { tts: [7, 3], wake: [7, 1], playing: [3, 1, 1] },
  LX5A: { tts: [5, 1], wake: [5, 3] },
  LX05: { tts: [5, 1], wake: [5, 3], playing: [3, 1, 1] },
  X10A: { tts: [7, 3], wake: [7, 1] },
  L17A: { tts: [7, 3], wake: [7, 1] },
  L06A: { tts: [5, 1], wake: [5, 2] },
  LX01: { tts: [5, 1], wake: [5, 2] },
  L05B: { tts: [5, 3], wake: [5, 1] },
  L05C: { tts: [5, 3], wake: [5, 1] },
  L09A: { tts: [3, 1], wake: [3, 2] },
  LX04: { tts: [5, 1], wake: [5, 2] },
  ASX4B: { tts: [5, 3], wake: [5, 1] },
  X6A: { tts: [7, 3], wake: [7, 1] },
  X08E: { tts: [7, 3], wake: [7, 1] },
};

const hardware = (env.XIAOAI_HARDWARE || "LX06").toUpperCase();
const speakerCommands = commandMap[hardware] || commandMap.LX06;
const streamResponse = env.XIAOAI_STREAM_RESPONSE !== "false";
const callAIKeywords = keywords(env.XIAOAI_CALL_KEYWORD, ["问AI", "问 ai", "问小爱", "揾AI", "揾 ai", "文AI", "文 ai"]);
const wakeUpKeywords = keywords(env.XIAOAI_WAKE_KEYWORD, ["打开AI", "开启AI", "开启小爱"]);
const exitKeywords = keywords(env.XIAOAI_EXIT_KEYWORD, ["关闭AI", "退出AI", "关闭小爱"]);
const systemPrompt = choose(CONFIG.systemPrompt, env.XIAOAI_SYSTEM_PROMPT, DEFAULT_SYSTEM_PROMPT);
const conversationTurns = envInt("CONVERSATION_TURNS", 6);
const requestTimeoutMs = envInt("LLM_TIMEOUT_MS", 30000);
const openclawTimeoutMs = envInt("OPENCLAW_TIMEOUT_MS", 90000);
const openclawTestTimeoutMs = envInt("OPENCLAW_TEST_TIMEOUT_MS", 30000);
const ollamaTimeoutMs = envInt("OLLAMA_TIMEOUT_MS", 90000);

const providers = {
  deepseek: {
    label: "deepseek",
    kind: "openai",
    baseURL: choose(CONFIG.providers.deepseek.baseURL, env.DEEPSEEK_BASE_URL, "https://api.deepseek.com/v1"),
    apiKey: choose(CONFIG.providers.deepseek.apiKey, env.DEEPSEEK_API_KEY, ""),
    model: choose(CONFIG.providers.deepseek.model, env.DEEPSEEK_MODEL, "deepseek-chat"),
  },
  openai: {
    label: "openai",
    kind: "openai",
    baseURL: choose(CONFIG.providers.openai.baseURL, env.OPENAI_BASE_URL, "https://api.openai.com/v1"),
    apiKey: choose(CONFIG.providers.openai.apiKey, env.OPENAI_API_KEY, ""),
    model: choose(CONFIG.providers.openai.model, env.OPENAI_MODEL, "gpt-4o-mini"),
  },
  gemini: {
    label: "gemini",
    kind: "gemini",
    apiKey: choose(CONFIG.providers.gemini.apiKey, env.GEMINI_API_KEY, ""),
    model: choose(CONFIG.providers.gemini.model, env.GEMINI_MODEL, "gemini-2.0-flash"),
  },
  openclaw: {
    label: "open",
    kind: "openai",
    baseURL: choose(CONFIG.providers.openclaw.baseURL, env.OPENCLAW_BASE_URL, ""),
    apiKey: choose(CONFIG.providers.openclaw.apiKey, env.OPENCLAW_API_KEY, "xiaoai-local"),
    model: choose(CONFIG.providers.openclaw.model, env.OPENCLAW_DISPLAY_MODEL || env.OPENCLAW_MODEL, "open"),
  },
  ollama: {
    label: "ollama",
    kind: "openai",
    baseURL: choose(CONFIG.providers.ollama.baseURL, env.OLLAMA_BASE_URL, ""),
    apiKey: choose(CONFIG.providers.ollama.apiKey, env.OLLAMA_API_KEY, "ollama"),
    model: choose(CONFIG.providers.ollama.model, env.OLLAMA_MODEL, "qwen3:4b"),
  },
};

const llmState = globalThis.__xiaoai_llm_state || { provider: initialProvider(), messages: [] };
globalThis.__xiaoai_llm_state = llmState;

function normalizeProvider(value) {
  const cmd = normalizeCommand(value);
  if (["deepseek", "ds", "深度求索", "深度"].includes(cmd)) return "deepseek";
  if (["openai", "chatgpt", "gpt"].includes(cmd)) return "openai";
  if (["gemini", "google", "谷歌", "gmini"].includes(cmd)) return "gemini";
  if (["open", "openclaw", "opencall", "opencloud", "爪子", "本地模型", "本地ai"].includes(cmd)) return "openclaw";
  if (["ollama", "olama", "欧拉拉", "欧拉马", "奥拉马", "gemma", "伽马", "电脑", "本地电脑", "局域网模型"].includes(cmd)) return "ollama";
  return "";
}
function providerReady(provider) {
  const p = providers[provider];
  if (!p) return false;
  if (p.kind === "gemini") return !!p.apiKey;
  if (provider === "ollama") return !!p.baseURL;
  return !!p.baseURL && !!p.apiKey;
}
function providerName(provider) {
  return providers[provider]?.label || provider;
}
function initialProvider() {
  const configured = normalizeProvider(choose(CONFIG.defaultProvider, env.XIAOAI_DEFAULT_PROVIDER, "deepseek"));
  if (configured) return configured;
  if (providers.openclaw.baseURL) return "openclaw";
  if (providers.ollama.baseURL) return "ollama";
  if (providers.deepseek.apiKey) return "deepseek";
  if (providers.openai.apiKey) return "openai";
  if (providers.gemini.apiKey) return "gemini";
  return "openclaw";
}
function currentProvider() {
  if (!providers[llmState.provider]) llmState.provider = initialProvider();
  return llmState.provider;
}
function stripCallKeyword(text) {
  const raw = String(text || "").trim();
  const hit = callAIKeywords.find((keyword) => raw.startsWith(keyword));
  return hit ? raw.slice(hit.length).trim() : raw;
}
function historyMessages() {
  if (conversationTurns <= 0) return [];
  return llmState.messages.slice(-conversationTurns * 2);
}
function rememberTurn(user, assistant) {
  if (conversationTurns <= 0) return;
  llmState.messages.push({ role: "user", content: compactText(user) });
  llmState.messages.push({ role: "assistant", content: compactText(assistant) });
  llmState.messages = llmState.messages.slice(-conversationTurns * 2);
}
async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}
function chatEndpoint(baseURL) {
  return `${String(baseURL || "").replace(/\/+$/, "")}/chat/completions`;
}
async function callOpenAICompat(provider, userText, timeoutMs) {
  const p = providers[provider];
  const headers = { "content-type": "application/json" };
  if (p.apiKey) headers.authorization = `Bearer ${p.apiKey}`;
  const res = await fetchWithTimeout(
    chatEndpoint(p.baseURL),
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        model: p.model,
        messages: [{ role: "system", content: systemPrompt }, ...historyMessages(), { role: "user", content: userText }],
        temperature: 0.7,
      }),
    },
    timeoutMs
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.error) throw new Error(data?.error?.message || `HTTP ${res.status}`);
  const text = data?.choices?.[0]?.message?.content || data?.output_text || "";
  if (!text) throw new Error("模型返回为空");
  return compactText(text);
}
async function callGemini(userText, timeoutMs) {
  const p = providers.gemini;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(p.model)}:generateContent?key=${encodeURIComponent(p.apiKey)}`;
  const context = historyMessages().map((m) => `${m.role === "user" ? "用户" : "助手"}：${m.content}`).join("\n");
  const prompt = context ? `${systemPrompt}\n\n最近对话：\n${context}\n\n用户：${userText}` : `${systemPrompt}\n\n用户：${userText}`;
  const res = await fetchWithTimeout(
    url,
    { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: prompt }] }] }) },
    timeoutMs
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.error) throw new Error(data?.error?.message || `HTTP ${res.status}`);
  const text = data?.candidates?.[0]?.content?.parts?.map((part) => part.text || "").join("") || "";
  if (!text) throw new Error("模型返回为空");
  return compactText(text);
}
function timeoutForProvider(provider, testing = false) {
  if (provider === "openclaw") return testing ? openclawTestTimeoutMs : openclawTimeoutMs;
  if (provider === "ollama") return ollamaTimeoutMs;
  return testing ? Math.min(requestTimeoutMs, 15000) : requestTimeoutMs;
}
async function callLLM(provider, userText, testing = false) {
  if (!providerReady(provider)) throw new Error(`${providerName(provider)} 还没配置接口或 Key`);
  const timeoutMs = timeoutForProvider(provider, testing);
  if (providers[provider].kind === "gemini") return callGemini(userText, timeoutMs);
  return callOpenAICompat(provider, userText, timeoutMs);
}
function switchProvider(provider) {
  if (!providers[provider]) return `未知模型：${provider}`;
  llmState.provider = provider;
  llmState.messages = [];
  if (!providerReady(provider)) return `已切换到 ${providerName(provider)}，但还没配置接口或 Key。`;
  return `已切换到 ${providerName(provider)}。`;
}
function commandAction(text) {
  const cmd = normalizeCommand(text);
  if (["查看模型", "当前模型", "当前模式"].includes(cmd)) return { type: "current" };
  if (["清空上下文", "清除上下文", "清空对话"].includes(cmd)) return { type: "clear" };
  if (["测试模型", "测试当前模型"].includes(cmd)) return { type: "test" };
  if (cmd.startsWith("切换到")) return { type: "switch", provider: normalizeProvider(cmd.slice(3)) };
  if (cmd.startsWith("切换")) return { type: "switch", provider: normalizeProvider(cmd.slice(2)) };
  return null;
}

const providerCommands = {
  match: (msg) => !!commandAction(msg.text),
  run: async (msg) => {
    const action = commandAction(msg.text);
    if (!action) return undefined;
    if (action.type === "current") {
      const provider = currentProvider();
      const p = providers[provider];
      return { text: `当前模型是 ${providerName(provider)}，模型名 ${p.model}。` };
    }
    if (action.type === "clear") {
      llmState.messages = [];
      return { text: "已清空上下文。" };
    }
    if (action.type === "switch") {
      if (!action.provider) return { text: "没听清要切换到哪个模型。" };
      return { text: switchProvider(action.provider) };
    }
    if (action.type === "test") {
      const provider = currentProvider();
      const started = Date.now();
      try {
        const text = await callLLM(provider, "请只回答 OK", true);
        return { text: `连通正常：${providerName(provider)}，${Date.now() - started}毫秒，返回：${text}` };
      } catch (err) {
        return { text: `测试失败：${err?.message || "未知错误"}` };
      }
    }
    return undefined;
  },
};

export default {
  systemTemplate: `${systemPrompt}\n\n最近对话：\n{{messages}}`,
  bot: { name: "AI助手", profile: "简洁、可靠的语音助手" },
  master: { name: "用户", profile: "" },
  speaker: {
    userId: env.MI_USER,
    password: env.MI_PASS || "__cookie_login__",
    did: env.MI_DID,
    callAIKeywords,
    wakeUpKeywords,
    exitKeywords,
    onEnterAI: ["AI模式已开启"],
    onExitAI: ["AI模式已关闭"],
    onAIAsking: [],
    onAIReplied: [],
    onAIError: ["连接模型失败，请稍后再试"],
    commands: [providerCommands],
    askAI: async (msg) => {
      const userText = stripCallKeyword(msg.text);
      const provider = currentProvider();
      try {
        const answer = await callLLM(provider, userText);
        rememberTurn(userText, answer);
        return { text: answer };
      } catch (err) {
        return { text: `${providerName(provider)} 调用失败：${err?.message || "未知错误"}` };
      }
    },
    ttsCommand: speakerCommands.tts,
    wakeUpCommand: speakerCommands.wake,
    playingCommand: speakerCommands.playing,
    streamResponse,
    debug: env.XIAOAI_DEBUG === "true",
    enableTrace: env.XIAOAI_DEBUG === "true",
  },
};
EOF_CONFIG
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
    XIAOAI_CALL_KEYWORD|XIAOAI_WAKE_KEYWORD|XIAOAI_EXIT_KEYWORD|XIAOAI_STREAM_RESPONSE|XIAOAI_DEBUG|XIAOAI_SYSTEM_PROMPT|\
    XIAOAI_DEFAULT_PROVIDER|CONVERSATION_TURNS|LLM_TIMEOUT_MS|\
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
  case "$1" in
    http://api.deepseek.com|https://api.deepseek.com)
      printf '%s/v1' "$1"
      ;;
    http://api.deepseek.com/|https://api.deepseek.com/)
      printf '%sv1' "$1"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
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
  [ -n "$deepseek_base" ] || deepseek_base="https://api.deepseek.com/v1"
  deepseek_base=$(normalize_deepseek_base_url "$deepseek_base")
  [ -n "$deepseek_model" ] || deepseek_model="deepseek-chat"

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
    printf '%s\n' '# 问AI/问小爱：单次问答；开启AI/开启小爱：进入连续对话。'
  } >> "$tmp"
  append_env_line "XIAOAI_CALL_KEYWORD" "问AI" "$tmp"
  append_env_line "XIAOAI_WAKE_KEYWORD" "开启AI" "$tmp"
  append_env_line "XIAOAI_EXIT_KEYWORD" "关闭AI" "$tmp"
  append_env_line "XIAOAI_STREAM_RESPONSE" "true" "$tmp"
  append_env_line "XIAOAI_DEBUG" "false" "$tmp"
  if [ -n "$(env_value "XIAOAI_SYSTEM_PROMPT")" ]; then
    append_env_line "XIAOAI_SYSTEM_PROMPT" "" "$tmp"
  fi

  {
    printf '\n%s\n' '# ===== 运行参数 ====='
    printf '%s\n' '# 模型来源、API Key 和模型名请改 /opt/open-xiaoai-migpt/config.ts。'
  } >> "$tmp"
  append_env_line "CONVERSATION_TURNS" "6" "$tmp"
  append_env_line "LLM_TIMEOUT_MS" "30000" "$tmp"
  append_env_line "OPENCLAW_TIMEOUT_MS" "90000" "$tmp"
  append_env_line "OPENCLAW_TEST_TIMEOUT_MS" "30000" "$tmp"
  append_env_line "OLLAMA_TIMEOUT_MS" "90000" "$tmp"

  compat_header_written=0
  append_compat_env() {
    key="$1"
    value="$2"
    [ -n "$value" ] || return 0
    if [ "$compat_header_written" -eq 0 ]; then
      {
        printf '\n%s\n' '# ===== 兼容旧模型变量 ====='
        printf '%s\n' '# 新配置请优先改 /opt/open-xiaoai-migpt/config.ts；这里仅保留旧版本已经填写的值。'
      } >> "$tmp"
      compat_header_written=1
    fi
    append_env_value "$key" "$value" "$tmp"
  }
  append_compat_env "XIAOAI_DEFAULT_PROVIDER" "$(env_value "XIAOAI_DEFAULT_PROVIDER")"
  append_compat_env "DEEPSEEK_BASE_URL" "$(env_value "DEEPSEEK_BASE_URL")"
  append_compat_env "DEEPSEEK_API_KEY" "$(env_value "DEEPSEEK_API_KEY")"
  append_compat_env "DEEPSEEK_MODEL" "$(env_value "DEEPSEEK_MODEL")"
  append_compat_env "OPENAI_BASE_URL" "$(env_value "OPENAI_BASE_URL")"
  append_compat_env "OPENAI_API_KEY" "$(env_value "OPENAI_API_KEY")"
  append_compat_env "OPENAI_MODEL" "$(env_value "OPENAI_MODEL")"
  append_compat_env "GEMINI_API_KEY" "$(env_value "GEMINI_API_KEY")"
  append_compat_env "GEMINI_MODEL" "$(env_value "GEMINI_MODEL")"
  append_compat_env "OPENCLAW_BASE_URL" "$(env_value "OPENCLAW_BASE_URL")"
  append_compat_env "OPENCLAW_API_KEY" "$(env_value "OPENCLAW_API_KEY")"
  append_compat_env "OPENCLAW_DISPLAY_MODEL" "$(env_value "OPENCLAW_DISPLAY_MODEL")"
  append_compat_env "OPENCLAW_MODEL" "$(env_value "OPENCLAW_MODEL")"
  append_compat_env "OLLAMA_BASE_URL" "$(env_value "OLLAMA_BASE_URL")"
  append_compat_env "OLLAMA_API_KEY" "$(env_value "OLLAMA_API_KEY")"
  append_compat_env "OLLAMA_MODEL" "$(env_value "OLLAMA_MODEL")"

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
  if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$WORK_DIR/.env" ]; then
      cp "$WORK_DIR/.env" "$ENV_FILE"
    elif [ -f "$OLD_WORK_DIR/.env" ]; then
      cp "$OLD_WORK_DIR/.env" "$ENV_FILE"
      log "已从旧目录 $OLD_WORK_DIR/.env 迁移配置到 $ENV_FILE"
    else
      fetch_template "templates/env-noflash.example" "$ENV_FILE"
    fi
    chmod 600 "$ENV_FILE"
  fi
  normalize_env_file
  if [ ! -f "$CONFIG_FILE" ]; then
    fetch_template "templates/config-noflash.ts" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
  fi
  ln -sf "$(basename "$CONFIG_FILE")" "$WORK_DIR/.migpt.js" 2>/dev/null || true
  ln -sf "$(basename "$ENV_FILE")" "$WORK_DIR/.env" 2>/dev/null || true
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
  log "基础配置已保存到 $ENV_FILE"
  log "模型配置在 $CONFIG_FILE，按旧教程打开 config.ts 添加 API Key，然后运行菜单 3 重建服务。"
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
  --status) docker ps -a --filter "name=${CONTAINER_NAME}" ;;
  --logs) docker logs -f --tail=120 "$CONTAINER_NAME" ;;
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

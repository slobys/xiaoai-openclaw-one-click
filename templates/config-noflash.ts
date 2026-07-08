// /opt/open-xiaoai-migpt/config.ts
//
// 这是旧刷机版教程里的主配置入口。免刷机版仍然让你改这个文件：
// - 小米账号、音箱名称、passToken 等基础信息由菜单写入 migpt.env
// - DeepSeek / OpenAI / Gemini / OpenClaw / Ollama 在这里配置
// - 这个文件会被 Docker 挂载为 MiGPT 需要的 /app/.migpt.js

const env = process.env;
const DEFAULT_SYSTEM_PROMPT =
  "你是运行在智能音箱上的语音助手。请使用中文直接回答，内容准确、自然、简短，避免 Markdown 和冗长列表。";

const CONFIG = {
  // 默认模型来源：deepseek / openai / gemini / openclaw / ollama
  defaultProvider: "deepseek",

  // 智能音箱回答风格
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

function envInt(name, fallback) {
  const n = Number.parseInt(env[name] || "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function keywords(value, defaults) {
  const items = `${value || ""},${defaults.join(",")}`
    .split(/[,，\s]+/)
    .map((item) => item.trim())
    .filter(Boolean);
  return [...new Set(items)];
}

function normalizeCommand(raw) {
  return String(raw || "")
    .normalize("NFKC")
    .replace(/\s+/g, "")
    .replace(/[，。！？；：、,.!?;:~`"'“”‘’（）()【】[\]{}<>《》]/g, "")
    .toLowerCase();
}

function compactText(text) {
  return String(text || "").replace(/\s+/g, " ").trim();
}

const callAIKeywords = keywords(env.XIAOAI_CALL_KEYWORD, [
  "问AI",
  "问 ai",
  "问小爱",
  "揾AI",
  "揾 ai",
  "文AI",
  "文 ai",
]);
const wakeUpKeywords = keywords(env.XIAOAI_WAKE_KEYWORD, ["打开AI", "开启AI", "开启小爱"]);
const exitKeywords = keywords(env.XIAOAI_EXIT_KEYWORD, ["关闭AI", "退出AI", "关闭小爱"]);

const systemPrompt = choose(CONFIG.systemPrompt, env.XIAOAI_SYSTEM_PROMPT, DEFAULT_SYSTEM_PROMPT);
const conversationTurns = envInt("CONVERSATION_TURNS", 6);
const requestTimeoutMs = envInt("LLM_TIMEOUT_MS", 30000);
const openclawTimeoutMs = envInt("OPENCLAW_TIMEOUT_MS", 90000);
const openclawTestTimeoutMs = envInt("OPENCLAW_TEST_TIMEOUT_MS", 30000);
const ollamaTimeoutMs = envInt("OLLAMA_TIMEOUT_MS", 90000);

const openAIBaseURL = choose(CONFIG.providers.openai.baseURL, env.OPENAI_BASE_URL, "https://api.openai.com/v1");
const openAIModel = choose(CONFIG.providers.openai.model, env.OPENAI_MODEL, "gpt-4o-mini");
const looksLikeOpenClawCompat =
  /(^|\/)(open|openclaw)$/i.test(openAIModel) || /:11435(\/|$)/.test(openAIBaseURL);

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
    baseURL: openAIBaseURL,
    apiKey: choose(CONFIG.providers.openai.apiKey, env.OPENAI_API_KEY, ""),
    model: openAIModel,
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
    baseURL: choose(CONFIG.providers.openclaw.baseURL, env.OPENCLAW_BASE_URL || (looksLikeOpenClawCompat ? openAIBaseURL : ""), ""),
    apiKey: choose(
      CONFIG.providers.openclaw.apiKey,
      env.OPENCLAW_API_KEY || (looksLikeOpenClawCompat ? env.OPENAI_API_KEY : ""),
      "xiaoai-local"
    ),
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

const llmState = globalThis.__xiaoai_llm_state || {
  provider: initialProvider(),
  messages: [],
};
globalThis.__xiaoai_llm_state = llmState;
applyProviderToMiGPTEnv(llmState.provider);

function normalizeProvider(value) {
  const cmd = normalizeCommand(value);
  if (["deepseek", "ds", "深度求索", "深度"].includes(cmd)) return "deepseek";
  if (["openai", "chatgpt", "gpt"].includes(cmd)) return "openai";
  if (["gemini", "google", "谷歌", "gmini"].includes(cmd)) return "gemini";
  if (["open", "openclaw", "opencall", "opencloud", "爪子", "本地模型", "本地ai"].includes(cmd)) {
    return "openclaw";
  }
  if (["ollama", "olama", "欧拉拉", "欧拉马", "奥拉马", "gemma", "伽马", "电脑", "本地电脑", "局域网模型"].includes(cmd)) {
    return "ollama";
  }
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

function applyProviderToMiGPTEnv(provider) {
  const p = providers[provider];
  if (!p || p.kind !== "openai") return false;
  if (!p.baseURL || !p.model) return false;
  env.OPENAI_BASE_URL = p.baseURL;
  env.OPENAI_API_KEY = p.apiKey || "dummy";
  env.OPENAI_MODEL = p.model;
  return true;
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
  const messages = [
    { role: "system", content: systemPrompt },
    ...historyMessages(),
    { role: "user", content: userText },
  ];
  const headers = { "content-type": "application/json" };
  if (p.apiKey) headers.authorization = `Bearer ${p.apiKey}`;

  const res = await fetchWithTimeout(
    chatEndpoint(p.baseURL),
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        model: p.model,
        messages,
        temperature: 0.7,
      }),
    },
    timeoutMs
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.error) {
    throw new Error(data?.error?.message || `HTTP ${res.status}`);
  }
  const text = data?.choices?.[0]?.message?.content || data?.output_text || "";
  if (!text) throw new Error("模型返回为空");
  return compactText(text);
}

async function callGemini(userText, timeoutMs) {
  const p = providers.gemini;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
    p.model
  )}:generateContent?key=${encodeURIComponent(p.apiKey)}`;
  const context = historyMessages()
    .map((m) => `${m.role === "user" ? "用户" : "助手"}：${m.content}`)
    .join("\n");
  const prompt = context ? `${systemPrompt}\n\n最近对话：\n${context}\n\n用户：${userText}` : `${systemPrompt}\n\n用户：${userText}`;
  const res = await fetchWithTimeout(
    url,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: prompt }] }] }),
    },
    timeoutMs
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.error) {
    throw new Error(data?.error?.message || `HTTP ${res.status}`);
  }
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
  if (!providerReady(provider)) {
    throw new Error(`${providerName(provider)} 还没配置接口或 Key`);
  }
  const timeoutMs = timeoutForProvider(provider, testing);
  if (providers[provider].kind === "gemini") return callGemini(userText, timeoutMs);
  return callOpenAICompat(provider, userText, timeoutMs);
}

function switchProvider(provider) {
  if (!providers[provider]) return `未知模型：${provider}`;
  llmState.provider = provider;
  llmState.messages = [];
  applyProviderToMiGPTEnv(provider);
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

const fallbackQACommand = {
  match: (msg) => {
    const text = String(msg?.text || "").trim();
    if (!text) return false;
    return !commandAction(text);
  },
  run: async (msg) => {
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
    commands: [providerCommands, fallbackQACommand],
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

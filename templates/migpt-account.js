const env = process.env;

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
const commands = commandMap[hardware] || commandMap.LX06;
const streamResponse = env.XIAOAI_STREAM_RESPONSE !== "false";

function keywords(value, defaults) {
  const items = `${value || ""},${defaults.join(",")}`
    .split(/[,，\s]+/)
    .map((item) => item.trim())
    .filter(Boolean);
  return [...new Set(items)];
}

const callAIKeywords = keywords(env.XIAOAI_CALL_KEYWORD, ["问AI", "问小爱"]);
const wakeUpKeywords = keywords(env.XIAOAI_WAKE_KEYWORD, ["打开AI", "开启AI", "开启小爱"]);
const exitKeywords = keywords(env.XIAOAI_EXIT_KEYWORD, ["关闭AI", "退出AI", "关闭小爱"]);

export default {
  systemTemplate:
    "你是运行在智能音箱上的语音助手。请使用中文直接回答，内容准确、自然、简短，避免 Markdown 和冗长列表。\n\n最近对话：\n{{messages}}",
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
    ttsCommand: commands.tts,
    wakeUpCommand: commands.wake,
    playingCommand: commands.playing,
    streamResponse,
    debug: env.XIAOAI_DEBUG === "true",
    enableTrace: env.XIAOAI_DEBUG === "true",
  },
};

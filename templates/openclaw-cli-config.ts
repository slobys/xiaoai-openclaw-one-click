// Experimental host-mode adapter.
// This is for running the MiGPT server on the same host where the openclaw CLI is installed.
// Docker mode should use the upstream slobys/xiaoai config.ts instead.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { OpenXiaoAIConfig } from "./migpt/xiaoai.js";

const execFileAsync = promisify(execFile);
const systemPrompt =
  "你是运行在小爱音箱上的语音助手，由 OpenClaw 调用大模型驱动。回答要短、口语化，不要 markdown。";

async function askOpenClaw(prompt: string) {
  const model = process.env.OPENCLAW_MODEL || "openai/gpt-5.4";
  const { stdout } = await execFileAsync(
    "openclaw",
    ["infer", "model", "run", "--json", "--model", model, "--prompt", prompt],
    { timeout: Number(process.env.OPENCLAW_TIMEOUT_MS || 30000) }
  );
  const data = JSON.parse(stdout);
  return String(data.text || data.output || data.response || "").trim();
}

export const kOpenXiaoAIConfig: OpenXiaoAIConfig = {
  callAIKeywords: ["", "开", "切", "设", "关", "查", "停", "闭", "你", "我", "请", "帮", "问"],
  prompt: {
    system: systemPrompt,
  },
  async onMessage(engine, { text }) {
    const raw = String(text || "").trim();
    if (!raw) return { handled: true };
    if (raw === "停止" || raw === "闭嘴") {
      await engine.speaker.abortXiaoAI?.();
      return { text: "好的。" };
    }
    const answer = await askOpenClaw(`${systemPrompt}\n\n用户：${raw}`);
    return { text: answer || "我没听清，你能再说一次吗？" };
  },
};

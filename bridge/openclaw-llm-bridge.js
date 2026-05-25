#!/usr/bin/env node
"use strict";

const http = require("http");
const { execFile } = require("child_process");

const host = process.env.OPENCLAW_BRIDGE_HOST || "0.0.0.0";
const port = Number(process.env.OPENCLAW_BRIDGE_PORT || 11435);
const model = process.env.OPENCLAW_MODEL || "";
const bridgeMode = (process.env.OPENCLAW_BRIDGE_MODE || "agent").toLowerCase();
const agent = process.env.OPENCLAW_AGENT || "main";
const sessionKey = process.env.OPENCLAW_SESSION_KEY || `agent:${agent}:xiaoai`;
const thinking = process.env.OPENCLAW_THINKING || "";
const respectRequestModel = process.env.OPENCLAW_RESPECT_REQUEST_MODEL === "1";
const token = process.env.OPENCLAW_BRIDGE_TOKEN || "";
const timeoutMs = Number(process.env.OPENCLAW_TIMEOUT_MS || 60000);
const openclawBin = process.env.OPENCLAW_BIN || "openclaw";

function normalizeModelName(name, fallback) {
  const raw = String(name || "").trim();
  const lowered = raw.toLowerCase();
  if (!raw || lowered === "open" || lowered === "openclaw") return fallback || "";
  return raw;
}

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1024 * 1024) {
        reject(new Error("payload_too_large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error("invalid_json"));
      }
    });
    req.on("error", reject);
  });
}

function authorized(req) {
  if (!token) return true;
  const auth = req.headers.authorization || "";
  return auth === `Bearer ${token}`;
}

function contentToText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === "string") return part;
        if (part && typeof part.text === "string") return part.text;
        if (part && typeof part.content === "string") return part.content;
        return "";
      })
      .filter(Boolean)
      .join("\n");
  }
  return "";
}

function messagesToPrompt(messages) {
  return (messages || [])
    .map((m) => {
      const role = m.role || "user";
      return `${role}: ${contentToText(m.content)}`;
    })
    .filter((line) => line.trim() !== ":")
    .join("\n");
}

function responsesInputToPrompt(input) {
  if (typeof input === "string") return input;
  if (Array.isArray(input)) return messagesToPrompt(input);
  return String(input || "");
}

function extractAgentText(data) {
  const payloads = data && data.result && Array.isArray(data.result.payloads) ? data.result.payloads : [];
  const joined = payloads
    .map((p) => (p && typeof p.text === "string" ? p.text : ""))
    .filter(Boolean)
    .join("\n")
    .trim();
  if (joined) return joined;
  return String(
    data?.result?.finalAssistantVisibleText ||
      data?.result?.finalAssistantRawText ||
      data?.text ||
      data?.output ||
      data?.response ||
      ""
  ).trim();
}

function runOpenClawAgent(prompt, requestedModel) {
  const selectedModel = normalizeModelName(respectRequestModel && requestedModel ? requestedModel : model, "");
  const args = [
    "agent",
    "--json",
    "--agent",
    agent,
    "--session-key",
    sessionKey,
    "--message",
    prompt,
    "--timeout",
    String(Math.max(1, Math.ceil(timeoutMs / 1000))),
  ];
  if (selectedModel) args.push("--model", selectedModel);
  if (thinking) args.push("--thinking", thinking);

  return new Promise((resolve, reject) => {
    execFile(openclawBin, args, { timeout: timeoutMs + 5000, maxBuffer: 2 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        err.message = `${err.message}${stderr ? `\n${stderr}` : ""}`;
        reject(err);
        return;
      }
      try {
        const data = JSON.parse(stdout || "{}");
        const text = extractAgentText(data);
        if (text) resolve(text);
        else reject(new Error("openclaw_agent_empty_response"));
      } catch {
        resolve(String(stdout || "").trim());
      }
    });
  });
}

function runOpenClawInfer(prompt, requestedModel) {
  const selectedModel = normalizeModelName(respectRequestModel && requestedModel ? requestedModel : model, "openai/gpt-5.4");
  return new Promise((resolve, reject) => {
    execFile(
      openclawBin,
      ["infer", "model", "run", "--json", "--model", selectedModel, "--prompt", prompt],
      { timeout: timeoutMs, maxBuffer: 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          err.message = `${err.message}${stderr ? `\n${stderr}` : ""}`;
          reject(err);
          return;
        }
        try {
          const data = JSON.parse(stdout || "{}");
          resolve(String(data.text || data.output || data.response || data.message || "").trim());
        } catch {
          resolve(String(stdout || "").trim());
        }
      }
    );
  });
}

function runOpenClaw(prompt, requestedModel) {
  if (bridgeMode === "infer" || bridgeMode === "model") return runOpenClawInfer(prompt, requestedModel);
  return runOpenClawAgent(prompt, requestedModel);
}

async function handleChat(req, res) {
  const body = await readJson(req);
  const prompt = messagesToPrompt(body.messages);
  const text = await runOpenClaw(prompt, body.model);
  send(res, 200, {
    id: `chatcmpl_${Date.now()}`,
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model: model || "openclaw-default",
    choices: [{ index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" }],
  });
}

async function handleResponses(req, res) {
  const body = await readJson(req);
  const prompt = responsesInputToPrompt(body.input);
  const text = await runOpenClaw(prompt, body.model);
  send(res, 200, {
    id: `resp_${Date.now()}`,
    object: "response",
    created_at: Math.floor(Date.now() / 1000),
    model: model || "openclaw-default",
    output_text: text,
    output: [
      {
        type: "message",
        role: "assistant",
        content: [{ type: "output_text", text }],
      },
    ],
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") {
      send(res, 200, { ok: true, mode: bridgeMode, model: model || "openclaw-default", agent, sessionKey });
      return;
    }
    if (!authorized(req)) {
      send(res, 401, { error: { message: "unauthorized" } });
      return;
    }
    if (req.method === "POST" && req.url === "/v1/chat/completions") {
      await handleChat(req, res);
      return;
    }
    if (req.method === "POST" && req.url === "/v1/responses") {
      await handleResponses(req, res);
      return;
    }
    send(res, 404, { error: { message: "not_found" } });
  } catch (err) {
    send(res, 500, { error: { message: String(err && err.message ? err.message : err) } });
  }
});

server.listen(port, host, () => {
  console.log(`openclaw-llm-bridge listening on http://${host}:${port}/v1 model=${model}`);
});

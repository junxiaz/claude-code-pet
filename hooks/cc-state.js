#!/usr/bin/env node
// 记录“每个 session”的状态 + 本轮计时，供悬浮 Pet 读取（按 session_id 分文件）。
// 写 {state, ts, sid, startTs, dur}；dur 仅在 done 时给出（本轮用时，毫秒）。
// 名字/tty 由 Pet 侧用 `claude agents --json` + 终端标题解析。
// 用法: node cc-state.js <EventName>   （hook JSON 从 stdin 传入，含 session_id / message）
const fs = require("fs");
const path = require("path");
const os = require("os");

const DIR = path.join(os.homedir(), ".claude", "hooks", "cc-state.d");

const MAP = {
  UserPromptSubmit: "working",
  PreToolUse: "working",
  PostToolUse: "working", // 工具执行完 → 回到 working
  Notification: "needs",  // 下面按 message 细分：权限类=needs，等待输入类=waiting
  Stop: "done",
  SessionStart: "idle",
  SessionEnd: "__end__",
};

const event = process.argv[2];
let state = MAP[event];
if (!state) process.exit(0);

let data = {};
try {
  data = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
} catch {}

// Notification 既用于“需要权限”也用于“等待你的输入”。
// 只有真正的权限/批准类通知才算 needs(⏰)；其余(如等待输入)视为 waiting(💬)。
if (event === "Notification") {
  const msg = String(data.message || "").toLowerCase();
  state = /permission|approve|approval|confirm|allow|grant|authoriz/.test(msg) ? "needs" : "waiting";
}

const sid = (data.session_id || "default").replace(/[^\w.-]/g, "_");
const now = Date.now();

try {
  fs.mkdirSync(DIR, { recursive: true });
  const file = path.join(DIR, sid + ".json");

  if (state === "__end__") {
    fs.rmSync(file, { force: true });
    process.exit(0);
  }

  // 读旧记录以延续“本轮开始时间” startTs
  let prev = {};
  try { prev = JSON.parse(fs.readFileSync(file, "utf8")); } catch {}
  let startTs = prev.startTs;
  if (event === "UserPromptSubmit") startTs = now;    // 新一轮开始计时
  if (state === "working" && !startTs) startTs = now; // 兜底

  const rec = { state, ts: now, sid };
  if (startTs) rec.startTs = startTs;
  if (state === "done" && startTs) rec.dur = now - startTs; // 本轮用时(ms)

  fs.writeFileSync(file, JSON.stringify(rec));
} catch {}
process.exit(0);

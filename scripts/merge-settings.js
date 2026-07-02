#!/usr/bin/env node
// 把 Pet 需要的 hook 条目【合并】进 ~/.claude/settings.json，不覆盖用户已有配置。
// 幂等：重复运行不会产生重复条目。
// 用法:
//   node merge-settings.js          安装（写入 hook 条目）
//   node merge-settings.js --remove 卸载（移除本工具写入的 hook 条目）
const fs = require("fs");
const path = require("path");
const os = require("os");

const SETTINGS = path.join(os.homedir(), ".claude", "settings.json");
const HOOKS = path.join(os.homedir(), ".claude", "hooks");
const remove = process.argv.includes("--remove");

// cc-state.js 注册到这些事件；cc-autoallow.js 只注册到 PreToolUse。
const STATE_EVENTS = [
  "UserPromptSubmit", "PreToolUse", "PostToolUse",
  "Notification", "Stop", "SessionStart", "SessionEnd",
];
const stateCmd = (evt) => `node ${JSON.stringify(path.join(HOOKS, "cc-state.js"))} ${evt}`;
const allowCmd = `node ${JSON.stringify(path.join(HOOKS, "cc-autoallow.js"))}`;

// 判定“这是本工具写入的条目”：命令里含我们的脚本文件名。
const isOurs = (cmd) =>
  typeof cmd === "string" && (cmd.includes("cc-state.js") || cmd.includes("cc-autoallow.js"));

let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(SETTINGS, "utf8") || "{}"); } catch {}
cfg.hooks = cfg.hooks || {};

function entriesFor(evt) {
  cfg.hooks[evt] = Array.isArray(cfg.hooks[evt]) ? cfg.hooks[evt] : [];
  return cfg.hooks[evt];
}
function hasCmd(arr, needle) {
  return arr.some((e) => (e.hooks || []).some((h) => (h.command || "").includes(needle)));
}
function stripOurs(arr) {
  // 删掉“只含我们脚本”的整条；对混合条目则只摘掉我们的那条 hook。
  const kept = [];
  for (const e of arr) {
    const hooks = (e.hooks || []).filter((h) => !isOurs(h.command));
    if (hooks.length > 0) { e.hooks = hooks; kept.push(e); }
  }
  return kept;
}

if (remove) {
  for (const evt of Object.keys(cfg.hooks)) {
    cfg.hooks[evt] = stripOurs(cfg.hooks[evt]);
    if (cfg.hooks[evt].length === 0) delete cfg.hooks[evt];
  }
  console.log("已移除 Pet 的 hook 条目");
} else {
  // cc-state.js：每个事件确保存在一条
  for (const evt of STATE_EVENTS) {
    const arr = entriesFor(evt);
    if (!hasCmd(arr, "cc-state.js")) {
      arr.push({ hooks: [{ type: "command", command: stateCmd(evt) }] });
    }
  }
  // cc-autoallow.js：PreToolUse 里确保存在一条（限定只读工具）
  const pre = entriesFor("PreToolUse");
  if (!hasCmd(pre, "cc-autoallow.js")) {
    pre.push({ matcher: "Read|Glob|Grep", hooks: [{ type: "command", command: allowCmd }] });
  }
  console.log("已写入 Pet 的 hook 条目");
}

fs.mkdirSync(path.dirname(SETTINGS), { recursive: true });
fs.writeFileSync(SETTINGS, JSON.stringify(cfg, null, 2) + "\n");

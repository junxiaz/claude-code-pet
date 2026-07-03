#!/usr/bin/env node
// 汇集“当前开着终端的 Claude 会话”，输出 JSON 供悬浮 Pet 使用。
// macOS : 只包含有真实 tty 的会话（关掉终端的会话 tty=?? 会被过滤），
//         标题同时从 iTerm2 与 Terminal.app 读取（谁在运行读谁）。
// Windows: 只包含进程仍存活的会话；名字取 `claude agents` 里的会话名；
//         tty 字段放 pid，供挂件点击时聚焦承载它的终端窗口（win-focus.ps1）。
// 输出: [{sid, name, tty, state, ts}]，按状态优先级排序。
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const os = require("os");

const IS_WIN = process.platform === "win32";

// claude 路径：优先取调用方传入的 argv[2]，否则按常见位置探测，最后退到 PATH。
const CLAUDE = process.argv[2] || (() => {
  const cands = IS_WIN
    ? [
        path.join(os.homedir(), "AppData", "Roaming", "npm", "claude.cmd"),
        path.join(os.homedir(), ".local", "bin", "claude.exe"),
      ]
    : [
        path.join(os.homedir(), ".npm-global/bin/claude"),
        path.join(os.homedir(), ".claude/local/claude"),
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
      ];
  for (const p of cands) { try { if (fs.existsSync(p)) return p; } catch {} }
  return "claude";
})();
const DIR = path.join(os.homedir(), ".claude", "hooks", "cc-state.d");
const DONE_LINGER = 6000;      // “完成”✅ 显示时长，之后转“等你回话”
const NEEDS_TTL = 120000;      // “需审批”⏰ 有效期：超过则视为残留，转空闲
const WAITING_TTL = 5 * 60 * 1000; // “等你回话”💬 有效期：晾太久则转空闲
const WORKING_TTL = 45000;     // “工作中”🌀 有效期：超过没刷新则视为空闲
const STALE = 15 * 60 * 1000;
const NAME_MAX = 22;
const PRIORITY = { needs: 5, waiting: 4, working: 3, done: 2, idle: 1 };

function sh(cmd) {
  try {
    return execSync(cmd, {
      encoding: "utf8", timeout: 5000, windowsHide: true,
      stdio: ["ignore", "pipe", "ignore"], // 静默 stderr，替代 2>/dev/null（cmd.exe 不认）
    });
  } catch { return ""; }
}

// 路径 → 命令行参数：Windows 上不能用 JSON.stringify（反斜杠会被转义成 \\）
const q = (p) => (IS_WIN ? `"${p}"` : JSON.stringify(p));

function pretty(title) {
  if (!title) return null;
  let n = title.replace(/\s*\([^)]*\)\s*$/, "");   // 去尾部 (claude)/(caffeinate)
  n = n.replace(/^[^\p{L}\p{N}]+/u, "");            // 去开头 spinner/符号/空格
  n = n.trim();
  if ([...n].length > NAME_MAX) n = [...n].slice(0, NAME_MAX).join("") + "…";
  return n || null;
}

function fmtDur(ms) {
  const s = Math.round(ms / 1000);
  if (s < 60) return s + "s";
  return Math.floor(s / 60) + "m" + String(s % 60).padStart(2, "0") + "s";
}

// 返回 {state, dur?}；dur 仅在 done 时可能带上（本轮用时 ms）。
function stateOf(sid, status) {
  try {
    const obj = JSON.parse(fs.readFileSync(path.join(DIR, sid + ".json"), "utf8"));
    const age = Date.now() - obj.ts;
    const st = obj.state;
    // 生命周期：working → done(6s) → waiting(≤5min) → idle；needs 独立超期转空闲
    if (st === "needs")   return { state: age < NEEDS_TTL   ? "needs"   : "idle" };
    if (st === "done")    return { state: age < DONE_LINGER ? "done"    : "waiting", dur: obj.dur };
    if (st === "waiting") return { state: age < WAITING_TTL ? "waiting" : "idle" };
    if (st === "working") return { state: age < WORKING_TTL ? "working" : "idle" };
    if (st === "idle" && age <= STALE) return { state: "idle" };
  } catch {}
  return { state: status === "busy" ? "working" : "idle" };
}

let sessions = [];
try { sessions = JSON.parse(sh(`${q(CLAUDE)} agents --json`) || "[]"); } catch {}

const out = [];

if (IS_WIN) {
  for (const e of sessions) {
    if (!e.pid) continue;
    try { process.kill(e.pid, 0); } catch { continue; } // 进程没了 → 会话已关闭
    let name = pretty(e.name) || "claude";
    const r = stateOf(e.sessionId, e.status);
    if (r.state === "done" && r.dur) name = name + " · " + fmtDur(r.dur); // 完成时附上本轮用时
    out.push({ sid: e.sessionId, name, tty: String(e.pid), state: r.state, ts: e.startedAt || 0 });
  }
} else {
  // pid -> tty
  const pids = sessions.map((s) => s.pid).filter(Boolean);
  const pidTty = {};
  if (pids.length) {
    sh(`/bin/ps -o pid=,tty= -p ${pids.join(",")}`).split("\n").forEach((line) => {
      const m = line.match(/^\s*(\d+)\s+(\S+)/);
      if (m) pidTty[m[1]] = m[2];
    });
  }

  // 终端 tty -> 标题（iTerm2 + Terminal.app）
  const ttyTitle = {};
  const scriptFile = path.join(DIR, "..", "terminal-titles.applescript");
  const titleOut = sh(`/usr/bin/osascript ${JSON.stringify(scriptFile)}`);
  titleOut.split("\n").forEach((line) => {
    const i = line.indexOf("@@@");
    if (i > 0) {
      let dev = line.slice(0, i);                       // 形如 /dev/ttys003
      const tty = dev.replace(/^\/dev\//, "");
      ttyTitle[tty] = line.slice(i + 3);
    }
  });

  for (const e of sessions) {
    const tty = pidTty[String(e.pid)] || "";
    if (!tty || tty === "??") continue; // 只保留有真实终端的会话
    let name = pretty(ttyTitle[tty]) || e.name || "claude";
    const r = stateOf(e.sessionId, e.status);
    if (r.state === "done" && r.dur) name = name + " · " + fmtDur(r.dur); // 完成时附上本轮用时
    out.push({ sid: e.sessionId, name, tty, state: r.state, ts: e.startedAt || 0 });
  }
}

out.sort((a, b) => (PRIORITY[b.state] || 0) - (PRIORITY[a.state] || 0) || b.ts - a.ts);

process.stdout.write(JSON.stringify(out));

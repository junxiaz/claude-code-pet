#!/usr/bin/env node
// C 策略：只读类工具(Read/Glob/Grep)自动放行，消掉无谓确认；
// 风险操作(Bash/Write/Edit/…)不在名单内 → 照常弹权限提示，交你人工把关(配合悬浮 Pet 的 needs⏰ 秒跳)。
// PreToolUse hook：命中名单则输出 permissionDecision=allow 跳过提示；否则什么都不做(交回默认流程)。
const fs = require("fs");

const ALLOW = new Set(["Read", "Glob", "Grep"]);

let data = {};
try {
  data = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
} catch {}

const tool = data.tool_name || "";
if (ALLOW.has(tool)) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "cc-autoallow: read-only tool",
      },
    })
  );
}
process.exit(0);

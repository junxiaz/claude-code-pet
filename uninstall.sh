#!/usr/bin/env bash
# Claude Code 悬浮 Pet —— 卸载
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.claude/hooks"
HSDIR="$HOME/.hammerspoon"

say() { printf '\033[1;36m› %s\033[0m\n' "$1"; }
ok()  { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

say "移除 settings.json 中的 hook 条目（保留你自己的配置）"
node "$REPO/scripts/merge-settings.js" --remove && ok "配置已清理"

say "删除已安装文件"
rm -f "$HOOKS/cc-state.js" "$HOOKS/cc-sessions.js" "$HOOKS/cc-autoallow.js" \
      "$HOOKS/terminal-titles.applescript" "$HOOKS/focus-tty.applescript" "$HOOKS/open-agents.applescript"
rm -f "$HSDIR/cc-pet.lua"
rm -rf "$HOOKS/cc-state.d"
ok "文件已删除"

say "清理 init.lua 里的加载行"
INIT="$HSDIR/init.lua"
if [ -f "$INIT" ]; then
  # 删掉包含 require("cc-pet") 的那一行
  grep -v 'require("cc-pet")' "$INIT" > "$INIT.tmp" && mv "$INIT.tmp" "$INIT"
  ok "已从 init.lua 移除加载行"
fi

command -v hs >/dev/null 2>&1 && hs -c 'hs.reload()' >/dev/null 2>&1 || true
ok "卸载完成。挂件已停止（如仍显示，请 Reload Hammerspoon 或重启它）"

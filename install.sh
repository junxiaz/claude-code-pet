#!/usr/bin/env bash
# Claude Code 悬浮 Pet —— 一键安装
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.claude/hooks"
HSDIR="$HOME/.hammerspoon"

say()  { printf '\033[1;36m› %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$1"; exit 1; }

say "检查依赖…"
[ "$(uname)" = "Darwin" ] || die "此脚本仅用于 macOS;Windows 请运行 install.ps1"
command -v node >/dev/null 2>&1 || die "未找到 node，请先安装 Node.js（brew install node）"
[ -d "/Applications/Hammerspoon.app" ] || warn "未检测到 Hammerspoon.app，请从 https://www.hammerspoon.org 安装"
if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.npm-global/bin/claude" ] || [ -x "$HOME/.claude/local/claude" ]; then
  ok "找到 claude CLI"
else
  warn "未找到 claude CLI（需支持 \`claude agents --json\`）"
fi
if [ -d "/Applications/iTerm.app" ]; then ok "终端: iTerm2"; else ok "终端: Terminal.app（无 iTerm2，跳转/取标题将用 Terminal.app）"; fi

say "安装 hook 脚本 → $HOOKS"
mkdir -p "$HOOKS"
cp "$REPO/hooks/"*.js "$HOOKS/"
cp "$REPO/hooks/"*.applescript "$HOOKS/"
ok "hooks 已复制"

say "安装挂件模块 → $HSDIR/cc-pet.lua"
mkdir -p "$HSDIR"
cp "$REPO/pet/cc-pet.lua" "$HSDIR/cc-pet.lua"
INIT="$HSDIR/init.lua"
touch "$INIT"
if grep -q 'require("cc-pet")' "$INIT" 2>/dev/null; then
  ok "init.lua 已含加载行"
else
  printf '\nrequire("cc-pet") -- Claude Code 悬浮 Pet\n' >> "$INIT"
  ok "已向 init.lua 追加 require(\"cc-pet\")"
fi

say "合并 hook 配置 → $HOME/.claude/settings.json（自动备份）"
SET="$HOME/.claude/settings.json"
[ -f "$SET" ] && cp "$SET" "$SET.bak.$(date +%s)" && ok "已备份原 settings.json"
node "$REPO/scripts/merge-settings.js"
ok "配置已合并"

say "重载 Hammerspoon…"
if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.reload()' >/dev/null 2>&1 && ok "已 reload" || warn "reload 失败，请手动在 Hammerspoon 菜单 Reload Config"
else
  warn "未安装 hs 命令行。请打开 Hammerspoon → 菜单 Reload Config（或在 Hammerspoon 控制台运行 hs.ipc.cliInstall() 后即可用 hs 命令）"
fi

cat <<'EOF'

──────────────────────────────────────────────
安装完成 🐾
  · 打开 Hammerspoon，若首次需在「系统设置 → 隐私与安全性 → 辅助功能」勾选 Hammerspoon（拖动挂件需要）
  · 右下角出现挂件后，随便开几个跑着 claude 的终端即可看到状态
  · 自定义 node/claude 路径：新建 ~/.hammerspoon/cc-pet.json  例如 {"node":"/opt/homebrew/bin/node","claude":"/opt/homebrew/bin/claude"}
  · 卸载：bash uninstall.sh
──────────────────────────────────────────────
EOF

# Claude Code 悬浮 Pet 🐾

**中文** · [English](README.en.md)

![platform](https://img.shields.io/badge/platform-macOS-black)
![license](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks-8A5CF6)
![Hammerspoon](https://img.shields.io/badge/Hammerspoon-Lua-blue)

给 [Claude Code](https://claude.com/claude-code) 做的 macOS 桌面悬浮状态挂件,灵感来自 OpenAI Codex 的 "Pets" —— 在屏幕角落实时显示每个会话的状态,点一下就跳到对应终端。

![states](docs/demo.gif)

## 功能

- **多会话总览**:所有开着终端的 Claude 会话列在一个小面板里,只显示活着的(关掉的会自动消失)
- **五态轻量动画**
  - 🌀 `working` 旋转 —— 正在干活
  - ⏰ `needs` 红色脉动 —— 等你审批权限
  - 💬 `waiting` 蓝色呼吸 —— 干完了在等你回话
  - ✅ `done` 蹦跳 —— 刚完成一轮
  - 😴 `idle` 微呼吸 —— 空闲
- **点击跳转**:点某个会话行 → 自动切到它所在的终端 tab
- **可拖动**,位置记忆
- **少打扰的审批**:只读工具(Read/Glob/Grep)自动放行,只有风险操作才弹提示并在挂件上红色高亮提醒你

## 前置条件

| 依赖 | 说明 |
|---|---|
| macOS | 仅支持 macOS |
| [Hammerspoon](https://www.hammerspoon.org) | 悬浮窗载体,免费开源 |
| [Node.js](https://nodejs.org) | 跑 hook / 汇集脚本 |
| Claude Code CLI | 需支持 `claude agents --json` |
| 终端 | **iTerm2** 或系统 **Terminal.app** 均可(跳转/取标题两边都适配) |

## 安装

```bash
git clone https://github.com/junxiaz/claude-code-pet.git
cd claude-code-pet
bash install.sh
```

安装脚本会:
1. 检查依赖
2. 把 hook 脚本复制到 `~/.claude/hooks/`
3. 把挂件模块放到 `~/.hammerspoon/cc-pet.lua`,并在你的 `~/.hammerspoon/init.lua` 追加一行 `require("cc-pet")`
4. **合并**(不覆盖)必要的 hook 条目进 `~/.claude/settings.json`(会先自动备份)
5. Reload Hammerspoon

装完后:
- 打开 Hammerspoon,首次需到 **系统设置 → 隐私与安全性 → 辅助功能** 勾选 Hammerspoon(拖动挂件用)
- 开几个跑着 `claude` 的终端,右下角就会看到它们的状态

## 卸载

```bash
bash uninstall.sh
```

会移除写入的 hook 条目(保留你自己的配置)、删除已安装文件、清理 `init.lua` 里的加载行。

## 自定义

新建 `~/.hammerspoon/cc-pet.json` 覆盖自动探测的路径:

```json
{ "node": "/opt/homebrew/bin/node", "claude": "/opt/homebrew/bin/claude" }
```

挂件外观常量在 `~/.hammerspoon/cc-pet.lua` 顶部(`ICON` / `PANEL_W` / `CHIP_H` / `MAX_CHIPS`);
动画速度/幅度在 `animate()` 里(旋转 `t*200`、脉动 `t*3.2`、蹦跳高度 `12` 等)。

## 工作原理

```
Claude Code 事件 ──hook──> cc-state.js ──写──> ~/.claude/hooks/cc-state.d/<sid>.json
                                                        │
Hammerspoon 每 2s ──> cc-sessions.js ──汇集──> ┤ claude agents --json (有哪些会话)
  (cc-pet.lua)                                 ┤ ps (pid→tty)
                                               └ terminal-titles.applescript (tty→标题)
                          │
                          └─> 输出 [{sid,name,tty,state}] ──> 挂件渲染 + 逐帧动画
```

- **状态写入**:`cc-state.js` 挂在 7 个 Claude Code 事件上,把每个会话的状态写成小 JSON。
- **状态聚合**:`cc-sessions.js` 把"活着的会话 + tty + 终端标题 + 状态"合成一份列表,带 TTL(超时的状态自动降级,避免卡住)。
- **自动放行**:`cc-autoallow.js` 是 `PreToolUse` hook,只读工具直接返回 `permissionDecision: allow`。
- **渲染/动画分离**:数据轮询只在状态变化时重建面板;独立的 14fps 定时器只改元素属性做动画,平滑且省电。

## 安全说明

`cc-autoallow.js` 会让 `Read` / `Glob` / `Grep` **自动通过权限确认**(它们不改文件、不执行命令)。
`Bash` / `Write` / `Edit` 等有副作用的操作**不在名单内**,照常需要你确认。
想关掉自动放行:编辑 `~/.claude/settings.json`,删掉 `matcher: "Read|Glob|Grep"` 那条 PreToolUse hook 即可。

## 许可

MIT

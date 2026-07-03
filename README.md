# Claude Code 悬浮 Pet 🐾

**中文** · [English](README.en.md)

![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-black)
![license](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks-8A5CF6)
![Hammerspoon](https://img.shields.io/badge/Hammerspoon-Lua-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-WPF-5391FE)

给 [Claude Code](https://claude.com/claude-code) 做的桌面悬浮状态挂件(macOS / Windows),灵感来自 OpenAI Codex 的 "Pets" —— 在屏幕角落实时显示每个会话的状态,点一下就跳到对应终端。

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

| 依赖 | macOS | Windows |
|---|---|---|
| 悬浮窗载体 | [Hammerspoon](https://www.hammerspoon.org)(免费开源) | 系统自带 PowerShell 5.1 + WPF,**零额外依赖** |
| [Node.js](https://nodejs.org) | 需要(跑 hook / 汇集脚本) | 需要 |
| Claude Code CLI | 需支持 `claude agents --json` | 同左 |
| 终端 | **iTerm2** 或系统 **Terminal.app**(跳转/取标题两边都适配) | **Windows Terminal**(推荐)或任意控制台窗口 |

## 安装

### macOS

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

### Windows

```powershell
git clone https://github.com/junxiaz/claude-code-pet.git
cd claude-code-pet
powershell -ExecutionPolicy Bypass -File install.ps1
```

安装脚本会:
1. 检查依赖(node / claude / Windows Terminal)
2. 把 hook 脚本和挂件(`cc-pet.ps1`)复制到 `%USERPROFILE%\.claude\hooks\`
3. **合并**(不覆盖)必要的 hook 条目进 `%USERPROFILE%\.claude\settings.json`(会先自动备份)
4. 在启动文件夹创建自启快捷方式,并立即启动挂件

Windows 版已知差异:
- 会话名取自 `claude agents` 的会话名(不读终端 tab 标题)
- 点击跳转聚焦到承载该会话的**终端窗口**;Windows Terminal 多 tab 共享一个窗口,无法切到具体 tab(平台限制)
- WPF 不支持彩色 emoji,状态图标为单色字形 + 按状态着色(红=需审批、蓝=等回话、绿=完成等)

## 卸载

macOS:

```bash
bash uninstall.sh
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

会移除写入的 hook 条目(保留你自己的配置)、删除已安装文件、清理加载入口(macOS 的 `init.lua` 加载行 / Windows 的自启快捷方式)。

## 自定义

覆盖自动探测的 node/claude 路径:

- macOS:新建 `~/.hammerspoon/cc-pet.json`,例如 `{ "node": "/opt/homebrew/bin/node", "claude": "/opt/homebrew/bin/claude" }`
- Windows:新建 `%USERPROFILE%\.claude\hooks\cc-pet.json`,例如 `{ "node": "C:\\Program Files\\nodejs\\node.exe", "claude": "claude" }`

挂件外观常量在 `~/.hammerspoon/cc-pet.lua` / `cc-pet.ps1` 顶部(`ICON` / `PANEL_W` / `CHIP_H` / `MAX_CHIPS`);
动画速度/幅度在 `animate()` / 动画定时器里(旋转 `t*200`、脉动 `t*3.2` 等,两个平台参数一致)。

## 工作原理

```
Claude Code 事件 ──hook──> cc-state.js ──写──> ~/.claude/hooks/cc-state.d/<sid>.json
                                                        │
挂件每 2s ──────────> cc-sessions.js ──汇集──> ┤ claude agents --json (有哪些会话)
 macOS: cc-pet.lua                             ┤ macOS: ps (pid→tty) + terminal-titles.applescript (tty→标题)
 Windows: cc-pet.ps1                           └ Windows: pid 存活检测(名字直接用会话名)
                          │
                          └─> 输出 [{sid,name,tty,state}] ──> 挂件渲染 + 逐帧动画
                              (Windows 上 tty 字段放 pid,点击时交给 win-focus.ps1 聚焦终端窗口)
```

- **状态写入**:`cc-state.js` 挂在 7 个 Claude Code 事件上,把每个会话的状态写成小 JSON。
- **状态聚合**:`cc-sessions.js` 把"活着的会话 + tty + 终端标题 + 状态"合成一份列表,带 TTL(超时的状态自动降级,避免卡住)。
- **自动放行**:`cc-autoallow.js` 是 `PreToolUse` hook,只读工具直接返回 `permissionDecision: allow`。
- **渲染/动画分离**:数据轮询只在状态变化时重建面板;独立的 14fps 定时器只改元素属性做动画,平滑且省电。

## 安全说明

`cc-autoallow.js` 会让 `Read` / `Glob` / `Grep` **自动通过权限确认**(它们不改文件、不执行命令)。
`Bash` / `Write` / `Edit` 等有副作用的操作**不在名单内**,照常需要你确认。
想关掉自动放行:编辑 `~/.claude/settings.json`,删掉 `matcher: "Read|Glob|Grep"` 那条 PreToolUse hook 即可。

### 盲批(默认关,谨慎开启)

在 `cc-pet.json` 里设 `"blindApprove": true` 后,**点击 needs ⏰ 行会直接给该会话发送批准键(默认 `1` = 允许本次),不切窗口**;适合信任当前任务、想省去切终端的场景。

⚠️ **这是盲操作 —— 你没看到在批准什么就批了**,风险自负;拿不准就别开(默认关闭,点击照常只跳转)。不同 Claude Code 版本的权限菜单可能不同,可用 `"approveKeys"` 自定义发送的键(如 `""` 表示只回车、接受高亮默认项)。

## 许可

MIT

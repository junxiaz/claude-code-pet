# Claude Code Floating Pet 🐾

[中文](README.md) · **English**

![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-black)
![license](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks-8A5CF6)
![Hammerspoon](https://img.shields.io/badge/Hammerspoon-Lua-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-WPF-5391FE)

A floating desktop companion for [Claude Code](https://claude.com/claude-code) (macOS / Windows), inspired by OpenAI Codex's "Pets" — it shows the live status of every Claude Code session in a corner of your screen, and jumps to the matching terminal on click.

![states](docs/demo.gif)

## Features

- **Multi-session overview**: every Claude session with an open terminal is listed in one small panel; only live ones show (closed sessions disappear automatically).
- **Five lightweight animated states**
  - 🌀 `working` — spinning, busy at work
  - ⏰ `needs` — red pulse, waiting for your permission approval
  - 💬 `waiting` — blue breathing, finished and waiting for your reply
  - ✅ `done` — bouncing, just finished a turn
  - 😴 `idle` — gentle breathing, nothing to do
- **Click to jump**: click a session row → automatically switch to the terminal tab it lives in.
- **Draggable**, with position memory.
- **Low-noise approvals**: read-only tools (Read/Glob/Grep) are auto-approved; only risky operations pop a prompt and highlight the pet in red to get your attention.

## Requirements

| Dependency | macOS | Windows |
|---|---|---|
| Floating-window host | [Hammerspoon](https://www.hammerspoon.org) (free, open source) | Built-in PowerShell 5.1 + WPF — **no extra dependency** |
| [Node.js](https://nodejs.org) | Required (runs the hook / aggregation scripts) | Required |
| Claude Code CLI | Must support `claude agents --json` | Same |
| Terminal | **iTerm2** or the built-in **Terminal.app** (both jump & title-reading are supported) | **Windows Terminal** (recommended) or any console window |

## Install

### macOS

```bash
git clone https://github.com/junxiaz/claude-code-pet.git
cd claude-code-pet
bash install.sh
```

The install script will:
1. Check dependencies
2. Copy the hook scripts into `~/.claude/hooks/`
3. Place the widget module at `~/.hammerspoon/cc-pet.lua` and append one line `require("cc-pet")` to your `~/.hammerspoon/init.lua`
4. **Merge** (not overwrite) the required hook entries into `~/.claude/settings.json` (a backup is made first)
5. Reload Hammerspoon

After installing:
- Open Hammerspoon; on first run, go to **System Settings → Privacy & Security → Accessibility** and enable Hammerspoon (needed for dragging the pet).
- Open a few terminals running `claude`, and their statuses appear in the bottom-right corner.

### Windows

```powershell
git clone https://github.com/junxiaz/claude-code-pet.git
cd claude-code-pet
powershell -ExecutionPolicy Bypass -File install.ps1
```

The install script will:
1. Check dependencies (node / claude / Windows Terminal)
2. Copy the hook scripts and the widget (`cc-pet.ps1`) into `%USERPROFILE%\.claude\hooks\`
3. **Merge** (not overwrite) the required hook entries into `%USERPROFILE%\.claude\settings.json` (a backup is made first)
4. Create a Startup-folder shortcut for auto-start and launch the widget immediately

Known differences on Windows:
- Session names come from `claude agents` (terminal tab titles are not read).
- Click-to-jump focuses the **terminal window** hosting the session; Windows Terminal tabs share one window, so switching to a specific tab is not possible (platform limitation).
- WPF cannot render color emoji, so state icons are monochrome glyphs tinted per state (red = needs approval, blue = waiting for reply, green = done, …).

## Uninstall

macOS:

```bash
bash uninstall.sh
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

Removes the hook entries it added (keeping your own config), deletes the installed files, and cleans the loader entry (the `init.lua` line on macOS / the Startup shortcut on Windows).

## Customization

Override the auto-detected node/claude paths:

- macOS: create `~/.hammerspoon/cc-pet.json`, e.g. `{ "node": "/opt/homebrew/bin/node", "claude": "/opt/homebrew/bin/claude" }`
- Windows: create `%USERPROFILE%\.claude\hooks\cc-pet.json`, e.g. `{ "node": "C:\\Program Files\\nodejs\\node.exe", "claude": "claude" }`

Appearance constants are at the top of `~/.hammerspoon/cc-pet.lua` / `cc-pet.ps1` (`ICON` / `PANEL_W` / `CHIP_H` / `MAX_CHIPS`); animation speed/amplitude live in `animate()` / the animation timer (rotation `t*200`, pulse `t*3.2`, etc. — identical on both platforms).

## How it works

```
Claude Code event ──hook──> cc-state.js ──write──> ~/.claude/hooks/cc-state.d/<sid>.json
                                                          │
Widget every 2s ────────> cc-sessions.js ──aggregate──> ┤ claude agents --json (which sessions)
 macOS: cc-pet.lua                                      ┤ macOS: ps (pid→tty) + terminal-titles.applescript (tty→title)
 Windows: cc-pet.ps1                                    └ Windows: pid liveness check (names come from session names)
                          │
                          └─> emits [{sid,name,tty,state}] ──> pet renders + per-frame animation
                              (on Windows the tty field carries the pid; clicks hand it to win-focus.ps1 to focus the terminal window)
```

- **State writing**: `cc-state.js` hooks into 7 Claude Code events and writes each session's state as a small JSON file.
- **State aggregation**: `cc-sessions.js` combines "live sessions + tty + terminal title + state" into one list, with TTLs (stale states auto-downgrade, so nothing gets stuck).
- **Auto-approve**: `cc-autoallow.js` is a `PreToolUse` hook that returns `permissionDecision: allow` for read-only tools.
- **Render/animation split**: the data poll only rebuilds the panel when state changes; a separate 14fps timer mutates element properties for animation — smooth and power-efficient.

## Security

`cc-autoallow.js` makes `Read` / `Glob` / `Grep` **pass the permission prompt automatically** (they don't modify files or run commands). Side-effecting operations like `Bash` / `Write` / `Edit` are **not** on the allowlist and still require your confirmation.

To turn auto-approve off: edit `~/.claude/settings.json` and remove the PreToolUse hook whose `matcher` is `"Read|Glob|Grep"`.

### Blind approve (off by default, use with care)

Set `"blindApprove": true` in `cc-pet.json` and **clicking a needs ⏰ row sends the approval key (default `1` = allow once) straight to that session — without switching windows**. Handy when you trust the current task and want to skip the terminal round-trip.

⚠️ **This is a blind action — you approve without seeing what you're approving.** Use at your own risk; leave it off if unsure (default off; clicks just jump as usual). Permission menus may differ across Claude Code versions, so you can set `"approveKeys"` to customize what's sent (e.g. `""` = just Enter, accepting the highlighted default).

## License

MIT

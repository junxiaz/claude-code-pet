# Claude Code Floating Pet 🐾

[中文](README.md) · **English**

![platform](https://img.shields.io/badge/platform-macOS-black)
![license](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-hooks-8A5CF6)
![Hammerspoon](https://img.shields.io/badge/Hammerspoon-Lua-blue)

A floating macOS desktop companion for [Claude Code](https://claude.com/claude-code), inspired by OpenAI Codex's "Pets" — it shows the live status of every Claude Code session in a corner of your screen, and jumps to the matching terminal on click.

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

| Dependency | Notes |
|---|---|
| macOS | macOS only |
| [Hammerspoon](https://www.hammerspoon.org) | Hosts the floating window; free and open source |
| [Node.js](https://nodejs.org) | Runs the hook / aggregation scripts |
| Claude Code CLI | Must support `claude agents --json` |
| Terminal | **iTerm2** or the built-in **Terminal.app** (both jump & title-reading are supported) |

## Install

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

## Uninstall

```bash
bash uninstall.sh
```

Removes the hook entries it added (keeping your own config), deletes the installed files, and cleans the loader line from `init.lua`.

## Customization

Create `~/.hammerspoon/cc-pet.json` to override the auto-detected paths:

```json
{ "node": "/opt/homebrew/bin/node", "claude": "/opt/homebrew/bin/claude" }
```

Appearance constants are at the top of `~/.hammerspoon/cc-pet.lua` (`ICON` / `PANEL_W` / `CHIP_H` / `MAX_CHIPS`); animation speed/amplitude live in `animate()` (rotation `t*200`, pulse `t*3.2`, bounce height `12`, etc.).

## How it works

```
Claude Code event ──hook──> cc-state.js ──write──> ~/.claude/hooks/cc-state.d/<sid>.json
                                                          │
Hammerspoon every 2s ──> cc-sessions.js ──aggregate──> ┤ claude agents --json (which sessions)
  (cc-pet.lua)                                          ┤ ps (pid→tty)
                                                        └ terminal-titles.applescript (tty→title)
                          │
                          └─> emits [{sid,name,tty,state}] ──> pet renders + per-frame animation
```

- **State writing**: `cc-state.js` hooks into 7 Claude Code events and writes each session's state as a small JSON file.
- **State aggregation**: `cc-sessions.js` combines "live sessions + tty + terminal title + state" into one list, with TTLs (stale states auto-downgrade, so nothing gets stuck).
- **Auto-approve**: `cc-autoallow.js` is a `PreToolUse` hook that returns `permissionDecision: allow` for read-only tools.
- **Render/animation split**: the data poll only rebuilds the panel when state changes; a separate 14fps timer mutates element properties for animation — smooth and power-efficient.

## Security

`cc-autoallow.js` makes `Read` / `Glob` / `Grep` **pass the permission prompt automatically** (they don't modify files or run commands). Side-effecting operations like `Bash` / `Write` / `Edit` are **not** on the allowlist and still require your confirmation.

To turn auto-approve off: edit `~/.claude/settings.json` and remove the PreToolUse hook whose `matcher` is `"Read|Glob|Grep"`.

## License

MIT

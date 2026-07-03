require("hs.ipc") -- 启用 `hs` 命令行（可选）

-- ============================================================================
-- Claude Code 悬浮 Pet（类 Codex Pets）—— 轻量动画版
--   · 会话列表来自 `claude agents --json`（异步 helper 汇集，只显示有真实终端的会话）
--   · 名字用终端标签标题；状态用 hook 实时写入
--   · 五态轻量动画：working 旋转 / needs 红脉动 / waiting 蓝呼吸 / done 蹦跳 / idle 微呼吸
--   · 可拖动（需辅助功能权限），位置持久化；点击某会话行 → 异步跳到它的终端 tab
--   · 终端支持 iTerm2 与 Terminal.app（跳转/取标题两边都试）
-- ============================================================================

-- ---- reload 免重启：先停掉上一实例的长生命周期对象 ----
for _, k in ipairs({ "ccStateTimer", "ccAnimTimer", "ccDragTap" }) do
  if _G[k] then pcall(function() _G[k]:stop() end); _G[k] = nil end
end
if _G.ccCanvas then pcall(function() _G.ccCanvas:delete() end); _G.ccCanvas = nil end

-- ---- 路径探测（去硬编码）----
local HOME = os.getenv("HOME")
local function resolvePath(cands)
  for _, p in ipairs(cands) do if p and hs.fs.attributes(p) then return p end end
  return nil
end
local cfg = {}
do
  local f = io.open(HOME .. "/.hammerspoon/cc-pet.json", "r")
  if f then local c = f:read("a"); f:close(); local ok, o = pcall(hs.json.decode, c); if ok and o then cfg = o end end
end
local NODE = cfg.node or resolvePath({ "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node" }) or
    "/usr/local/bin/node"
local CLAUDE = cfg.claude or resolvePath({ HOME .. "/.npm-global/bin/claude", HOME .. "/.claude/local/claude",
  "/opt/homebrew/bin/claude", "/usr/local/bin/claude" }) or "claude"
local HOOKS = HOME .. "/.claude/hooks"
local HELPER = HOOKS .. "/cc-sessions.js"
local FOCUS = HOOKS .. "/focus-tty.applescript"
local OPEN = HOOKS .. "/open-agents.applescript"
local SENDKEY = HOOKS .. "/send-key.applescript"
-- 盲批开关(默认关):开启后,点 needs⏰ 行直接给该会话发送批准键,不切窗口。
-- ⚠️ 盲操作,你没看到在批准什么;approveKeys 默认 "1"(允许本次)。
local BLIND = cfg.blindApprove == true
local APPROVE_KEYS = cfg.approveKeys or "1"
_G.ccPaths = "node=" .. NODE .. " | claude=" .. CLAUDE

-- ---- 配置 ----
local EMOJI = { needs = "⏰", working = "🌀", done = "✅", waiting = "💬", idle = "😴" }
local MAX_CHIPS = 8
local ICON = 68
local PANEL_W = 230
local CHIP_H = 30

local screen = hs.screen.primaryScreen()
local sf = screen:frame()
local canDrag = hs.accessibilityState()

local chipMap = {}   -- elementId -> 会话
local anim = {}      -- 动画目标列表
local lastSig = nil
local grab, downId, moved = nil, nil, false

-- ---- 异步任务（保留引用防 GC）----
local running = {}
local function runTask(bin, args, cb)
  local tk
  tk = hs.task.new(bin, function(code, out, err)
    running[tk] = nil
    if cb then cb(code, out, err) end
  end, args)
  running[tk] = true
  tk:start()
  return tk
end

-- ---- 异步跳转（调用外部 AppleScript 文件，兼容 iTerm2 / Terminal.app）----
local function openAgentsAsync()
  runTask("/usr/bin/osascript", { OPEN, CLAUDE })
end

local function focusTtyAsync(tty, onFail)
  if not tty or tty == "" or tty == "??" then if onFail then onFail() end; return end
  runTask("/usr/bin/osascript", { FOCUS, "/dev/" .. tty }, function(_, out)
    if not (out or ""):find("ok") and onFail then onFail() end
  end)
end

local function approveTtyAsync(tty, name)
  if not tty or tty == "" or tty == "??" then return end
  runTask("/usr/bin/osascript", { SENDKEY, "/dev/" .. tty, APPROVE_KEYS }, function(_, out)
    if (out or ""):find("ok") then hs.alert.show("🔓 已盲批 " .. (name or "")) end
  end)
end

local function onClick(id)
  local s = chipMap[id]
  if s and s.tty and s.tty ~= "" and s.tty ~= "??" then
    if BLIND and s.state == "needs" then
      approveTtyAsync(s.tty, s.name) -- 盲批:直接发批准键,不切窗口
    else
      focusTtyAsync(s.tty, openAgentsAsync)
    end
  else
    openAgentsAsync()
  end
end

-- ---- 拖动 / 点击 ----
local function savePos()
  if not _G.ccCanvas then return end
  local tl = _G.ccCanvas:topLeft()
  local sz = _G.ccCanvas:size()
  hs.settings.set("ccPetAnchor", { x = tl.x + sz.w, y = tl.y + sz.h })
end

local function mouseHandler(_, msg, elemId)
  if msg == "mouseDown" then
    downId = elemId
    moved = false
    if canDrag and _G.ccCanvas then
      local m = hs.mouse.absolutePosition()
      local tl = _G.ccCanvas:topLeft()
      grab = { dx = m.x - tl.x, dy = m.y - tl.y }
      if _G.ccDragTap then _G.ccDragTap:stop() end
      _G.ccDragTap = hs.eventtap.new(
        { hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp },
        function(e)
          local ty = e:getType()
          if ty == hs.eventtap.event.types.leftMouseDragged then
            local mm = hs.mouse.absolutePosition()
            local nx, ny = mm.x - grab.dx, mm.y - grab.dy
            if math.abs(nx - _G.ccCanvas:topLeft().x) > 3 or math.abs(ny - _G.ccCanvas:topLeft().y) > 3 then moved = true end
            _G.ccCanvas:topLeft({ x = nx, y = ny })
          else
            if _G.ccDragTap then _G.ccDragTap:stop(); _G.ccDragTap = nil end
            if moved then savePos() else onClick(downId) end
          end
          return false
        end
      )
      _G.ccDragTap:start()
    end
  elseif msg == "mouseUp" then
    if not canDrag then onClick(elemId) end
  end
end

-- ---- 渲染（结构重建，仅状态变化时调用）----
local function render(list)
  local n = #list
  local w, h
  local elements = {}
  chipMap = {}
  anim = {}
  local now = hs.timer.secondsSinceEpoch()

  if n <= 1 then
    w, h = ICON, ICON
    local st = (n == 1) and list[1].state or "idle"
    elements[#elements + 1] = { type = "rectangle", action = "fill", id = "bg",
      fillColor = { alpha = 0.32, red = 0, green = 0, blue = 0 },
      roundedRectRadii = { xRadius = 18, yRadius = 18 },
      trackMouseDown = true, trackMouseUp = true }
    elements[#elements + 1] = { type = "text", text = EMOJI[st] or "🐾", textSize = 40,
      textAlignment = "center", frame = { x = 0, y = 8, w = ICON, h = ICON - 14 } }
    if n == 1 then
      chipMap["bg"] = list[1]
      anim[#anim + 1] = { emojiIdx = 2, bgIdx = 1, state = st, cx = ICON / 2, cy = ICON / 2, ts = now }
    end
  else
    local m = math.min(n, MAX_CHIPS)
    w = PANEL_W
    h = m * CHIP_H + 10
    elements[#elements + 1] = { type = "rectangle", action = "fill", id = "bg",
      fillColor = { alpha = 0.36, red = 0, green = 0, blue = 0 },
      roundedRectRadii = { xRadius = 14, yRadius = 14 },
      trackMouseDown = true, trackMouseUp = true }
    for i = 1, m do
      local s = list[i]
      local id = "chip" .. i
      local y = 5 + (i - 1) * CHIP_H
      elements[#elements + 1] = { type = "rectangle", action = "fill", id = id,
        fillColor = { alpha = 0.001, white = 1 },
        frame = { x = 5, y = y, w = w - 10, h = CHIP_H - 2 },
        trackMouseDown = true, trackMouseUp = true }
      local chipIdx = #elements
      elements[#elements + 1] = { type = "text", text = EMOJI[s.state] or "🐾", textSize = 17,
        textAlignment = "center", frame = { x = 8, y = y + 4, w = 26, h = CHIP_H - 8 } }
      local emojiIdx = #elements
      elements[#elements + 1] = { type = "text", text = s.name, textSize = 15,
        textColor = { white = 1 }, frame = { x = 38, y = y + 5, w = w - 46, h = CHIP_H - 8 } }
      chipMap[id] = s
      anim[#anim + 1] = { emojiIdx = emojiIdx, bgIdx = chipIdx, state = s.state,
        cx = 8 + 13, cy = y + 4 + (CHIP_H - 8) / 2, ts = now }
    end
  end

  -- 多屏/分辨率兜底：锚点不在任何屏幕内(换屏、分辨率变化、拔外接屏)就回落到当前主屏右下角
  local pf = hs.screen.primaryScreen():frame()
  local anchor = hs.settings.get("ccPetAnchor")
  local onScreen = false
  if anchor then
    for _, sc in ipairs(hs.screen.allScreens()) do
      local f = sc:frame()
      if anchor.x >= f.x and anchor.x <= f.x + f.w and anchor.y >= f.y and anchor.y <= f.y + f.h then
        onScreen = true; break
      end
    end
  end
  if not onScreen then anchor = { x = pf.x + pf.w - 24, y = pf.y + pf.h - 24 } end
  local rect = hs.geometry.rect(anchor.x - w, anchor.y - h, w, h)

  -- 先销毁旧挂件再建新的，否则旧 canvas 要等 GC 才消失 → 屏幕上短暂出现两个
  if _G.ccCanvas then pcall(function() _G.ccCanvas:delete() end); _G.ccCanvas = nil end

  local c = hs.canvas.new(rect)
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior({ "canJoinAllSpaces", "stationary" })
  c:clickActivating(false)
  for i, e in ipairs(elements) do c[i] = e end
  c:mouseCallback(mouseHandler)
  c:canvasMouseEvents(true, true, false, false)
  c:show()
  _G.ccCanvas = c

  local dbg = {}
  for _, e in ipairs(elements) do if e.type == "text" then dbg[#dbg + 1] = e.text end end
  _G.ccRender = table.concat(dbg, " || ")
end

-- ---- 逐帧动画（只改元素属性，不重建）----
local M = hs.canvas.matrix
local function animate()
  local c = _G.ccCanvas
  if not c or #anim == 0 then return end
  local t = hs.timer.secondsSinceEpoch()
  for _, a in ipairs(anim) do
    local mat
    if a.state == "working" then
      local deg = (t * 200) % 360 -- 旋转 200°/s
      mat = M.identity():translate(a.cx, a.cy):rotate(deg):translate(-a.cx, -a.cy)
    elseif a.state == "needs" then
      local p = math.abs(math.sin(t * 3.2))
      mat = M.identity():translate(a.cx, a.cy):scale(1 + 0.12 * p):translate(-a.cx, -a.cy)
      pcall(function() c[a.bgIdx].fillColor = { red = 0.95, green = 0.26, blue = 0.2, alpha = 0.12 + 0.34 * p } end)
    elseif a.state == "waiting" then
      local p = math.abs(math.sin(t * 1.6)) -- 柔和蓝色呼吸,慢于 needs
      mat = M.identity():translate(a.cx, a.cy):scale(1 + 0.05 * p):translate(-a.cx, -a.cy)
      pcall(function() c[a.bgIdx].fillColor = { red = 0.25, green = 0.55, blue = 0.95, alpha = 0.06 + 0.16 * p } end)
    elseif a.state == "done" then
      local dt = t - (a.ts or t)
      local dy = 0
      if dt < 1.1 then dy = -math.abs(math.sin(dt * math.pi * 2)) * 12 * (1 - dt / 1.1) end
      mat = M.identity():translate(0, dy)
    elseif a.state == "idle" then
      mat = M.identity():translate(a.cx, a.cy):scale(1 + 0.03 * math.sin(t * 2.0)):translate(-a.cx, -a.cy)
    end
    if mat then pcall(function() c[a.emojiIdx].transformation = mat end) end
  end
end

-- ---- 数据轮询（异步 helper，绝不阻塞主线程）----
local polling = false
local function poll()
  if polling then return end
  polling = true
  runTask(NODE, { HELPER, CLAUDE }, function(code, stdout)
    polling = false
    if code ~= 0 then return end
    local ok, list = pcall(hs.json.decode, stdout)
    if not ok or type(list) ~= "table" then return end
    local parts = { tostring(#list) }
    for _, s in ipairs(list) do parts[#parts + 1] = s.state .. ":" .. s.name end
    local sig = table.concat(parts, "|")
    _G.ccLast = sig
    if sig ~= lastSig then
      lastSig = sig
      render(list)
    end
  end)
end

_G.ccStateTimer = hs.timer.doEvery(2, poll)
_G.ccStateTimer:start()
_G.ccAnimTimer = hs.timer.doEvery(0.07, animate)
_G.ccAnimTimer:start()
poll()

if not canDrag then
  hs.alert.show("Claude Code 悬浮 Pet 已启动 🐾（拖动需开启辅助功能权限）")
  hs.accessibilityState(true)
else
  hs.alert.show("Claude Code 悬浮 Pet 已启动 🐾")
end

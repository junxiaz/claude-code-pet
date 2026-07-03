# ============================================================================
# Claude Code 悬浮 Pet —— Windows 版（PowerShell 5.1 + WPF，零额外依赖）
#   · 与 macOS 版(cc-pet.lua)同一套数据链路: node cc-sessions.js 每 2s 汇集会话
#   · 仅状态签名变化才重建面板；独立 ~14fps 定时器只改变换属性做动画
#   · 五态动画: working 旋转 / needs 红脉动 / waiting 蓝呼吸 / done 蹦跳 / idle 微呼吸
#   · 可拖动，位置持久化；点击会话行 → 聚焦承载它的终端窗口(win-focus.ps1)
#   · 已知限制: WPF 不支持彩色 emoji 字体，图标为单色字形 + 按状态着色；
#               Windows Terminal 多 tab 共享窗口，跳转只能到窗口级
# 启动: powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File cc-pet.ps1
# ============================================================================
#Requires -Version 5.1

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---- 单实例 ----
$script:mutex = New-Object System.Threading.Mutex($false, "cc-pet-widget")
if (-not $script:mutex.WaitOne(0, $false)) { exit }

# ---- 路径 ----
$HOOKS   = Join-Path $env:USERPROFILE ".claude\hooks"
$HELPER  = Join-Path $HOOKS "cc-sessions.js"
$FOCUS   = Join-Path $HOOKS "win-focus.ps1"
$OPEN    = Join-Path $HOOKS "win-open-agents.ps1"
$POSFILE = Join-Path $HOOKS "cc-pet-anchor.json"

# 自定义 node/claude 路径: 新建 %USERPROFILE%\.claude\hooks\cc-pet.json
# 例如 {"node":"C:\\Program Files\\nodejs\\node.exe","claude":"claude"}
$cfg = $null
$cfgFile = Join-Path $HOOKS "cc-pet.json"
if (Test-Path $cfgFile) { try { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json } catch {} }
$NODE   = if ($cfg -and $cfg.node)   { $cfg.node }   else { "node" }
$CLAUDE = if ($cfg -and $cfg.claude) { $cfg.claude } else { "claude" }

# ---- 配置（emoji 用码点构造，避免脚本编码问题；与 lua 版 EMOJI 一致）----
$U = { param($cp) [char]::ConvertFromUtf32($cp) }
$EMOJI = @{
  needs   = & $U 0x23F0   # ⏰
  working = & $U 0x1F300  # 🌀
  done    = & $U 0x2705   # ✅
  waiting = & $U 0x1F4AC  # 💬
  idle    = & $U 0x1F634  # 😴
}
$PAW = & $U 0x1F43E       # 🐾
# WPF 的 emoji 是单色字形 → 按状态着色补回色彩语义
$COLOR = @{
  needs = "#FF6B5E"; working = "#FFFFFF"; done = "#4CD97B"; waiting = "#6BA6FF"; idle = "#9AA0A6"
}
$MAX_CHIPS = 8
$ICON      = 68.0
$PANEL_W   = 230.0
$CHIP_H    = 30.0

$bc = New-Object Windows.Media.BrushConverter
function NewBrush([string]$hex) { ($bc.ConvertFromString($hex)).Clone() } # Clone 解冻，动画要改 Opacity
$BG_PANEL = "#5C000000"

# ---- 窗口 ----
$win = New-Object Windows.Window
$win.WindowStyle       = "None"
$win.AllowsTransparency = $true
$win.Background        = [Windows.Media.Brushes]::Transparent
$win.Topmost           = $true
$win.ShowInTaskbar     = $false
$win.ShowActivated     = $false
$win.ResizeMode        = "NoResize"
$win.Width  = $ICON
$win.Height = $ICON

$rootBorder = New-Object Windows.Controls.Border
$rootBorder.CornerRadius = New-Object Windows.CornerRadius 18
$win.Content = $rootBorder

$script:anim    = @()
$script:lastSig = $null
$script:clock   = [System.Diagnostics.Stopwatch]::StartNew()

# ---- 位置（锚点 = 右下角，随尺寸变化保持右下不动，与 lua 版一致）----
function Get-Anchor {
  if (Test-Path $POSFILE) {
    try {
      $a = Get-Content $POSFILE -Raw | ConvertFrom-Json
      if ($a.x -and $a.y) { return $a }
    } catch {}
  }
  $wa = [Windows.SystemParameters]::WorkArea
  [pscustomobject]@{ x = $wa.Right - 24; y = $wa.Bottom - 24 }
}
function Save-Anchor {
  try {
    @{ x = $win.Left + $win.Width; y = $win.Top + $win.Height } | ConvertTo-Json -Compress | Set-Content $POSFILE
  } catch {}
}
function Place-Window {
  $a = Get-Anchor
  $win.Left = [double]$a.x - $win.Width
  $win.Top  = [double]$a.y - $win.Height
}

# ---- 变换组（scale + rotate + translate，动画只改这些属性）----
function New-EmojiTransform($tb) {
  $scale = New-Object Windows.Media.ScaleTransform 1, 1
  $rot   = New-Object Windows.Media.RotateTransform 0
  $tr    = New-Object Windows.Media.TranslateTransform 0, 0
  $g = New-Object Windows.Media.TransformGroup
  [void]$g.Children.Add($scale); [void]$g.Children.Add($rot); [void]$g.Children.Add($tr)
  $tb.RenderTransform = $g
  $tb.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
  @{ scale = $scale; rot = $rot; tr = $tr }
}

# ---- 渲染（结构重建，仅状态变化时调用）----
function Render($list) {
  $script:anim = @()
  $now = $script:clock.Elapsed.TotalSeconds
  $n = @($list).Count

  if ($n -le 1) {
    # 单会话/空: 大图标模式
    $st = if ($n -eq 1) { $list[0].state } else { "idle" }
    $win.Width = $ICON; $win.Height = $ICON
    $rootBorder.CornerRadius = New-Object Windows.CornerRadius 18
    $bgBrush = NewBrush $BG_PANEL
    $rootBorder.Background = $bgBrush
    $rootBorder.Tag = if ($n -eq 1) { $list[0] } else { $null }

    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = if ($n -eq 1) { $EMOJI[$st] } else { $PAW }
    $tb.FontFamily = New-Object Windows.Media.FontFamily "Segoe UI Emoji"
    $tb.FontSize = 34
    $tb.Foreground = NewBrush $COLOR[$st]
    $tb.HorizontalAlignment = "Center"; $tb.VerticalAlignment = "Center"
    $tf = New-EmojiTransform $tb
    $rootBorder.Child = $tb

    if ($n -eq 1) {
      $pulse = $null
      if ($st -eq "needs" -or $st -eq "waiting") { $pulse = NewBrush $COLOR[$st]; $pulse.Opacity = 0.1; $rootBorder.Background = $pulse }
      $script:anim += @{ state = $st; ts = $now; scale = $tf.scale; rot = $tf.rot; tr = $tf.tr; bgBrush = $pulse }
    }
  } else {
    # 多会话: 面板模式
    $m = [Math]::Min($n, $MAX_CHIPS)
    $win.Width = $PANEL_W; $win.Height = $m * $CHIP_H + 10
    $rootBorder.CornerRadius = New-Object Windows.CornerRadius 14
    $rootBorder.Background = NewBrush $BG_PANEL
    $rootBorder.Tag = $null

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = New-Object Windows.Thickness 5
    for ($i = 0; $i -lt $m; $i++) {
      $s = $list[$i]
      $chip = New-Object Windows.Controls.Border
      $chip.Height = $CHIP_H - 2
      $chip.CornerRadius = New-Object Windows.CornerRadius 8
      $chip.Tag = $s
      $chip.Cursor = [Windows.Input.Cursors]::Hand
      $pulse = $null
      if ($s.state -eq "needs" -or $s.state -eq "waiting") {
        $pulse = NewBrush $COLOR[$s.state]; $pulse.Opacity = 0.1; $chip.Background = $pulse
      } else {
        $chip.Background = [Windows.Media.Brushes]::Transparent
      }

      $row = New-Object Windows.Controls.DockPanel
      $em = New-Object Windows.Controls.TextBlock
      $em.Text = $EMOJI[$s.state]; if (-not $em.Text) { $em.Text = $PAW }
      $em.FontFamily = New-Object Windows.Media.FontFamily "Segoe UI Emoji"
      $em.FontSize = 15
      $em.Foreground = NewBrush $COLOR[$s.state]
      $em.Width = 26; $em.TextAlignment = "Center"; $em.VerticalAlignment = "Center"
      $em.Margin = New-Object Windows.Thickness 4, 0, 4, 0
      [Windows.Controls.DockPanel]::SetDock($em, "Left")
      $tf = New-EmojiTransform $em

      $nm = New-Object Windows.Controls.TextBlock
      $nm.Text = $s.name
      $nm.FontFamily = New-Object Windows.Media.FontFamily "Segoe UI"
      $nm.FontSize = 13
      $nm.Foreground = [Windows.Media.Brushes]::White
      $nm.VerticalAlignment = "Center"
      $nm.TextTrimming = "CharacterEllipsis"

      [void]$row.Children.Add($em); [void]$row.Children.Add($nm)
      $chip.Child = $row
      [void]$stack.Children.Add($chip)

      $script:anim += @{ state = $s.state; ts = $now; scale = $tf.scale; rot = $tf.rot; tr = $tf.tr; bgBrush = $pulse }
    }
    $rootBorder.Child = $stack
  }
  Place-Window
}

# ---- 逐帧动画（只改变换/透明度，不重建）----
$animTimer = New-Object Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(70)
$animTimer.Add_Tick({
  $t = $script:clock.Elapsed.TotalSeconds
  foreach ($a in $script:anim) {
    switch ($a.state) {
      "working" {
        $a.rot.Angle = ($t * 200) % 360                       # 旋转 200°/s
      }
      "needs" {
        $p = [Math]::Abs([Math]::Sin($t * 3.2))               # 红色脉动
        $a.scale.ScaleX = 1 + 0.12 * $p; $a.scale.ScaleY = 1 + 0.12 * $p
        if ($a.bgBrush) { $a.bgBrush.Opacity = 0.12 + 0.34 * $p }
      }
      "waiting" {
        $p = [Math]::Abs([Math]::Sin($t * 1.6))               # 柔和蓝色呼吸，慢于 needs
        $a.scale.ScaleX = 1 + 0.05 * $p; $a.scale.ScaleY = 1 + 0.05 * $p
        if ($a.bgBrush) { $a.bgBrush.Opacity = 0.06 + 0.16 * $p }
      }
      "done" {
        $dt = $t - $a.ts                                       # 完成后蹦跳 1.1s
        $a.tr.Y = if ($dt -lt 1.1) { -([Math]::Abs([Math]::Sin($dt * [Math]::PI * 2)) * 8 * (1 - $dt / 1.1)) } else { 0 }
      }
      "idle" {
        $s2 = 1 + 0.03 * [Math]::Sin($t * 2.0)                 # 微呼吸
        $a.scale.ScaleX = $s2; $a.scale.ScaleY = $s2
      }
    }
  }
})

# ---- 数据轮询（后台进程，不阻塞 UI 线程）----
$script:pollProc = $null
function Start-Poll {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $NODE
    $psi.Arguments = ('"{0}" "{1}"' -f $HELPER, $CLAUDE)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $script:pollProc = [System.Diagnostics.Process]::Start($psi)
  } catch { $script:pollProc = $null }
}
$pollTimer = New-Object Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromSeconds(2)
$pollTimer.Add_Tick({
  if (-not $script:pollProc) { Start-Poll; return }
  if (-not $script:pollProc.HasExited) { return }
  $out = ""
  try { $out = $script:pollProc.StandardOutput.ReadToEnd() } catch {}
  try { $script:pollProc.Dispose() } catch {}
  $script:pollProc = $null

  $list = @()
  try { $list = @(($out | ConvertFrom-Json)) } catch { $list = @() }
  $parts = @([string]$list.Count)
  foreach ($s in $list) { $parts += "$($s.state):$($s.name)" }
  $sig = $parts -join "|"
  if ($sig -ne $script:lastSig) {
    $script:lastSig = $sig
    Render $list
  }
  Start-Poll
})

# ---- 点击跳转 / 拖动 ----
function Invoke-Detached([string]$file, [string[]]$argv) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $quoted = @($argv | ForEach-Object { '"{0}"' -f $_ }) -join " "
    $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $file, $quoted)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    [void][System.Diagnostics.Process]::Start($psi)
  } catch {}
}
function Find-Session($el) {
  $cur = $el
  while ($cur) {
    if ($cur -is [Windows.FrameworkElement] -and $cur.Tag) { return $cur.Tag }
    $cur = [Windows.Media.VisualTreeHelper]::GetParent($cur)
  }
  $null
}
$win.Add_MouseLeftButtonDown({
  param($s, $e)
  $src = $e.OriginalSource
  $x0 = $win.Left; $y0 = $win.Top
  try { $win.DragMove() } catch {}   # 阻塞到松开鼠标；没拖动就当点击
  if ([Math]::Abs($win.Left - $x0) -gt 3 -or [Math]::Abs($win.Top - $y0) -gt 3) {
    Save-Anchor
  } else {
    $sess = Find-Session $src
    if ($sess -and $sess.tty -and $sess.tty -ne "" -and $sess.tty -ne "??") {
      Invoke-Detached $FOCUS @([string]$sess.tty)      # Windows 上 tty 字段即 pid
    } else {
      Invoke-Detached $OPEN @([string]$CLAUDE)
    }
  }
})

# ---- 启动 ----
Render @()
$animTimer.Start()
$pollTimer.Start()
Start-Poll

$app = New-Object Windows.Application
[void]$app.Run($win)

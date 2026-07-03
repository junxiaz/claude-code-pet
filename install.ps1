# Claude Code 悬浮 Pet —— Windows 一键安装
# 用法: powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = "Stop"

$REPO  = Split-Path -Parent $MyInvocation.MyCommand.Path
$HOOKS = Join-Path $env:USERPROFILE ".claude\hooks"

function Say($m)  { Write-Host ("> " + $m)  -ForegroundColor Cyan }
function Ok($m)   { Write-Host ("√ " + $m)  -ForegroundColor Green }
function Warn($m) { Write-Host ("! " + $m)  -ForegroundColor Yellow }
function Die($m)  { Write-Host ("x " + $m)  -ForegroundColor Red; exit 1 }

Say "检查依赖…"
if ($env:OS -ne "Windows_NT") { Die "此脚本仅用于 Windows；macOS 请运行 install.sh" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Die "未找到 node，请先安装 Node.js（winget install OpenJS.NodeJS.LTS）" }
$claudeFound = (Get-Command claude -ErrorAction SilentlyContinue) -or
               (Test-Path (Join-Path $env:USERPROFILE "AppData\Roaming\npm\claude.cmd")) -or
               (Test-Path (Join-Path $env:USERPROFILE ".local\bin\claude.exe"))
if ($claudeFound) { Ok "找到 claude CLI" } else { Warn "未找到 claude CLI（需支持 ``claude agents --json``）" }
if (Get-Command wt.exe -ErrorAction SilentlyContinue) { Ok "终端: Windows Terminal" } else { Ok "终端: 控制台窗口（未装 Windows Terminal，跳转/新开将用 PowerShell 窗口）" }

Say "停止已在运行的挂件（如有）…"
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "cc-pet\.ps1" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Say "安装 hook 脚本 → $HOOKS"
New-Item -ItemType Directory -Force -Path $HOOKS | Out-Null
Copy-Item (Join-Path $REPO "hooks\*.js")      $HOOKS -Force
Copy-Item (Join-Path $REPO "hooks\win-*.ps1") $HOOKS -Force
Copy-Item (Join-Path $REPO "pet\cc-pet.ps1")  $HOOKS -Force
Ok "hooks 与挂件已复制"

Say "合并 hook 配置 → $env:USERPROFILE\.claude\settings.json（自动备份）"
$SET = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $SET) {
    $stamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Copy-Item $SET "$SET.bak.$stamp" -Force
    Ok "已备份原 settings.json"
}
node (Join-Path $REPO "scripts\merge-settings.js")
Ok "配置已合并"

Say "设置开机自启（启动文件夹快捷方式）…"
$startup = [Environment]::GetFolderPath("Startup")
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path $startup "Claude Code Pet.lnk"))
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments  = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $HOOKS "cc-pet.ps1"))
$lnk.WorkingDirectory = $HOOKS
$lnk.Save()
Ok "已创建自启快捷方式"

Say "启动挂件…"
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
    "-File", (Join-Path $HOOKS "cc-pet.ps1")
)
Ok "挂件已启动"

Write-Host @"

──────────────────────────────────────────────
安装完成 🐾
  · 屏幕右下角会出现挂件；开几个跑着 claude 的终端即可看到状态
  · 自定义 node/claude 路径: 新建 $env:USERPROFILE\.claude\hooks\cc-pet.json
    例如 {"node":"C:\\Program Files\\nodejs\\node.exe","claude":"claude"}
  · 卸载: powershell -ExecutionPolicy Bypass -File uninstall.ps1
──────────────────────────────────────────────
"@

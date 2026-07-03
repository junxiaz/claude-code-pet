# Claude Code 悬浮 Pet —— Windows 卸载
# 用法: powershell -ExecutionPolicy Bypass -File uninstall.ps1
$ErrorActionPreference = "SilentlyContinue"

$REPO  = Split-Path -Parent $MyInvocation.MyCommand.Path
$HOOKS = Join-Path $env:USERPROFILE ".claude\hooks"

function Say($m) { Write-Host ("> " + $m) -ForegroundColor Cyan }
function Ok($m)  { Write-Host ("√ " + $m) -ForegroundColor Green }

Say "停止运行中的挂件"
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "cc-pet\.ps1" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Ok "挂件已停止"

Say "移除 settings.json 中的 hook 条目（保留你自己的配置）"
node (Join-Path $REPO "scripts\merge-settings.js") --remove
Ok "配置已清理"

Say "删除已安装文件"
Remove-Item (Join-Path $HOOKS "cc-state.js"),
            (Join-Path $HOOKS "cc-sessions.js"),
            (Join-Path $HOOKS "cc-autoallow.js"),
            (Join-Path $HOOKS "win-focus.ps1"),
            (Join-Path $HOOKS "win-open-agents.ps1"),
            (Join-Path $HOOKS "cc-pet.ps1"),
            (Join-Path $HOOKS "cc-pet-anchor.json") -Force
Remove-Item (Join-Path $HOOKS "cc-state.d") -Recurse -Force
Ok "文件已删除"

Say "移除开机自启快捷方式"
Remove-Item (Join-Path ([Environment]::GetFolderPath("Startup")) "Claude Code Pet.lnk") -Force
Ok "卸载完成"

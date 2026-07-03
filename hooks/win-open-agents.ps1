# 用法: powershell -File win-open-agents.ps1 [claude路径]
# 对应 macOS 版的 open-agents.applescript:
# 若已有标题含 "claude agents" 的窗口则聚焦它；否则新开一个终端跑 `claude agents`。
# 优先 Windows Terminal(wt)，没有则退回 PowerShell 控制台窗口。
param([string]$ClaudeBin = "claude")

$ErrorActionPreference = "SilentlyContinue"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CCWin2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@

# 先找现有的（注: Windows Terminal 的 MainWindowTitle 是“当前活动 tab”的标题，
# claude agents 在后台 tab 时匹配不到 → 会新开一个，属已知限制）
$existing = Get-Process |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -match "claude agents" } |
    Select-Object -First 1
if ($existing) {
    if ([CCWin2]::IsIconic($existing.MainWindowHandle)) {
        [CCWin2]::ShowWindowAsync($existing.MainWindowHandle, 9) | Out-Null
    }
    [CCWin2]::SetForegroundWindow($existing.MainWindowHandle) | Out-Null
    Write-Output "focused"
    exit 0
}

# 没找到就新开一个
if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
    Start-Process wt.exe -ArgumentList @(
        "new-tab", "--title", "claude agents",
        "powershell", "-NoExit", "-Command", "& '$ClaudeBin' agents"
    )
} else {
    Start-Process powershell.exe -ArgumentList @(
        "-NoExit", "-Command",
        "`$Host.UI.RawUI.WindowTitle = 'claude agents'; & '$ClaudeBin' agents"
    )
}
Write-Output "created"
exit 0

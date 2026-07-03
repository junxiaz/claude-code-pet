# 用法: powershell -File win-focus.ps1 <pid>
# 聚焦承载指定 claude 进程的终端窗口（对应 macOS 版的 focus-tty.applescript）。
# 原理: 从 claude 的 pid 沿父进程链向上，找到第一个有主窗口的进程
#       （Windows Terminal / conhost / VS Code 等），把它前置。
# 输出 "ok" / "none"。注意: Windows Terminal 多 tab 共享一个窗口，
# 只能聚焦到窗口级，无法切到具体 tab（平台限制）。
param([Parameter(Mandatory = $true)][int]$TargetPid)

$ErrorActionPreference = "SilentlyContinue"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CCWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@

$cur = $TargetPid
for ($i = 0; $i -lt 8 -and $cur; $i++) {
    $p = Get-Process -Id $cur -ErrorAction SilentlyContinue
    if (-not $p) { break }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
        if ([CCWin]::IsIconic($p.MainWindowHandle)) {
            [CCWin]::ShowWindowAsync($p.MainWindowHandle, 9) | Out-Null  # 9 = SW_RESTORE
        }
        [CCWin]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        Write-Output "ok"
        exit 0
    }
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    $cur = if ($parent) { [int]$parent.ParentProcessId } else { 0 }
}

Write-Output "none"
exit 0

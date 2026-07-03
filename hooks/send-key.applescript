-- 用法: osascript send-key.applescript /dev/ttysXXX <要输入的字符>
-- 把按键直接打进该 tty 的终端会话(iTerm2 或 Terminal.app),用于「盲批」:
-- 不切窗口就给权限提示发送选择键(默认 "1" = 允许本次)。返回 "ok" / "none"。
-- ⚠️ 这是盲操作:你没看到在批准什么。仅在你明确开启 blindApprove 时才会被调用。
on run argv
	if (count of argv) < 2 then return "none"
	set theTty to item 1 of argv
	set theKeys to item 2 of argv

	if application "iTerm" is running then
		tell application "iTerm"
			repeat with w in windows
				repeat with t in tabs of w
					repeat with s in sessions of t
						if (tty of s) is theTty then
							tell s to write text theKeys
							return "ok"
						end if
					end repeat
				end repeat
			end repeat
		end tell
	end if

	if application "Terminal" is running then
		tell application "Terminal"
			repeat with w in windows
				repeat with t in tabs of w
					try
						if (tty of t) is theTty then
							do script theKeys in t
							return "ok"
						end if
					end try
				end repeat
			end repeat
		end tell
	end if

	return "none"
end run

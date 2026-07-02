-- 用法: osascript focus-tty.applescript /dev/ttysXXX
-- 在 iTerm2 或 Terminal.app 里找到该 tty 的会话并聚焦。返回 "ok" / "none"。
on run argv
	if (count of argv) < 1 then return "none"
	set theTty to item 1 of argv

	if application "iTerm" is running then
		tell application "iTerm"
			repeat with w in windows
				repeat with t in tabs of w
					repeat with s in sessions of t
						if (tty of s) is theTty then
							activate
							select s
							select t
							select w
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
							set selected of t to true
							set index of w to 1
							activate
							return "ok"
						end if
					end try
				end repeat
			end repeat
		end tell
	end if

	return "none"
end run

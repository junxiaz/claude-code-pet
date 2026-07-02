-- 用法: osascript open-agents.applescript <claude绝对路径>
-- 若已有跑着 `claude agents` 的会话则聚焦它；否则在可用终端里新开一个窗口运行它。
-- 优先 iTerm2；没有 iTerm2 时用 Terminal.app。
on run argv
	set claudeBin to "claude"
	if (count of argv) ≥ 1 then set claudeBin to item 1 of argv

	-- 先找现有的
	if application "iTerm" is running then
		tell application "iTerm"
			repeat with w in windows
				repeat with t in tabs of w
					repeat with s in sessions of t
						if (name of s) contains "claude agents" then
							activate
							select s
							select t
							select w
							return "focused"
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
						if (custom title of t) contains "claude agents" then
							set selected of t to true
							set index of w to 1
							activate
							return "focused"
						end if
					end try
				end repeat
			end repeat
		end tell
	end if

	-- 没找到就新开一个
	if application "iTerm" is running then
		tell application "iTerm"
			activate
			create window with default profile
			tell current session of current window to write text (claudeBin & " agents")
		end tell
		return "created"
	else
		tell application "Terminal"
			activate
			do script (claudeBin & " agents")
		end tell
		return "created"
	end if
end run

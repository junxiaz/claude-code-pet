-- 输出每个终端会话的 "tty@@@标题"，一行一个。
-- 同时覆盖 iTerm2 与 Terminal.app；用 `is running` 守卫，避免把没开的应用给启动起来。
set out to ""

if application "iTerm" is running then
	tell application "iTerm"
		repeat with w in windows
			repeat with t in tabs of w
				repeat with s in sessions of t
					set out to out & (tty of s) & "@@@" & (name of s) & linefeed
				end repeat
			end repeat
		end repeat
	end tell
end if

if application "Terminal" is running then
	tell application "Terminal"
		repeat with w in windows
			repeat with t in tabs of w
				set theTitle to ""
				try
					set theTitle to custom title of t
				end try
				if theTitle is "" or theTitle is missing value then
					try
						set procs to processes of t
						if (count of procs) > 0 then set theTitle to (item -1 of procs)
					end try
				end if
				try
					set out to out & (tty of t) & "@@@" & theTitle & linefeed
				end try
			end repeat
		end repeat
	end tell
end if

return out

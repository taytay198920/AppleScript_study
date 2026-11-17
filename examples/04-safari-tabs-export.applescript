-- 04-safari-tabs-export.applescript
-- 把 Safari 所有窗口的所有标签页导出成 Markdown 清单。
-- 对应 docs/14 §14.1
--
-- 用法：
--   osascript 04-safari-tabs-export.applescript                 # 输出到 stdout
--   osascript 04-safari-tabs-export.applescript <输出文件路径>    # 写入文件
--
-- 首次运行会弹「终端想要控制 Safari」授权框，点「好」。
-- 若点了「不允许」，会报 -1743，需去 系统设置 → 隐私与安全性 → 自动化 手动打开。

on ownDir()
	try
		return do shell script "dirname " & quoted form of (POSIX path of (path to me))
	on error
		return do shell script "pwd"
	end try
end ownDir

on loadLib()
	set libPath to (my ownDir()) & "/lib/stdlib.scpt"
	try
		return load script (POSIX file libPath)
	on error
		error "找不到工具库 " & libPath & linefeed & "请先执行：osacompile -o lib/stdlib.scpt lib/stdlib.applescript" number -43
	end try
end loadLib

on markdownEscape(theText)
	set escaped to my replaceIn(theText, "\\", "\\\\")
	return my replaceIn(escaped, "[", "\\[")
end markdownEscape

on replaceIn(theText, searchFor, replaceWith)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to searchFor
	set theParts to text items of theText
	set AppleScript's text item delimiters to replaceWith
	set theResult to theParts as text
	set AppleScript's text item delimiters to oldDelims
	return theResult
end replaceIn

on run argv
	set lib to my loadLib()
	set out to {}

	-- 不启动 Safari，只在它已经运行时才导出
	set safariRunning to false
	tell application "System Events"
		set safariRunning to (exists process "Safari")
	end tell

	if not safariRunning then
		return "Safari 当前没有运行。请先打开 Safari 再运行本脚本。" & linefeed & ¬
			"（脚本刻意不主动启动 Safari，避免打断你。）"
	end if

	set windowCount to 0
	set tabTotal to 0

	try
		tell application "Safari"
			set windowCount to count of windows
		end tell
	on error errMsg number errNum
		return "❌ 无法访问 Safari：" & errMsg & " (#" & errNum & ")" & linefeed & ¬
			"如果是 -1743，请到 系统设置 → 隐私与安全性 → 自动化，允许当前程序控制 Safari。"
	end try

	set end of out to "# Safari 标签页清单"
	set end of out to ""
	set end of out to "> 导出时间：" & (lib's formatStamp(current date))
	set end of out to "> 窗口数：" & windowCount
	set end of out to ""

	tell application "Safari"
		repeat with w from 1 to windowCount
			set theTabs to tabs of window w
			set tabCount to count of theTabs
			set tabTotal to tabTotal + tabCount

			set end of out to "## 窗口 " & w & "（" & tabCount & " 个标签页）"
			set end of out to ""

			-- ⚠️ 一次性取回 name / URL 列表，比逐个标签页问 Safari 快得多（见 docs/07 §7.7）
			set tabNames to name of every tab of window w
			set tabURLs to URL of every tab of window w
			set currentIndex to index of current tab of window w

			repeat with t from 1 to tabCount
				set theName to item t of tabNames
				set theURL to item t of tabURLs
				set marker to ""
				if t is currentIndex then set marker to " ←当前"
				if theName is missing value or theName is "" then set theName to "(无标题)"
				if theURL is missing value then set theURL to ""
				set end of out to "- [" & (my markdownEscape(theName)) & "](" & theURL & ")" & marker
			end repeat

			set end of out to ""
		end repeat
	end tell

	set end of out to "---"
	set end of out to "共 " & tabTotal & " 个标签页。"

	set markdownText to lib's joinText(out, linefeed)

	if (count of argv) > 0 then
		set outputPath to item 1 of argv
		lib's writeTextFile(outputPath, markdownText & linefeed, false)
		return "✅ 已导出 " & tabTotal & " 个标签页到：" & outputPath
	else
		return markdownText
	end if
end run

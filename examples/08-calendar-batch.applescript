-- 08-calendar-batch.applescript
-- 从文本文件批量创建 Calendar 事件。对应 docs/14 §14.3、docs/04 §4.2、docs/08 §8.5
--
-- 用法：
--   osascript 08-calendar-batch.applescript <文本文件> [--calendar 日历名] [--dry-run]
--
-- <文本文件> 可以是绝对路径、~ 开头、相对当前目录、或相对本脚本所在目录，
--    四种都会依次尝试。
--
-- 输入格式（每行一条，用 | 分隔，# 开头是注释，空行忽略）：
--   YYYY-MM-DD HH:MM | 时长 | 标题 | 地点
--   YYYY-MM-DD HH:MM | 时长 | 标题
--   YYYY-MM-DD       | 标题                    ← 两段 = 全天事件
--
-- 时长写法：90（分钟）、1h30m、2h、45m
--
-- 示例文件内容：
--   # 本周会议
--   2026-11-20 10:00 | 1h   | 产品周会   | 会议室 A
--   2026-11-20 14:30 | 90    | 技术评审
--   2026-11-21       | 团建日
--
-- ⚠️ 首次运行会弹「终端想要控制 Calendar」授权框，点「好」；
--    若点了「不允许」会报 -1743，需去 系统设置 → 隐私与安全性 → 自动化 手动打开。
--    在授权框上不做选择会让脚本一直挂着（无超时）。
-- ⚠️ Calendar 的事件标题属性叫 summary，不是 name/title（见 docs/08 §8.5）。
-- ⚠️ Calendar 没有 default calendar 术语，不指定 --calendar 时会用 calendar 1。
--
-- 验证状态：
--   ✅ 解析、日期计算、时长计算、dry-run、错误处理：本机实测通过
--   🔵 真正写入 Calendar 的分支：osacompile 编译通过，
--      但本机测试时 Calendar 的自动化授权框需要人工点击，未做运行时验证

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
		error "找不到工具库 " & libPath & linefeed & ¬
			"请先执行：osacompile -o lib/stdlib.scpt lib/stdlib.applescript" number -43
	end try
end loadLib

on expandTilde(p)
	if p starts with "~/" then
		return (POSIX path of (path to home folder)) & (text 3 thru -1 of p)
	else if p is "~" then
		return POSIX path of (path to home folder)
	end if
	return p
end expandTilde

on parseArgs(argv)
	set opts to {inputPath:"", calendarName:"", dryRun:false}
	set positional to {}
	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--calendar" then
			set i to i + 1
			if i > (count of argv) then error "--calendar 后面要跟日历名"
			set calendarName of opts to item i of argv
		else if a is "--dry-run" then
			set dryRun of opts to true
		else if a starts with "--" then
			error "未知参数：" & a
		else
			set end of positional to a
		end if
		set i to i + 1
	end repeat
	if (count of positional) < 1 then
		error "用法：osascript 08-calendar-batch.applescript <文本文件> [--calendar 日历名] [--dry-run]"
	end if
	set inputPath of opts to my expandTilde(item 1 of positional)
	return opts
end parseArgs

-- "2026-11-20 10:00" → date 对象
-- ⚠️ 不用 date "2026年11月20日…" 字面量：格式随系统区域变化，本机实测会 -30720（docs/16 §16.5⑤）
on parseDateTime(dateText)
	set t to my trimBoth(dateText)
	set theDatePart to t
	set theTimePart to "00:00"
	set spacePos to offset of " " in t
	if spacePos > 0 then
		set theDatePart to text 1 thru (spacePos - 1) of t
		set theTimePart to my trimBoth(text (spacePos + 1) thru -1 of t)
	end if

	set AppleScript's text item delimiters to "-"
	set dateParts to text items of theDatePart
	set AppleScript's text item delimiters to ""
	if (count of dateParts) is not 3 then
		error "日期格式应为 YYYY-MM-DD，实际是：" & dateText
	end if

	set theYear to (item 1 of dateParts) as integer
	set theMonth to (item 2 of dateParts) as integer
	set theDay to (item 3 of dateParts) as integer

	set theHour to 0
	set theMinute to 0
	if theTimePart contains ":" then
		set AppleScript's text item delimiters to ":"
		set timeParts to text items of theTimePart
		set AppleScript's text item delimiters to ""
		set theHour to (item 1 of timeParts) as integer
		set theMinute to (item 2 of timeParts) as integer
	end if

	-- 从一个已知基准日出发逐项赋值，避免任何本地化解析
	set theDate to (current date)
	set day of theDate to 1              -- 先设成 1 号，防止改月份时日期溢出
	set year of theDate to theYear
	set month of theDate to theMonth
	set day of theDate to theDay
	set hours of theDate to theHour
	set minutes of theDate to theMinute
	set seconds of theDate to 0
	return theDate
end parseDateTime

-- "90" / "1h30m" / "2h" / "45m" / "1h" → 分钟数
-- ⚠️ 取子串前一定要判长度：`text 3 thru -1 of "1h"` 会报 -1728（越界）
on parseDuration(durationText)
	set t to my trimBoth(durationText)
	if t is "" then return 60

	if (t contains "h") or (t contains "m") then
		set totalMinutes to 0

		set hPos to offset of "h" in t
		if hPos > 1 then
			set totalMinutes to totalMinutes + ((text 1 thru (hPos - 1) of t) as integer) * 60
		end if
		if hPos > 0 then
			if hPos < (length of t) then
				set t to my trimBoth(text (hPos + 1) thru -1 of t)
			else
				set t to ""
			end if
		end if

		set mPos to offset of "m" in t
		if mPos > 1 then
			set minuteText to my trimBoth(text 1 thru (mPos - 1) of t)
			if minuteText is not "" then set totalMinutes to totalMinutes + (minuteText as integer)
		end if

		if totalMinutes is 0 then error "无法解析时长：" & durationText
		return totalMinutes
	end if

	try
		return t as integer
	on error
		error "无法解析时长：" & durationText & "（支持 90 / 1h30m / 2h / 45m）"
	end try
end parseDuration

-- ⚠️ do shell script 的工作目录是 $HOME，不是调用 osascript 时的 cwd，
-- 所以拿不到「用户当前目录」。这里按两个候选依次试：
--   ① 原样（绝对路径 / ~ 展开后）  ② 相对本脚本所在目录
-- 把用户给的路径解析成绝对路径。
-- ⚠️ System Events 的 `exists file` 不认相对路径（实测直接返回 false），
--    但 `do shell script "pwd"` 能拿到调用 osascript 时的 cwd（实测）。
--    所以按三个候选依次试：① 原样/~展开  ② 相对 cwd  ③ 相对本脚本目录。
-- ⚠️ 这里刻意不用「候选列表 + repeat」的写法：`set end of lst to x` 存进去的是
--    引用，遍历时 `c as text` 行为不稳定（docs/16 §16.2①a、§16.2⑳）。
-- ⚠️ 局部变量别叫 expanded：会撞上 AX 的 expanded 术语，报 -10003。见 docs/16 §16.1③。
on resolveInputPath(rawPath, lib)
	set expandedPath to my expandTilde(rawPath)
	if lib's fileExists(expandedPath) then return expandedPath

	set cwdPath to ""
	try
		set cwdPath to (do shell script "pwd") & "/" & rawPath
	end try
	if cwdPath is not "" then
		if lib's fileExists(cwdPath) then return cwdPath
	end if

	set scriptPath to (my ownDir()) & "/" & rawPath
	if lib's fileExists(scriptPath) then return scriptPath

	error "输入文件不存在：" & rawPath & linefeed & ¬
		"已尝试：" & linefeed & ¬
		"  1) " & expandedPath & linefeed & ¬
		"  2) " & cwdPath & linefeed & ¬
		"  3) " & scriptPath number 10030
end resolveInputPath

on trimBoth(theText)
	set t to theText
	repeat while (length of t) > 0 and ((text 1 of t) is in {" ", linefeed, tab, return})
		set t to text 2 thru -1 of t
	end repeat
	repeat while (length of t) > 0 and ((text -1 of t) is in {" ", linefeed, tab, return})
		set t to text 1 thru -2 of t
	end repeat
	return t
end trimBoth

-- 解析一行 → record
on parseLine(lineText, lineNo)
	set t to my trimBoth(lineText)
	if t is "" or t starts with "#" then return missing value

	set AppleScript's text item delimiters to "|"
	set parts to text items of t
	set AppleScript's text item delimiters to ""

	set fieldCount to count of parts
	if fieldCount < 2 then
		error "第 " & lineNo & " 行格式不对（至少要 2 个字段，用 | 分隔）：" & lineText
	end if

	-- 清洗每个字段
	set cleanParts to {}
	repeat with p in parts
		set end of cleanParts to my trimBoth(p as text)
	end repeat

	set theDateText to item 1 of cleanParts
	-- ⚠️ record 的所有键必须在这里一次性建好。
	-- AppleScript 的 `set X of rec to …` 只能改「已存在的键」，
	-- 对不存在的键赋值会报 -10006（errAECantAssign）。见 docs/16 §16.2⑮。
	set rec to {lineNo:lineNo, rawText:lineText, startDate:(current date), ¬
		summary:"", allday:false, durationMinutes:0, locationText:""}

	if fieldCount = 2 then
		-- YYYY-MM-DD | 标题  → 全天事件
		set startDate of rec to my parseDateTime(theDateText)
		set summary of rec to item 2 of cleanParts
		set allday of rec to true
		set durationMinutes of rec to 0
		set locationText of rec to ""
	else
		-- YYYY-MM-DD HH:MM | 时长 | 标题 [| 地点]
		set startDate of rec to my parseDateTime(theDateText)
		set durationMinutes of rec to my parseDuration(item 2 of cleanParts)
		set summary of rec to item 3 of cleanParts
		set allday of rec to false
		if fieldCount ≥ 4 then
			set locationText of rec to item 4 of cleanParts
		else
			set locationText of rec to ""
		end if
	end if

	if (summary of rec) is "" then error "第 " & lineNo & " 行标题为空：" & lineText
	return rec
end parseLine

on formatEvent(rec, lib)
	set startStamp to lib's formatStamp(startDate of rec)
	if allday of rec then
		set durText to "全天"
	else
		set endDate to (startDate of rec) + (durationMinutes of rec * minutes)
		set durText to (durationMinutes of rec as text) & " 分钟（至 " & (lib's formatStamp(endDate)) & "）"
	end if
	set outText to "  " & startStamp & "  " & (summary of rec) & linefeed & "    " & durText
	if (locationText of rec) is not "" then set outText to outText & linefeed & "    地点: " & (locationText of rec)
	return outText
end formatEvent

on run argv
	set lib to my loadLib()
	set opts to my parseArgs(argv)

	set inputPath to my resolveInputPath(inputPath of opts, lib)

	set allLines to lib's readLines(inputPath)
	set report to {}
	set parsedList to {}
	set lineNo to 0

	-- 1) 先全部解析完，任何一行有问题就整体中止（避免创建一半）
	repeat with aLine in allLines
		set lineNo to lineNo + 1
		try
			set rec to my parseLine(aLine as text, lineNo)
			if rec is not missing value then set end of parsedList to rec
		on error errMsg number errNum
			error "解析失败：" & errMsg number errNum
		end try
	end repeat

	set end of report to "从 " & inputPath & " 解析出 " & (count of parsedList) & " 条事件"
	set end of report to ""

	repeat with rec in parsedList
		set end of report to my formatEvent(rec, lib)
	end repeat

	if (count of parsedList) is 0 then
		set end of report to ""
		set end of report to "没有可创建的事件（文件里全是注释或空行？）"
		set AppleScript's text item delimiters to linefeed
		set finalText to report as text
		set AppleScript's text item delimiters to ""
		return finalText
	end if

	-- 2) dry-run 到此为止
	if dryRun of opts then
		set end of report to ""
		set end of report to "[dry-run] 未创建任何事件"
		set AppleScript's text item delimiters to linefeed
		set finalText to report as text
		set AppleScript's text item delimiters to ""
		return finalText
	end if

	-- 3) 真正创建
	set createdCount to 0
	set failedCount to 0
	tell application "Calendar"
		set targetCalendar to missing value
		if (calendarName of opts) is not "" then
			try
				set targetCalendar to calendar (calendarName of opts)
			on error
				set availableNames to name of every calendar
				set AppleScript's text item delimiters to "、"
				set namesText to availableNames as text
				set AppleScript's text item delimiters to ""
				error "找不到日历「" & (calendarName of opts) & "」。可用的有：" & namesText
			end try
		else
			-- ⚠️ Calendar 没有 default calendar 这个术语（本机 sdef 实测，
			-- application 的 class-extension 只声明了 calendar 元素）。
			-- 写 `set x to default calendar` 会编译失败：
			--   Expected end of line but found class name. (-2741)
			-- 只能退回到「第一个日历」，并把实际用的名字报告出来。
			set targetCalendar to calendar 1
			set end of report to "⚠️ 未指定 --calendar，使用第一个日历「" & (name of targetCalendar) & "」"
			set end of report to ""
		end if

		repeat with rec in parsedList
			try
				if allday of rec then
					make new event at end of events of targetCalendar with properties ¬
						{summary:(summary of rec), start date:(startDate of rec), allday event:true}
				else
					set endDate to (startDate of rec) + ((durationMinutes of rec) * minutes)
					set newEvent to make new event at end of events of targetCalendar ¬
						with properties {summary:(summary of rec), start date:(startDate of rec), ¬
						end date:endDate, allday event:false}
					-- ⚠️ location 必须在事件对象上设，不能往裸 record 里塞：
					-- 在 tell Calendar 块内 `set location of props to …` 会把 location
					-- 当成 Calendar 的术语解析，编译报 -2741（docs/07 §7.2）
					if (locationText of rec) is not "" then set location of newEvent to (locationText of rec)
				end if
				set createdCount to createdCount + 1
			on error errMsg
				set failedCount to failedCount + 1
				set end of report to "  ⚠️ 创建失败「" & (summary of rec) & "」: " & errMsg
			end try
		end repeat
	end tell

	set end of report to ""
	set end of report to "✅ 已创建 " & createdCount & " 条事件"
	if failedCount > 0 then set end of report to "⚠️ 失败 " & failedCount & " 条"

	set AppleScript's text item delimiters to linefeed
	set finalText to report as text
	set AppleScript's text item delimiters to ""
	return finalText
end run

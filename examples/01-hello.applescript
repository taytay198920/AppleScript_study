-- 01-hello.applescript
-- 基础语法演示：变量、类型、列表、记录、控制流、handler、命令行参数、错误处理
--
-- 运行：
--   osascript 01-hello.applescript
--   osascript 01-hello.applescript 张三 42

-- property 的值会被编译进 .scpt/.app 并持久保存（见 docs/05 §5.5）
property scriptVersion : "1.0.0"

on padLeft(theNumber, targetWidth)
	set theString to ((theNumber as integer) as text)
	repeat while (length of theString) < targetWidth
		set theString to "0" & theString
	end repeat
	return theString
end padLeft

on joinList(theList, theDelimiter)
	-- 保存并还原全局分隔符，避免污染调用方（见 docs/03 §3.3）
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theText to theList as text
	set AppleScript's text item delimiters to oldDelims
	return theText
end joinList

on describeValue(theValue)
	return ((class of theValue) as text) & " → " & (theValue as text)
end describeValue

on run argv
	set outputLines to {}

	-- ① 命令行参数：argv 是字符串列表
	set end of outputLines to "== 命令行参数 =="
	set end of outputLines to "参数个数: " & (count of argv)
	if (count of argv) > 0 then
		set end of outputLines to "第 1 个: " & (item 1 of argv)
		-- ⚠️ 参数永远是 text，要当数字用得显式转换
		try
			set end of outputLines to "第 1 个当整数: " & ((item 1 of argv) as integer)
		on error
			set end of outputLines to "第 1 个不是整数，跳过"
		end try
	end if

	-- ② 类型
	set end of outputLines to ""
	set end of outputLines to "== 类型与转换 =="
	set end of outputLines to my describeValue(42)
	set end of outputLines to my describeValue(3.14)
	set end of outputLines to my describeValue("文本")
	set end of outputLines to my describeValue(true)
	set end of outputLines to "class of {1,2} = " & ((class of {1, 2}) as text)
	set end of outputLines to "42.7 as integer = " & ((42.7 as integer) as text) & "（四舍五入，不是截断）"
	set end of outputLines to "round 2.5 = " & ((round 2.5) as text) & "（银行家舍入）"
	set end of outputLines to "round 2.5 rounding as taught in school = " & ((round 2.5 rounding as taught in school) as text)

	-- ③ 列表
	set end of outputLines to ""
	set end of outputLines to "== 列表 =="
	set numberList to {5, 3, 9}
	set end of numberList to 1
	set end of outputLines to "追加后: " & my joinList(numberList, ", ")
	set end of outputLines to "count = " & (count of numberList)
	set end of outputLines to "item 1 = " & (item 1 of numberList)
	set end of outputLines to "item -1 = " & (item -1 of numberList)
	set end of outputLines to "items 2 thru 3 = " & my joinList(items 2 thru 3 of numberList, ", ")
	set end of outputLines to "去掉最后一个 = " & my joinList(items 1 thru -2 of numberList, ", ")
	set end of outputLines to "reverse = " & my joinList(reverse of numberList, ", ")

	-- ⚠️ 引用语义演示：set 共享，copy 独立
	set listA to {1, 2}
	set listB to listA
	set end of listB to 3
	set end of outputLines to "set 共享引用: A=" & my joinList(listA, "") & " B=" & my joinList(listB, "")
	set listC to {1, 2}
	copy listC to listD
	set end of listD to 3
	set end of outputLines to "copy 独立副本: C=" & my joinList(listC, "") & " D=" & my joinList(listD, "")

	-- ④ 记录
	set end of outputLines to ""
	set end of outputLines to "== 记录 =="
	-- ⚠️ 键名避开 name / id / class / text / URL（见 docs/03 §3.2）
	set personRecord to {fullName:"Taylor", age:30, city:"上海"}
	set end of outputLines to "fullName = " & (fullName of personRecord)
	set end of outputLines to "字段数 = " & (count of personRecord)
	set mergedRecord to {level:5} & {level:1, verbose:false}
	set end of outputLines to "记录合并（左边优先）level = " & (level of mergedRecord)

	-- ⑤ 文本
	set end of outputLines to ""
	set end of outputLines to "== 文本 =="
	set sampleText to "AppleScript"
	set end of outputLines to "length = " & (length of sampleText)
	set end of outputLines to "text 1 thru 5 = " & (text 1 thru 5 of sampleText)
	set end of outputLines to "text 7 thru -1 = " & (text 7 thru -1 of sampleText)
	set end of outputLines to "offset of \"Scr\" = " & (offset of "Scr" in sampleText)
	set end of outputLines to "padLeft(7,3) = " & my padLeft(7, 3)
	set end of outputLines to "quoted form of = " & (quoted form of "/tmp/a b'c.txt")

	-- ⑥ 控制流
	set end of outputLines to ""
	set end of outputLines to "== 控制流 =="
	set collected to {}
	repeat with i from 1 to 5
		if (i mod 2) is 0 then
			set end of collected to (contents of i)
		end if
	end repeat
	set end of outputLines to "1-5 中的偶数: " & my joinList(collected, ", ")

	-- ⚠️ 遍历列表时用 contents of 取值，否则存进列表的是引用
	set words2 to {}
	repeat with aWord in {"甲", "乙", "丙"}
		set end of words2 to ((contents of aWord) & "!")
	end repeat
	set end of outputLines to "遍历拼接: " & my joinList(words2, " ")

	-- ⑦ 日期
	set end of outputLines to ""
	set end of outputLines to "== 日期 =="
	set nowDate to current date
	set end of outputLines to "现在: " & (year of nowDate as text) & "-" & my padLeft(month of nowDate, 2) ¬
		& "-" & my padLeft(day of nowDate, 2) & " " & my padLeft(hours of nowDate, 2) ¬
		& ":" & my padLeft(minutes of nowDate, 2) & ":" & my padLeft(seconds of nowDate, 2)
	set tomorrow to nowDate + (1 * days)
	set end of outputLines to "明天是星期: " & ((weekday of tomorrow) as text)

	-- ⚠️ date 是引用类型，函数里必须 copy
	copy nowDate to midnight
	set time of midnight to 0
	set end of outputLines to "今天零点: " & (midnight as string)
	set end of outputLines to "原变量未被改动: " & (nowDate as string)

	-- ⑧ 系统信息
	set end of outputLines to ""
	set end of outputLines to "== 系统 =="
	set sysInfo to system info
	set end of outputLines to "用户: " & (short user name of sysInfo)
	set end of outputLines to "系统版本: " & (system version of sysInfo)
	set end of outputLines to "CPU: " & (CPU type of sysInfo)
	set end of outputLines to "脚本版本: " & scriptVersion

	-- 输出（return 走 stdout，log 走 stderr，互不干扰）
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set finalText to outputLines as text
	set AppleScript's text item delimiters to oldDelims
	return finalText
end run

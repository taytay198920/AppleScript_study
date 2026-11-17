-- stdlib.applescript
-- AppleScript 通用工具库。所有函数都规避了 docs/16 里列出的坑。
--
-- ⚠️⚠️ 必须先编译成 .scpt 再 load！实测：
--   load script (POSIX file "…/stdlib.applescript")   ← 加载纯文本源码
--   之后调用 lib's fileExists("…") 会报
--   -1752 "Script doesn't seem to belong to AppleScript."
--   凡是函数体里带 `tell application …` 的都会失败（纯计算的函数侥幸能用）。
--   load script 加载编译好的 .scpt 则一切正常。
--
-- 用法（推荐）：
--   osacompile -o lib/stdlib.scpt lib/stdlib.applescript
--   set stdlib to load script (POSIX file "/abs/path/to/lib/stdlib.scpt")
--   stdlib's splitText("a,b,c", ",")
--   stdlib's fileExists("/tmp/a.txt")
--
-- 用法 B：把需要的 handler 直接复制进你的脚本（最省事，无 load script 开销）

use scripting additions

-- ============================================================
-- 文本
-- ============================================================

on splitText(theText, theDelimiter)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theParts to text items of theText
	set AppleScript's text item delimiters to oldDelims
	return theParts
end splitText

on joinText(theList, theDelimiter)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theText to theList as text
	set AppleScript's text item delimiters to oldDelims
	return theText
end joinText

on replaceText(theText, searchFor, replaceWith)
	return my joinText(my splitText(theText, searchFor), replaceWith)
end replaceText

on trimText(theText)
	set wsChars to {" ", tab, linefeed, return}
	set charList to characters of theText
	repeat while (count of charList) > 0 and (item 1 of charList) is in wsChars
		set charList to rest of charList
	end repeat
	repeat while (count of charList) > 0 and (item -1 of charList) is in wsChars
		set charList to item 1 thru -2 of charList
	end repeat
	return my joinText(charList, "")
end trimText

-- 按行切分，自动兼容 LF / CRLF / CR，并去掉末尾空行
on splitLines(theText)
	set normalized to my replaceText(theText, (return & linefeed), linefeed)
	set normalized to my replaceText(normalized, return, linefeed)
	set theLines to my splitText(normalized, linefeed)
	if (count of theLines) > 0 and (item -1 of theLines) is "" then
		set theLines to item 1 thru -2 of theLines
	end if
	return theLines
end splitLines

-- 左侧补零/补空格：padLeft(7, 2, "0") → "07"
on padLeft(theNumber, targetWidth, padChar)
	set theString to ((theNumber as integer) as text)
	repeat while (length of theString) < targetWidth
		set theString to padChar & theString
	end repeat
	return theString
end padLeft

on fileExtension(fileName)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "."
	set partCount to count of text items of fileName
	set theExt to ""
	if partCount > 1 then
		set theExt to text item -1 of fileName
		-- ".gitignore" 会切成 {"", "gitignore"}：首段为空说明是隐藏文件，不是扩展名
		if (text item 1 of fileName) is "" and partCount is 2 then set theExt to ""
	end if
	set AppleScript's text item delimiters to oldDelims
	return theExt
end fileExtension

-- "photo.tar.gz" → "photo.tar"
on fileBaseName(fileName)
	set theExt to my fileExtension(fileName)
	if theExt is "" then return fileName
	set cutLength to (length of theExt) + 2
	if (length of fileName) < cutLength then return fileName
	return text 1 thru -cutLength of fileName
end fileBaseName

-- ============================================================
-- 列表
-- ============================================================

on listContains(theList, theValue)
	repeat with anItem in theList
		if (contents of anItem) is theValue then return true
	end repeat
	return false
end listContains

on uniqueList(theList)
	set seen to {}
	repeat with anItem in theList
		set theValue to contents of anItem
		if not (my listContains(seen, theValue)) then set end of seen to theValue
	end repeat
	return seen
end uniqueList

-- ============================================================
-- 文件
-- ============================================================

-- ⚠️⚠️ 不要用 `tell application "System Events" to exists file posixPath`。
-- 本机实测：在 TCC 保护目录（~/Desktop、~/Documents、~/Downloads 等）里查询
-- 「不存在」的文件时，System Events 会**无限挂起**——不返回、不报错、不超时，
-- 而且会连带把 System Events 整个卡死（之后所有 Apple Event 都无响应，
-- 只能 killall "System Events" 才能恢复）。
-- 查询「存在」的文件、以及 /tmp 等非保护目录则正常。
-- 所以这里统一走 shell 的 test，行为确定且快。详见 docs/16 §16.5。
on fileExists(posixPath)
	try
		return (do shell script "test -f " & quoted form of posixPath & " && echo yes || echo no") is "yes"
	on error
		return false
	end try
end fileExists

on folderExists(posixPath)
	try
		return (do shell script "test -d " & quoted form of posixPath & " && echo yes || echo no") is "yes"
	on error
		return false
	end try
end folderExists

-- 文件不存在时返回 missing value，其他错误照常抛出
on readTextFile(posixPath)
	set fh to missing value
	try
		set fh to open for access (POSIX file posixPath)
		set theText to read fh as «class utf8»
		close access fh
		return theText
	on error errMsg number errNum
		if fh is not missing value then
			try
				close access fh
			end try
		end if
		if errNum is -39 or errNum is -43 then return missing value
		error errMsg number errNum
	end try
end readTextFile

on readLines(posixPath)
	set fh to missing value
	try
		set fh to open for access (POSIX file posixPath)
		-- ⚠️ 必须带 as «class utf8»，否则默认按 MacRoman 解码，中文变乱码
		set theLines to read fh using delimiter linefeed as «class utf8»
		close access fh
		return theLines
	on error errMsg number errNum
		if fh is not missing value then
			try
				close access fh
			end try
		end if
		if errNum is -39 or errNum is -43 then return {}
		error errMsg number errNum
	end try
end readLines

on writeTextFile(posixPath, theText, appendMode)
	set fh to missing value
	try
		set fh to open for access (POSIX file posixPath) with write permission
		if not appendMode then set eof of fh to 0
		write theText to fh starting at eof as «class utf8»
		close access fh
		return true
	on error errMsg number errNum
		if fh is not missing value then
			try
				close access fh
			end try
		end if
		error "写入失败 " & posixPath & ": " & errMsg & " (#" & errNum & ")" number errNum
	end try
end writeTextFile

on appendLogFile(posixPath, theMessage)
	set stamp to my formatStamp(current date)
	return my writeTextFile(posixPath, stamp & "  " & theMessage & linefeed, true)
end appendLogFile

-- ============================================================
-- 日期
-- ============================================================

-- "2026-11-17 09:30:05"
on formatStamp(theDate)
	return (year of theDate as text) & "-" & my padLeft(month of theDate, 2, "0") ¬
		& "-" & my padLeft(day of theDate, 2, "0") & " " ¬
		& my padLeft(hours of theDate, 2, "0") & ":" & my padLeft(minutes of theDate, 2, "0") ¬
		& ":" & my padLeft(seconds of theDate, 2, "0")
end formatStamp

-- "20261117-093005"，适合做文件名
on fileNameStamp(theDate)
	return (year of theDate as text) & my padLeft(month of theDate, 2, "0") & my padLeft(day of theDate, 2, "0") ¬
		& "-" & my padLeft(hours of theDate, 2, "0") & my padLeft(minutes of theDate, 2, "0") ¬
		& my padLeft(seconds of theDate, 2, "0")
end fileNameStamp

on startOfDay(theDate)
	copy theDate to theCopy
	set time of theCopy to 0
	return theCopy
end startOfDay

on endOfDay(theDate)
	copy theDate to theCopy
	set time of theCopy to (24 * hours - 1)
	return theCopy
end endOfDay

on startOfMonth(theDate)
	set theCopy to my startOfDay(theDate)
	copy theCopy to monthStart
	set day of monthStart to 1
	return monthStart
end startOfMonth

-- ============================================================
-- Shell
-- ============================================================

-- 只去掉末尾的换行符（CR / LF），保留正文里的换行和前导空白
on trimLineEnds(theText)
	set charList to characters of theText
	set eolChars to {linefeed, return}
	repeat while (count of charList) > 0 and (item -1 of charList) is in eolChars
		set charList to item 1 thru -2 of charList
	end repeat
	return my joinText(charList, "")
end trimLineEnds

-- 保留 LF（不做 CR 转换），并去掉末尾换行。
-- ⚠️ 实测 altering line endings false 会把命令输出的末尾换行也一起保留下来，
--    直接拿去当路径用会导致 folderExists 判断失败，所以这里必须 trim。
on runShell(command)
	return my trimLineEnds(do shell script command altering line endings false)
end runShell

on runShellLines(command)
	return my splitLines(do shell script command altering line endings false)
end runShellLines

-- ============================================================
-- 交互（全部安全处理"用户取消"）
-- ============================================================

on notify(theTitle, theMessage)
	display notification theMessage with title theTitle
end notify

on confirm(theMessage, theTitle)
	try
		set theReply to display dialog theMessage buttons {"取消", "确定"} ¬
			default button "确定" cancel button "取消" with title theTitle with icon caution
		return (button returned of theReply) is "确定"
	on error number errNum
		if errNum is -128 then return false
		error number errNum
	end try
end confirm

on prompt(theMessage, defaultValue, theTitle)
	try
		set theReply to display dialog theMessage default answer defaultValue ¬
			buttons {"取消", "确定"} default button "确定" cancel button "取消" with title theTitle
		return text returned of theReply
	on error number errNum
		if errNum is -128 then return missing value
		error number errNum
	end try
end prompt

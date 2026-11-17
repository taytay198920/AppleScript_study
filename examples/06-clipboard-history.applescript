-- 06-clipboard-history.applescript
-- 剪贴板文本清洗 + 历史记录 + 通知。对应 docs/13 §13.4、docs/03 §3.3
--
-- 用法：
--   osascript 06-clipboard-history.applescript                    # 清洗并打印
--   osascript 06-clipboard-history.applescript --write            # 同时写回剪贴板
--   osascript 06-clipboard-history.applescript --history <文件>    # 追加到历史文件
--   osascript 06-clipboard-history.applescript --max 200          # 历史上限条数
--   osascript 06-clipboard-history.applescript --notify           # 完成后发通知
--
-- 清洗规则：
--   1) CRLF / CR 统一成 LF（⚠️ 从 Windows 网页或邮件复制来的文本常带 CRLF）
--   2) 去掉零宽字符与 BOM（U+200B/200C/200D/FEFF），这类字符肉眼看不见但会破坏比较
--   3) 全角空格转半角
--   4) 连续空白折叠成单个空格（--no-collapse 可关）
--   5) 首尾空白去掉
--   6) 智能引号转直引号（--smart-quotes 则保留）

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

on parseArgs(argv)
	set opts to {historyPath:"", doWrite:false, doNotify:false, maxEntries:100, ¬
		collapseWhitespace:true, useSmartQuotes:false}
	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--history" then
			set i to i + 1
			if i > (count of argv) then error "--history 后面要跟文件路径"
			set historyPath of opts to my expandTilde(item i of argv)
		else if a is "--max" then
			set i to i + 1
			if i > (count of argv) then error "--max 后面要跟一个数字"
			set maxEntries of opts to (item i of argv) as integer
		else if a is "--write" then
			set doWrite of opts to true
		else if a is "--notify" then
			set doNotify of opts to true
		else if a is "--no-collapse" then
			set collapseWhitespace of opts to false
		else if a is "--smart-quotes" then
			set useSmartQuotes of opts to true
		else if a starts with "--" then
			error "未知参数：" & a
		else
			error "多余参数：" & a & linefeed & ¬
				"用法见文件头注释"
		end if
		set i to i + 1
	end repeat
	return opts
end parseArgs

on expandTilde(p)
	if p starts with "~/" then
		return (POSIX path of (path to home folder)) & (text 3 thru -1 of p)
	else if p is "~" then
		return POSIX path of (path to home folder)
	end if
	return p
end expandTilde

-- 用 id 构造「肉眼看不见的字符」，比在源码里直接敲安全得多
on charFromId(theId)
	return (character id theId) as text
end charFromId

on replaceAll(theText, searchFor, replaceWith)
	set AppleScript's text item delimiters to searchFor
	set theParts to text items of theText
	set AppleScript's text item delimiters to replaceWith
	set theResult to theParts as text
	set AppleScript's text item delimiters to ""
	return theResult
end replaceAll

on cleanText(rawText, collapseWhitespace, useSmartQuotes)
	set t to rawText

	-- 1) 换行统一成 LF
	set t to my replaceAll(t, (return & linefeed), linefeed)   -- CRLF
	set t to my replaceAll(t, return, linefeed)                -- 单独的 CR

	-- 2) 去掉零宽字符与 BOM
	repeat with zwId in {8203, 8204, 8205, 65279, 8232, 8233}
		set t to my replaceAll(t, (my charFromId(zwId)), "")
	end repeat

	-- 3) 全角空格（U+3000）转半角
	set t to my replaceAll(t, (my charFromId(12288)), " ")

	-- 4) 制表符转空格
	set t to my replaceAll(t, tab, " ")

	-- 5) 折叠连续空白
	if collapseWhitespace then
		set AppleScript's text item delimiters to {" ", linefeed, tab}
		set theParts to text items of t
		set AppleScript's text item delimiters to ""
		set kept to {}
		repeat with p in theParts
			set pt to p as text
			if pt is not "" then set end of kept to pt
		end repeat
		set AppleScript's text item delimiters to " "
		set t to kept as text
		set AppleScript's text item delimiters to ""
	end if

	-- 6) 智能引号 → 直引号（写代码时常被这个坑）
	if not useSmartQuotes then
		set t to my replaceAll(t, (my charFromId(8220)), "\"")  -- 左双引号
		set t to my replaceAll(t, (my charFromId(8221)), "\"")  -- 右双引号
		set t to my replaceAll(t, (my charFromId(8216)), "'")   -- 左单引号
		set t to my replaceAll(t, (my charFromId(8217)), "'")   -- 右单引号
	end if

	-- 7) 首尾裁剪
	return my trimBoth(t)
end cleanText

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

-- 读历史（每行一条），追加新条目并去重（连续重复只留一条），再截断到上限
on appendHistory(historyPath, newEntry, maxEntries, lib)
	set existingLines to {}
	if lib's fileExists(historyPath) then
		set existingLines to lib's readLines(historyPath)
	end if

	-- ⚠️ 别用 result 当累加器（docs/16 §16.1③）
	set merged to {}
	set previousEntry to ""
	repeat with aLine in existingLines
		set lineText to aLine as text
		if lineText is not "" and lineText is not previousEntry then
			set end of merged to lineText
			set previousEntry to lineText
		end if
	end repeat

	-- 新条目放最前面（最近优先），若与最新一条相同则跳过
	if newEntry is not "" and newEntry is not previousEntry then
		set merged to {newEntry} & merged
	end if

	if (count of merged) > maxEntries then
		set merged to items 1 thru maxEntries of merged
	end if

	set AppleScript's text item delimiters to linefeed
	set outText to merged as text
	set AppleScript's text item delimiters to ""
	lib's writeTextFile(historyPath, outText & linefeed, false)
	return count of merged
end appendHistory

on run argv
	set lib to my loadLib()
	set opts to my parseArgs(argv)

	-- 读剪贴板。⚠️ 剪贴板里可能不是文本（图片、文件），要先判类型
	set rawText to ""
	try
		set clipInfo to (clipboard info) as text
	on error
		set clipInfo to ""
	end try

	if clipInfo contains "«class PNGf»" or clipInfo contains "«class TIFF»" or ¬
		clipInfo contains "«class furl»" then
		error "剪贴板里不是纯文本（clipboard info: " & clipInfo & "）。" & linefeed & ¬
			"本示例只处理文本。图片/文件请改用 the clipboard as «class PNGf» 之类。" number 10020
	end if

	try
		set rawText to (the clipboard) as text
	on error errMsg
		error "读剪贴板失败：" & errMsg & linefeed & "（剪贴板可能是空的）" number 10021
	end try

	set cleaned to my cleanText(rawText, collapseWhitespace of opts, useSmartQuotes of opts)

	if cleaned is "" then
		error "清洗后内容为空（原文长度 " & (length of rawText) & " 个字符，可能全是空白/零宽字符）。" number 10022
	end if

	set report to {}
	set end of report to "== 清洗结果 =="
	set end of report to cleaned
	set end of report to ""
	set end of report to "原长度: " & (length of rawText) & " 字符 → 清洗后: " & (length of cleaned) & " 字符"

	-- 写回剪贴板
	if doWrite of opts then
		set the clipboard to cleaned
		set end of report to "✅ 已写回剪贴板"
	end if

	-- 追加历史
	if (historyPath of opts) is not "" then
		set entryCount to my appendHistory(historyPath of opts, cleaned, maxEntries of opts, lib)
		set end of report to "✅ 已追加到历史：" & historyPath of opts & "（当前 " & entryCount & " 条，上限 " & maxEntries of opts & "）"
	end if

	if doNotify of opts then
		set previewText to cleaned
		if (length of previewText) > 60 then set previewText to (text 1 thru 60 of previewText) & "…"
		lib's notify("剪贴板已清洗", previewText)
	end if

	set AppleScript's text item delimiters to linefeed
	set finalText to report as text
	set AppleScript's text item delimiters to ""
	return finalText
end run

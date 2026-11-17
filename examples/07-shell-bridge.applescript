-- 07-shell-bridge.applescript
-- Shell 互操作的正确姿势：转义、编码、退出码、stderr、JSON、管理员权限。
-- 对应 docs/12-Shell互操作.md
--
-- 运行：osascript 07-shell-bridge.applescript

-- ① 安全执行：保留 LF + 去掉末尾换行
on runShell(command)
	set rawOutput to do shell script command altering line endings false
	return my trimLineEnds(rawOutput)
end runShell

on trimLineEnds(theText)
	set charList to characters of theText
	repeat while (count of charList) > 0 and ((item -1 of charList) is linefeed or (item -1 of charList) is return)
		set charList to item 1 thru -2 of charList
	end repeat
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to ""
	set theResult to charList as text
	set AppleScript's text item delimiters to oldDelims
	return theResult
end trimLineEnds

-- ② 按行执行：自动切成 list，去掉末尾空行
on runShellLines(command)
	set rawOutput to my runShell(command)
	set normalized to my replaceIn(rawOutput, return, linefeed)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set theLines to text items of normalized
	set AppleScript's text item delimiters to oldDelims
	if (count of theLines) > 0 and (item -1 of theLines) is "" then
		set theLines to item 1 thru -2 of theLines
	end if
	return theLines
end runShellLines

on replaceIn(theText, searchFor, replaceWith)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to searchFor
	set theParts to text items of theText
	set AppleScript's text item delimiters to replaceWith
	set theResult to theParts as text
	set AppleScript's text item delimiters to oldDelims
	return theResult
end replaceIn

on runShellFull(command)
	set tmpDir to POSIX path of (path to temporary items)
	set outPath to tmpDir & "as_bridge_out_" & (random number from 100000 to 999999)
	set errPath to outPath & ".err"
	-- ⚠️ 必须用 sh -c 包一层：否则 command 里自带的 ";"、"&&"、"exit" 会破坏重定向
	set wrapped to "/bin/sh -c " & quoted form of command & ¬
		" > " & quoted form of outPath & " 2> " & quoted form of errPath & "; echo $?"
	set exitCode to (my runShell(wrapped)) as integer
	set stdoutText to my readFileOrEmpty(outPath)
	set stderrText to my readFileOrEmpty(errPath)
	do shell script "rm -f " & quoted form of outPath & " " & quoted form of errPath
	return {exitCode:exitCode, stdout:stdoutText, stderr:stderrText}
end runShellFull

on readFileOrEmpty(posixPath)
	try
		set fh to open for access (POSIX file posixPath)
		set theText to read fh as «class utf8»
		close access fh
		return my trimLineEnds(theText)
	on error
		return ""
	end try
end readFileOrEmpty

-- ④ 把 AppleScript 值安全地交给 python3 生成 JSON（避免手写转义）
on toJsonString(theList)
	set quotedArgs to {}
	repeat with anItem in theList
		set end of quotedArgs to quoted form of ((contents of anItem) as text)
	end repeat
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " "
	set argText to quotedArgs as text
	set AppleScript's text item delimiters to oldDelims
	return my runShell("/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1:], ensure_ascii=False))' " & argText)
end toJsonString

-- ⑤ 解析 JSON（交给 python3，AppleScript 没有原生 JSON 支持）
--    把 JSON 写进临时文件再交给 python，避免超长命令行和二次转义
on jsonKeys(jsonText)
	set tmpPath to (POSIX path of (path to temporary items)) & "as_bridge_json_" & (random number from 100000 to 999999) & ".json"
	set fh to open for access (POSIX file tmpPath) with write permission
	set eof of fh to 0
	write jsonText to fh as «class utf8»
	close access fh
	set pyCode to "import json,sys; print('\\n'.join(json.load(open(sys.argv[1])).keys()))"
	set theKeys to my runShellLines("/usr/bin/python3 -c " & quoted form of pyCode & " " & quoted form of tmpPath)
	do shell script "rm -f " & quoted form of tmpPath
	return theKeys
end jsonKeys

on run
	set out to {}

	set end of out to "== ① 换行符处理 =="
	set end of out to "默认模式（LF→CR）字符 id: " & my charIds(do shell script "printf 'a\\nb'")
	set end of out to "altering line endings false: " & my charIds(do shell script "printf 'a\\nb'" altering line endings false)
	set end of out to "runShell 结果: [" & (my replaceIn(my runShell("printf 'a\\nb\\n'"), linefeed, "⏎")) & "]"

	set end of out to ""
	set end of out to "== ② 执行者与环境 =="
	set end of out to "$0（实际 shell）: " & (my runShell("echo $0"))
	set end of out to "$SHELL（登录 shell）: " & (my runShell("echo $SHELL"))
	set end of out to "PATH: " & (text 1 thru (my minInt(90, length of (my runShell("echo $PATH")))) of (my runShell("echo $PATH"))) & "…"
	set end of out to "whoami: " & (my runShell("whoami"))
	set end of out to "system attribute USER: " & (system attribute "USER")

	set end of out to ""
	set end of out to "== ③ 引号转义（quoted form of）=="
	set weirdPath to "/tmp/a b'c\"d$e`f`.txt"
	set end of out to "原始路径: " & weirdPath
	set end of out to "quoted form of: " & (quoted form of weirdPath)
	-- 往返验证：写一个文件名带特殊字符的文件再读回来
	set roundTrip to my runShell("printf '%s' " & quoted form of weirdPath)
	set end of out to "shell 往返一致: " & ((roundTrip is weirdPath) as text)

	set end of out to ""
	set end of out to "== ④ 退出码与 stderr =="
	set okResult to my runShellFull("echo 正常输出; exit 0")
	set end of out to "成功: exit=" & (exitCode of okResult) & " stdout=[" & (stdout of okResult) & "]"
	set failResult to my runShellFull("echo 错误信息 >&2; echo 部分输出; exit 7")
	set end of out to "失败: exit=" & (exitCode of failResult) & " stdout=[" & (stdout of failResult) & "] stderr=[" & (stderr of failResult) & "]"
	try
		do shell script "exit 3"
	on error errMsg number errNum
		set end of out to "do shell script 直接抛错: number=" & errNum & "（= 进程退出码）"
	end try

	set end of out to ""
	set end of out to "== ⑤ JSON 往返 =="
	set theJSON to my toJsonString({"中文", "with \"quotes\"", "line1", "tab	here"})
	set end of out to "生成: " & theJSON
	set parsedKeys to my jsonKeys("{\"甲\":1,\"乙\":2,\"丙\":3}")
	set oldDelims2 to AppleScript's text item delimiters
	set AppleScript's text item delimiters to ", "
	set end of out to "jsonKeys 解析: " & (parsedKeys as text)
	set AppleScript's text item delimiters to oldDelims2

	set end of out to ""
	set end of out to "== ⑥ 大文本走临时文件而非命令行 =="
	set tmpScript to (POSIX path of (path to temporary items)) & "as_bridge_demo.py"
	set fh to open for access (POSIX file tmpScript) with write permission
	set eof of fh to 0
	write "import sys, json" & linefeed to fh as «class utf8»
	write "print(json.dumps({'sum': sum(int(x) for x in sys.argv[1:])}))" & linefeed to fh as «class utf8»
	close access fh
	set end of out to "python 计算 1+2+3: " & (my runShell("/usr/bin/python3 " & quoted form of tmpScript & " 1 2 3"))
	do shell script "rm -f " & quoted form of tmpScript

	set end of out to ""
	set end of out to "== ⑦ 管理员权限（此处只演示语法，不实际执行）=="
	set end of out to "  do shell script \"cmd\" with administrator privileges"
	set end of out to "  do shell script \"cmd\" with administrator privileges with prompt \"需要安装组件\""
	set end of out to "⚠️ 用户取消会抛 -128；定时任务里无法弹框，会直接失败"

	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set finalText to out as text
	set AppleScript's text item delimiters to oldDelims
	return finalText
end run

on charIds(theText)
	set codes to {}
	repeat with ch in (characters of theText)
		set end of codes to ((id of ch) as text)
	end repeat
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to ","
	set theResult to codes as text
	set AppleScript's text item delimiters to oldDelims
	return theResult
end charIds

on minInt(a, b)
	if a < b then return a
	return b
end minInt

-- 02-text-utils.applescript
-- 演示如何加载并使用 lib/stdlib.scpt 工具库。
--
-- 首次使用先编译工具库（stdlib 必须先编译成 .scpt，见 docs/16 §16.2⑱）：
--   osacompile -o lib/stdlib.scpt lib/stdlib.applescript
--
-- 运行：
--   osascript 02-text-utils.applescript

-- 本脚本所在目录（POSIX 路径，末尾带 /）
-- 用 path to me 定位，避免硬编码；osascript 直接跑纯文本脚本时同样有效
on ownDir()
	try
		set selfPOSIX to POSIX path of (path to me)
		return do shell script "dirname " & quoted form of selfPOSIX
	on error
		return do shell script "pwd"
	end try
end ownDir

on run argv
	set libDir to my ownDir()
	set libPath to libDir & "/lib/stdlib.scpt"

	if not (my plainFileExists(libPath)) then
		return "❌ 找不到 " & libPath & linefeed & ¬
			"请先执行：osacompile -o lib/stdlib.scpt lib/stdlib.applescript"
	end if

	set lib to load script (POSIX file libPath)
	set out to {}

	set end of out to "== 切分 / 拼接 / 替换 =="
	set end of out to "splitText: " & (lib's joinText(lib's splitText("2026-11-17", "-"), " | "))
	set end of out to "replaceText: " & (lib's replaceText("a-b-c", "-", "+"))
	set end of out to "joinText: " & (lib's joinText({"甲", "乙", "丙"}, "、"))

	set end of out to ""
	set end of out to "== 多分隔符切分 =="
	set csvLine to "姓名,年龄;城市 职业"
	set AppleScript's text item delimiters to {",", ";", " "}
	set multiParts to text items of csvLine
	set AppleScript's text item delimiters to ""
	set end of out to "输入: " & csvLine
	set end of out to "结果: " & (lib's joinText(multiParts, " / "))

	set end of out to ""
	set end of out to "== 修剪空白 =="
	set dirtyText to "  	带空白的文本 	
	"
	set end of out to "trimText: [" & (lib's trimText(dirtyText)) & "]"

	set end of out to ""
	set end of out to "== 按行切分（自动兼容 LF / CRLF / CR）=="
	set mixedText to "第一行" & return & linefeed & "第二行" & return & "第三行" & linefeed
	set theLines to lib's splitLines(mixedText)
	set end of out to "行数: " & (count of theLines)
	repeat with i from 1 to count of theLines
		set end of out to "  " & i & ": " & (item i of theLines)
	end repeat

	set end of out to ""
	set end of out to "== 文件名解析 =="
	repeat with fileName in {"photo.tar.gz", "report.pdf", "README", ".gitignore"}
		set theName to contents of fileName
		set end of out to theName & "  →  基名[" & (lib's fileBaseName(theName)) & "] 扩展名[" & (lib's fileExtension(theName)) & "]"
	end repeat

	set end of out to ""
	set end of out to "== 列表工具 =="
	set end of out to "uniqueList: " & (lib's joinText(lib's uniqueList({"a", "b", "a", "c", "b"}), ","))
	set end of out to "listContains(b): " & ((lib's listContains({"a", "b"}, "b")) as text)
	set end of out to "listContains(z): " & ((lib's listContains({"a", "b"}, "z")) as text)

	set end of out to ""
	set end of out to "== 补零与日期格式化 =="
	set end of out to "padLeft(7,2,'0'): " & (lib's padLeft(7, 2, "0"))
	set end of out to "padLeft(42,5,'*'): " & (lib's padLeft(42, 5, "*"))
	set nowDate to current date
	set end of out to "formatStamp:   " & (lib's formatStamp(nowDate))
	set end of out to "fileNameStamp: " & (lib's fileNameStamp(nowDate))
	set end of out to "startOfDay:    " & (lib's formatStamp(lib's startOfDay(nowDate)))
	set end of out to "startOfMonth:  " & (lib's formatStamp(lib's startOfMonth(nowDate)))

	set end of out to ""
	set end of out to "== 文件读写 =="
	set tmpPath to (POSIX path of (path to temporary items)) & "as_text_utils_demo.txt"
	lib's writeTextFile(tmpPath, "第一行" & linefeed & "第二行" & linefeed, false)
	lib's writeTextFile(tmpPath, "追加的第三行" & linefeed, true)
	set end of out to "写入路径: " & tmpPath
	set end of out to "fileExists: " & ((lib's fileExists(tmpPath)) as text)
	set end of out to "readLines 行数: " & (count of (lib's readLines(tmpPath)))
	set end of out to "内容: "
	set fileLines to lib's readLines(tmpPath)
	repeat with aLine in fileLines
		set end of out to "  | " & (contents of aLine)
	end repeat
	set end of out to "读取不存在的文件 → missing value? " & ¬
		(((lib's readTextFile("/tmp/这个文件一定不存在.txt")) is missing value) as text)
	do shell script "rm -f " & quoted form of tmpPath

	set end of out to ""
	set end of out to "== Shell 互操作 =="
	set end of out to "runShellLines(ls /usr/bin | head -3): "
	set shellLines to lib's runShellLines("ls /usr/bin | head -3")
	repeat with aLine in shellLines
		set end of out to "  | " & (contents of aLine)
	end repeat
	set end of out to "runShell 保留 LF: " & (lib's replaceText(lib's runShell("printf 'a\\nb'"), linefeed, "⏎"))

	return lib's joinText(out, linefeed)
end run

-- 不依赖 stdlib 的存在性检查（用于判断 stdlib 本身是否已编译）
on plainFileExists(posixPath)
	try
		do shell script "test -e " & quoted form of posixPath
		return true
	on error
		return false
	end try
end plainFileExists

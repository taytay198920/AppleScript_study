-- 03-batch-rename.applescript
-- 批量重命名文件：支持「加前缀」「加序号」「替换字符串」「改扩展名」四种模式。
-- 默认 dry-run（只打印不动手），确认无误后加 --apply 才真正改名。
--
-- 用法：
--   osascript 03-batch-rename.applescript <目录> <模式> [--apply]
--
-- 模式：
--   prefix:<前缀>            给文件名加前缀
--   number:<起始值>:<位数>    改成 序号_原名
--   replace:<旧>:<新>        替换文件名中的字符串
--   ext:<新扩展名>           统一改扩展名（不含点）
--
-- 示例：
--   osascript 03-batch-rename.applescript ~/Desktop/照片 'prefix:2026旅行_'
--   osascript 03-batch-rename.applescript ~/Desktop/照片 'number:1:3' --apply
--   osascript 03-batch-rename.applescript ~/Desktop/照片 'replace:IMG_:照片_'
--   osascript 03-batch-rename.applescript ~/Desktop/照片 'ext:jpg' --apply

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

-- 生成新名字
on newNameFor(originalName, modeSpec, theIndex, lib)
	set modeParts to lib's splitText(modeSpec, ":")
	set modeName to item 1 of modeParts
	set baseName to lib's fileBaseName(originalName)
	set theExt to lib's fileExtension(originalName)

	if modeName is "prefix" then
		if (count of modeParts) < 2 then error "prefix 模式需要一个参数：prefix:<前缀>"
		set finalName to (item 2 of modeParts) & originalName

	else if modeName is "number" then
		set startAt to 1
		set padWidth to 3
		if (count of modeParts) > 1 then set startAt to (item 2 of modeParts) as integer
		if (count of modeParts) > 2 then set padWidth to (item 3 of modeParts) as integer
		set seqText to lib's padLeft(startAt + theIndex - 1, padWidth, "0")
		set finalName to seqText & "_" & originalName

	else if modeName is "replace" then
		if (count of modeParts) < 3 then error "replace 模式需要两个参数：replace:<旧>:<新>"
		set finalName to lib's replaceText(originalName, item 2 of modeParts, item 3 of modeParts)

	else if modeName is "ext" then
		if (count of modeParts) < 2 then error "ext 模式需要一个参数：ext:<新扩展名>"
		set newExt to item 2 of modeParts
		if baseName ends with "." then
			set finalName to baseName & newExt
		else
			set finalName to baseName & "." & newExt
		end if

	else
		error "未知模式：" & modeName & "（可用 prefix / number / replace / ext）"
	end if

	return finalName
end newNameFor

on run argv
	set lib to my loadLib()
	set out to {}

	-- 解析参数
	if (count of argv) < 2 then
		return "用法: osascript 03-batch-rename.applescript <目录> <模式> [--apply]" & linefeed & ¬
			"模式: prefix:<前缀> | number:<起始>:<位数> | replace:<旧>:<新> | ext:<新扩展名>"
	end if

	set targetDirRaw to item 1 of argv
	set modeSpec to item 2 of argv
	set doApply to (count of argv) > 2 and (item 3 of argv) is "--apply"

	-- 展开 ~ 并规范化路径
	set targetDir to lib's runShell("cd " & quoted form of targetDirRaw & " && pwd -P")

	if not (lib's folderExists(targetDir)) then
		error "目录不存在：" & targetDir number -43
	end if

	-- 用 System Events 列文件（接受 POSIX 字符串，比 Finder 省事，也不会把 Finder 拉到前台）
	set fileNames to {}
	set allItemNames to {}
	tell application "System Events"
		set fileNames to name of every file of folder targetDir whose visible is true
		-- 目录里所有条目（含隐藏文件和子文件夹），用于冲突检测
		set allItemNames to name of every disk item of folder targetDir
	end tell

	if (count of fileNames) is 0 then
		return "目录里没有可见文件：" & targetDir
	end if

	set end of out to "目录: " & targetDir
	set end of out to "模式: " & modeSpec
	set end of out to "文件数: " & (count of fileNames)
	set end of out to "执行方式: " & (my pickText(doApply, "⚠️ 实际改名", "🔍 dry-run（只预览）"))
	set end of out to "----------------------------------------"

	set plannedCount to 0
	set skippedCount to 0
	set conflictCount to 0
	set targetNames to {}
	set outIndexes to {}        -- 记录每个文件对应的输出行号，便于冲突检测时回改

	repeat with i from 1 to count of fileNames
		set originalName to item i of fileNames
		set end of outIndexes to (count of out) + 1
		try
			set finalName to my newNameFor(originalName, modeSpec, i, lib)
		on error errMsg
			set end of out to "❌ " & originalName & " → 出错: " & errMsg
			set skippedCount to skippedCount + 1
			-- 占位，保持索引对齐
			set end of targetNames to missing value
			-- 出错就整体中止，避免改到一半
			set end of out to ""
			set end of out to "已中止，未做任何修改。"
			return lib's joinText(out, linefeed)
		end try

		if finalName is originalName then
			set end of out to "＝ " & originalName & "（无变化，跳过）"
			set skippedCount to skippedCount + 1
			set end of targetNames to missing value
		else
			set end of out to "→ " & originalName & "  =>  " & finalName
			set end of targetNames to finalName
			set plannedCount to plannedCount + 1
		end if
	end repeat

	-- 冲突检测：目标名不能撞上「目录里其他不会被改名腾出的条目」
	-- （包括隐藏文件、子文件夹，以及本轮不改名的文件）
	set freedNames to {}
	repeat with i from 1 to count of fileNames
		if (item i of targetNames) is not missing value then
			set end of freedNames to item i of fileNames
		end if
	end repeat

	set remainingNames to {}
	repeat with anItem in allItemNames
		set itemName_ to contents of anItem
		if not (lib's listContains(freedNames, itemName_)) then
			set end of remainingNames to itemName_
		end if
	end repeat

	repeat with i from 1 to count of targetNames
		set finalName to item i of targetNames
		if finalName is not missing value then
			set originalName to item i of fileNames
			set conflictReason to missing value
			if lib's listContains(remainingNames, finalName) then
				set conflictReason to "目标已存在"
			else
				-- 检查是否和其他计划改名的目标重名
				repeat with j from 1 to count of targetNames
					if j is not i and (item j of targetNames) is finalName then
						set conflictReason to "与 " & (item j of fileNames) & " 的目标名重复"
						exit repeat
					end if
				end repeat
			end if
			if conflictReason is not missing value then
				set item (item i of outIndexes) of out to ("⚠️ " & originalName & " → " & finalName & "（" & conflictReason & "，跳过）")
				set item i of targetNames to missing value
				set plannedCount to plannedCount - 1
				set conflictCount to conflictCount + 1
			end if
		end if
	end repeat

	set end of out to "----------------------------------------"
	set end of out to "计划改名: " & plannedCount & "  跳过: " & skippedCount & "  冲突: " & conflictCount

	if not doApply then
		set end of out to ""
		set end of out to "这是 dry-run，未修改任何文件。确认无误后加 --apply 重跑。"
		return lib's joinText(out, linefeed)
	end if

	if plannedCount is 0 then
		set end of out to "没有需要改名的文件。"
		return lib's joinText(out, linefeed)
	end if

	if conflictCount > 0 then
		set end of out to "⚠️ 存在 " & conflictCount & " 个命名冲突，已中止。请调整模式后重试。"
		return lib's joinText(out, linefeed)
	end if

	-- 实际执行。⚠️ 两阶段：先把所有文件改成临时名，再改成目标名，
	-- 避免 "a→b, b→c" 这类链式改名互相覆盖。
	set end of out to ""
	set end of out to "开始改名…"
	set renamedCount to 0

	repeat with i from 1 to count of fileNames
		set finalName to item i of targetNames
		if finalName is not missing value then
			set originalName to item i of fileNames
			set tempName to "__as_tmp_" & i & "__"
			try
				tell application "System Events"
					set name of file originalName of folder targetDir to tempName
				end tell
				set renamedCount to renamedCount + 1
			on error errMsg number errNum
				set end of out to "❌ 第一阶段失败 " & originalName & ": " & errMsg & " (#" & errNum & ")"
			end try
		end if
	end repeat

	repeat with i from 1 to count of fileNames
		set finalName to item i of targetNames
		if finalName is not missing value then
			set tempName to "__as_tmp_" & i & "__"
			try
				tell application "System Events"
					set name of file tempName of folder targetDir to finalName
				end tell
			on error errMsg number errNum
				set end of out to "❌ 第二阶段失败 " & tempName & " → " & finalName & ": " & errMsg & " (#" & errNum & ")"
			end try
		end if
	end repeat

	set end of out to "✅ 完成，共处理 " & renamedCount & " 个文件。"
	return lib's joinText(out, linefeed)
end run

-- 三元表达式的替代写法（AppleScript 没有三元运算符）
-- ⚠️ 不要把这个 handler 命名为 choose —— 会和 Standard Additions 的
--    choose file / choose folder / choose from list / choose color 撞车，
--    编译器会报 "Expected "," but found identifier" (-2741)
on pickText(condition, trueValue, falseValue)
	if condition then return trueValue
	return falseValue
end pickText

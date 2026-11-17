-- 05-daily-backup.applescript
-- 定时备份文件夹：用 ditto 做带时间戳的快照，只保留最近 N 份，并写日志 + 发通知。
-- 对应 docs/09 §9.5、docs/12 §12.3、docs/15 §15.3
--
-- 用法：
--   osascript 05-daily-backup.applescript <源目录> <备份根目录> [--keep N] [--dry-run]
--
-- 示例：
--   osascript 05-daily-backup.applescript ~/Documents ~/Backups/docs --keep 7
--   osascript 05-daily-backup.applescript ~/Documents ~/Backups/docs --dry-run
--
-- 说明：
--   每次运行在 <备份根目录> 下建一个 YYYY-MM-DD_HHMMSS 子目录，把源目录 ditto 进去。
--   超过 --keep 份数的旧快照会被删除（按目录名时间排序）。
--   日志写到 <备份根目录>/backup.log。

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

-- 把 ~ 展开成绝对路径
on expandTilde(p)
	if p starts with "~/" then
		return (POSIX path of (path to home folder)) & (text 3 thru -1 of p)
	else if p is "~" then
		return POSIX path of (path to home folder)
	end if
	return p
end expandTilde

-- 去掉末尾斜杠，避免 ditto 路径歧义
on stripTrailingSlash(p)
	if (length of p) > 1 and p ends with "/" then return text 1 thru -2 of p
	return p
end stripTrailingSlash

on parseArgs(argv)
	set opts to {srcPath:"", dstRoot:"", keepCount:5, dryRun:false}
	set positional to {}
	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--keep" then
			set i to i + 1
			if i > (count of argv) then error "--keep 后面要跟一个数字"
			set keepCount of opts to (item i of argv) as integer
		else if a is "--dry-run" then
			set dryRun of opts to true
		else if a starts with "--" then
			error "未知参数：" & a
		else
			set end of positional to a
		end if
		set i to i + 1
	end repeat

	if (count of positional) < 2 then
		error "用法：osascript 05-daily-backup.applescript <源目录> <备份根目录> [--keep N] [--dry-run]"
	end if
	set srcPath of opts to my stripTrailingSlash(my expandTilde(item 1 of positional))
	set dstRoot of opts to my stripTrailingSlash(my expandTilde(item 2 of positional))
	return opts
end parseArgs

on run argv
	set lib to my loadLib()
	set opts to my parseArgs(argv)

	set srcPath to srcPath of opts
	set dstRoot to dstRoot of opts
	set keepCount to keepCount of opts
	set dryRun to dryRun of opts

	-- 1) 前置检查
	if not (lib's folderExists(srcPath)) then
		error "源目录不存在：" & srcPath
	end if
	set logPath to dstRoot & "/backup.log"
	set stamp to lib's fileNameStamp(current date)
	set snapshotDir to dstRoot & "/" & stamp
	set report to {}

	-- dry-run 保证零副作用：不建目录、不写日志、不删东西
	if not dryRun then
		if not (lib's folderExists(dstRoot)) then
			do shell script "mkdir -p " & quoted form of dstRoot
		end if
		lib's appendLogFile(logPath, "===== 开始备份 " & stamp & " =====")
		lib's appendLogFile(logPath, "源目录: " & srcPath)
		lib's appendLogFile(logPath, "快照目录: " & snapshotDir)
	end if

	if dryRun then
		set end of report to "[dry-run] 不会真正执行"
		set end of report to "  ditto " & srcPath & " → " & snapshotDir
	else
		-- 2) 执行备份。ditto 保留元数据、ACL、资源分叉，比 cp 更适合备份
		set dittoCmd to "ditto " & quoted form of srcPath & " " & quoted form of snapshotDir
		try
			do shell script dittoCmd
			lib's appendLogFile(logPath, "ditto 成功")
		on error errMsg number errNum
			lib's appendLogFile(logPath, "ditto 失败 (" & errNum & "): " & errMsg)
			lib's notify("备份失败", errMsg)
			error "备份失败：" & errMsg number errNum
		end try
	end if

	-- 3) 清理旧快照：只保留最近 keepCount 份
	--    目录名就是时间戳，字典序 == 时间序，所以 sort 后砍前面的
	set allSnapshots to {}
	if not dryRun then set allSnapshots to my listSnapshotDirs(dstRoot)
	set toDelete to {}
	if (count of allSnapshots) > keepCount then
		repeat with k from 1 to ((count of allSnapshots) - keepCount)
			set end of toDelete to item k of allSnapshots
		end repeat
	end if

	repeat with oldDir in toDelete
		set oldPath to dstRoot & "/" & oldDir
		if dryRun then
			set end of report to "[dry-run] 将删除旧快照: " & oldDir
		else
			try
				do shell script "rm -rf " & quoted form of oldPath
				lib's appendLogFile(logPath, "已删除旧快照: " & oldDir)
				set end of report to "已删除旧快照: " & oldDir
			on error errMsg
				lib's appendLogFile(logPath, "删除失败 " & oldDir & ": " & errMsg)
				set end of report to "⚠️ 删除失败: " & oldDir
			end try
		end if
	end repeat

	-- 4) 统计与汇报
	set sizeText to "?"
	if not dryRun then
		try
			set sizeText to do shell script "du -sh " & quoted form of snapshotDir & " | cut -f1"
		end try
	end if

	set end of report to "快照目录: " & snapshotDir
	set end of report to "占用空间: " & sizeText
	set end of report to "保留份数: " & keepCount & "（当前 " & (count of allSnapshots) & " 份）"
	if not dryRun then set end of report to "日志: " & logPath

	if not dryRun then
		lib's appendLogFile(logPath, "完成，占用 " & sizeText)
		lib's notify("备份完成", srcPath & " → " & stamp)
	end if

	set AppleScript's text item delimiters to linefeed
	set finalText to report as text
	set AppleScript's text item delimiters to ""
	return finalText
end run

-- 列出备份根目录下所有「看起来像时间戳快照」的子目录，按名字升序。
-- 快照名格式来自 stdlib 的 fileNameStamp：YYYYMMDD-HHMMSS
--
-- ⚠️ 两个实测踩过的坑，别改回去：
--   1) do shell script 的输出用 CR(return) 分隔，不是 LF(linefeed)。
--      用 linefeed 切会得到「整坨一个元素」。见 docs/16 §16.2。
--   2) 千万别用 result 当累加变量。result 是隐式全局，每条语句执行后
--      都会被自动覆盖。见 docs/16 §16.1③。
on listSnapshotDirs(dstRoot)
	set rawText to do shell script ¬
		"ls -1 " & quoted form of dstRoot & " 2>/dev/null | grep -E '^[0-9]{8}-[0-9]{6}$' | sort"
	set AppleScript's text item delimiters to return
	set theList to text items of rawText
	set AppleScript's text item delimiters to ""
	set theResult to {}
	repeat with anItem in theList
		set t to anItem as text
		if t is not "" then set end of theResult to t
	end repeat
	return theResult
end listSnapshotDirs

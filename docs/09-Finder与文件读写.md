# 09 Finder 与文件读写

## 9.1 三种路径表示（务必分清）

AppleScript 里同一个文件有三种写法，混用是最常见的 bug 来源：

| 类型 | 示例 | 说明 |
| --- | --- | --- |
| **POSIX 路径** | `/Users/taylor/Desktop/a.txt` | Unix 风格，text 类型 |
| **HFS 路径** | `Macintosh HD:Users:taylor:Desktop:a.txt` | 经典 Mac 风格，冒号分隔，text 类型 |
| **alias** | （对象，不是字符串） | 实时解析，文件移动后仍能找到 |

### 互转

```applescript
-- POSIX → HFS
POSIX file "/Users/taylor/Desktop" as text
--> "Macintosh HD:Users:taylor:Desktop:"      ⚠️ 末尾带冒号（表示这是文件夹）

-- HFS → POSIX
POSIX path of "Macintosh HD:Users:taylor:Desktop:"
--> "/Users/taylor/Desktop/"

-- POSIX → alias（文件必须存在，否则报错）
POSIX file "/Users/taylor/Desktop/a.txt" as alias

-- POSIX → file 对象（文件可以不存在，用于写入新文件）
POSIX file "/Users/taylor/Desktop/new.txt"
```

⚠️ **`as alias` 要求文件已存在**，不存在会抛 `-1728`。要创建新文件，用不带 `as alias` 的 `POSIX file`。

⚠️ **HFS 路径里文件夹末尾的冒号有意义**，写 `open for access file "Macintosh HD:tmp:x.txt"`
和 `"Macintosh HD:tmp:x.txt:"` 是不同的东西。

### 符号链接的坑

⚠️ `/tmp` 实际是指向 `/private/tmp` 的符号链接。Finder 对 `POSIX file "/tmp/x"` 有时会解析失败
（报 `-43 wasn't found`）。**给 Finder 用的路径请写解析后的真实路径** `/private/tmp/x`。

获取真实路径：

```applescript
set realPath to do shell script "readlink -f " & quoted form of "/tmp/asv"
```

## 9.2 标准路径：`path to`

不要硬编码 `/Users/xxx/`，用 `path to`（实测结果）：

```applescript
path to home folder                 --> alias "Macintosh HD:Users:taylor:"
path to desktop folder              --> …/taylor/Desktop/
path to documents folder            --> …/taylor/Documents/
path to downloads folder            --> …/taylor/Downloads/
path to temporary items             --> /private/var/folders/…/TemporaryItems/
path to preferences folder          --> …/taylor/Library/Preferences/
path to scripts folder              --> …/taylor/Library/Scripts/
path to application support folder  --> /Library/Application Support/
path to me                          --> 当前脚本自身（仅编译后的脚本可靠）
path to application "Safari"        --> App 的 alias
```

转成 POSIX：

```applescript
set desktopPOSIX to POSIX path of (path to desktop folder)
--> "/Users/taylor/Desktop/"
```

⚠️ `path to application support folder` 默认返回**系统级**目录。要用户级的：

```applescript
path to application support folder from user domain
```

其他可加的域：`from local domain`、`from system domain`、`from network domain`。

⚠️ 实测 `path to application "Safari"` 在 macOS 26 上返回
`/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/`（系统卷的 cryptex 路径）。
能用，但别拿它做字符串比较，用 `alias` 直接传给命令。

## 9.3 文件读写（Standard Additions）

### 基本模式

```applescript
set theFile to "/tmp/demo.txt"

-- 写入
set fh to open for access (POSIX file theFile) with write permission
set eof of fh to 0                                    -- 清空原内容（追加则不要这行）
write "第一行" & linefeed to fh as «class utf8»
close access fh

-- 读取
set content to read (POSIX file theFile) as «class utf8»
```

⚠️⚠️ **三条必守规则**：

1. **一定要 `close access`**，否则句柄泄漏，后续 `open for access` 会报 `-49`/`-50`。
   放在 `try` 里并在 `on error` 分支兜底关闭：

```applescript
set fh to missing value
try
	set fh to open for access (POSIX file theFile) with write permission
	write theText to fh starting at eof as «class utf8»
	close access fh
on error errMsg number errNum
	if fh is not missing value then
		try
			close access fh
		end try
	end if
	error errMsg number errNum
end try
```

2. **一定要指定 `as «class utf8»`**，否则中文会按 MacRoman 编码写出，变成乱码。
3. **一定要用 `linefeed`（`\n`）而不是 `return`（`\r`）** 给 Unix 工具消费的文件换行。

### 追加写入

```applescript
write ("新内容" & linefeed) to fh starting at eof as «class utf8»
```

⚠️ `starting at eof` 是追加；不加就是覆盖当前位置。

### 按行读取（推荐）

`read` 自带分隔符参数，比先读全部再 `text items of` 更省内存（实测）：

```applescript
set fh to open for access (POSIX file theFile)
set allLines to read fh using delimiter linefeed as «class utf8»     -- 直接返回 list
close access fh

count of allLines     --> 3
item 1 of allLines    --> "alpha"
```

⚠️⚠️ **`using delimiter` 不会自动继承编码**，漏写 `as «class utf8»` 时会按 MacRoman 解码，
中文全部变成乱码（实测 `"第二行"` → `"Á¨¬‰∫åË°å"`）。两种参数顺序都可以：

```applescript
read fh using delimiter linefeed as «class utf8»     -- ✅
read fh as «class utf8» using delimiter linefeed     -- ✅ 等价
```

⚠️ 文件最后一行如果以换行结尾，结果列表末尾可能多出一个 `""`，用之前先过滤。

也可以用 `using delimiters`（复数，多个分隔符）：

```applescript
read fh using delimiters {linefeed, return, tab}
```

### 读取字节范围

```applescript
set fh to open for access (POSIX file theFile)
set chunk to read fh from 1 for 5      -- 从第 1 字节起读 5 字节 → "alpha"
close access fh
```

⚠️ 位置从 **1** 开始。`from`/`to` 是字节偏移，对多字节字符（中文）要小心，
建议配合 `read … as «class utf8»` 使用字符而非字节。

### 大文件请交给 Shell

⚠️ AppleScript 的 `read` 会把整个文件载入内存并转成 AppleScript text，几十 MB 以上就会很慢。
大文件处理请用 `do shell script` 调 `grep`/`awk`/`sed`/`python3`。

## 9.4 `info for` vs Finder

获取文件信息有两条路：

```applescript
-- 方式 A：info for（Standard Additions，不启动 Finder，快）
set inf to info for (POSIX file "/tmp/asv/ftest/a.txt")
name of inf              --> "a.txt"
size of inf              --> 1
name extension of inf    --> "txt"
folder of inf            --> false
creation date of inf     --> date …

-- 方式 B：Finder（功能更全，但慢，且会启动 Finder）
tell application "Finder"
	set f to file (POSIX file "/tmp/asv/ftest/a.txt" as alias)
	name of f
	kind of f              --> "Plain Text Document"（本地化，随系统语言变化）
	comment of f
	locked of f
end tell
```

**能用 `info for` 就用 `info for`**，只有在需要 Finder 特有功能（标签、注释、锁定、Finder 窗口操作）时才 `tell Finder`。

⚠️ `info for` 官方已标记为 deprecated，但目前仍然可用且稳定。

## 9.5 Finder 文件操作

### 枚举

```applescript
set theFolder to POSIX file "/Users/taylor/Desktop/工作" as alias

tell application "Finder"
	set allItems to every item of theFolder          -- 文件 + 文件夹
	set onlyFiles to every file of theFolder
	set onlyDirs to every folder of theFolder
	set theNames to name of every file of theFolder  -- 直接拿名字列表（一次事件）
	set theSizes to size of every file of theFolder
	set theExts to name extension of every file of theFolder
end tell
```

⚠️⚠️ **`count of items of <alias>` 会报 `-1727 Expected a reference`**（实测）。可靠写法：

```applescript
-- ✅ 用 HFS 路径 + folder
tell application "Finder"
	set n to count of (items of folder "Macintosh HD:private:tmp:asv:ftest:")
end tell

-- ✅ 或先取列表再 count
tell application "Finder"
	set theList to every item of theFolder
end tell
set n to count of theList

-- ❌ 下面两种都会报 -1727
tell application "Finder"
	count items of theFolder
	count of (every item of theFolder)
end tell
```

### 增删改

```applescript
tell application "Finder"
	-- 新建文件夹
	set newFolder to make new folder at theFolder with properties {name:"新建"}

	-- 新建空文件（Finder 没有 "make new file" 的可靠方式，推荐用 write）
	-- 见下方 ⚠️

	-- 重命名
	set name of newFolder to "改名后"
	set renamed to folder "改名后" of theFolder      -- ⚠️ 必须重新取引用

	-- 复制
	set dup to duplicate renamed to theFolder with replacing

	-- 移动
	move (folder "改名后" of theFolder) to someOtherFolder

	-- 删除（移到废纸篓，可恢复）
	delete renamed
end tell
```

⚠️ `make new file at … with properties {name:"x.txt"}` 创建的是**没有内容、可能没有扩展名**的
document file，行为随系统版本变化。要创建文本文件，请用 §9.3 的 `open for access` + `write`，
或 `do shell script "touch …"`。

⚠️ **`delete` 是移到废纸篓**，不是真删。真要删用：

```applescript
do shell script "rm " & quoted form of posixPath
```

### whose 过滤

```applescript
tell application "Finder"
	set logs to name of (every file of theFolder whose name extension is "log")
	set bigFiles to name of (every file of theFolder whose size > 104857600)
end tell
```

⚠️⚠️ **不要把 `whose` 的结果存进变量后再取 `name of`**（实测报 `-1728`）：

```applescript
-- ❌
set logs to (every file of theFolder whose name extension is "log")
set logNames to name of logs        -- Can't get name of {document file …} (-1728)

-- ✅ 内联写
set logNames to name of (every file of theFolder whose name extension is "log")

-- ✅ 或者手动循环
set logs to (every file of theFolder whose name extension is "log")
set logNames to {}
repeat with f in logs
	set end of logNames to (name of f)
end repeat
```

### 磁盘信息

```applescript
tell application "Finder"
	set diskName to name of startup disk           --> "Macintosh HD"
	set freeBytes to free space of startup disk    --> 3.61436904375E+11（实数）
end tell
```

⚠️ `free space` 返回实数且可能是科学计数法，显示前要格式化（见 `docs/04` §4.7）。

### 不启动 Finder 的替代方案

System Events 也提供文件操作，且不会把 Finder 拉到前台：

```applescript
tell application "System Events"
	set fileExists to exists file "/tmp/asv/ftest/a.txt"     -- ⚠️ POSIX 字符串；且别用它判断「不存在」，见下方警告
	set theFiles to name of every file of folder "/tmp/asv/ftest"
	make new folder at folder "/tmp/asv" with properties {name:"newDir"}
end tell
```

⚠️ System Events 的 `exists file "…"` 接受 **POSIX 字符串**，写起来比 Finder 方便。

⚠️⚠️ **但别用它判断「文件不存在」**。本机实测：在 TCC 保护目录
（`~/Desktop`、`~/Documents`、`~/Downloads` 等）里查询一个**不存在**的文件时，
System Events 会**无限挂起**——不返回、不报错、也不超时，而且会连带把
System Events 整个卡死，之后所有 Apple Event 都无响应，只能
`killall "System Events"` 才能恢复（launchd 会自动重新拉起）。

| 查询 | 实测结果 |
| --- | --- |
| `/Users/…/Desktop/applescript/README.md`（存在） | `true`，正常 |
| `/Users/…/Desktop/applescript/nope-xyz`（不存在） | ⚠️⚠️ **挂起，System Events 卡死** |
| `/tmp/nope-xyz`（不存在，非保护目录） | `false`，正常 |
| `/Users/taylor/nope-xyz`（不存在，家目录根） | `false`，正常 |
| `README.md`（相对路径） | `false`（不解析相对路径，不挂起） |

⚠️ **加 `with timeout` 也救不回来**。本机复测：把查询包进 `with timeout of 6 seconds`，
6 秒后拿到的是 `System Events got an error: AppleEvent timed out. (-1712)`，
而 System Events 依然处于卡死状态——**紧接着的下一个 Apple Event 也照样 -1712**
（连 `name of first process whose frontmost is true` 这种最轻的查询都不回）。
只有 `killall "System Events"` 之后才立刻恢复正常。

```bash
# 怀疑 System Events 被自己卡死时：先健康检查，再重启它
osascript -e 'with timeout of 5 seconds' \
          -e 'tell application "System Events" to name of first process whose frontmost is true' \
          -e 'end timeout'      # 5 秒内不回 → 卡死了
killall "System Events"         # launchd 会自动重新拉起，无需手动启动
```

**判断文件是否存在请用 shell**，行为确定、速度快，而且相对路径也能正确解析：

```applescript
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
```
✅ 本机实测：7 种路径组合全部返回正确结果，总耗时约 1.9 秒。

⚠️ **不要用 `open for access` 来判断文件是否存在。** 它会在文件不存在时
**直接把文件创建出来**（实测生成了一个 0 字节文件），是个有副作用的「查询」。

System Events 的文件能力仍然值得用，只是**避开 `exists file`/`exists folder`**：
`name of every file of folder …`、`make new folder`、`property list file` 都没问题（§10.4）。

## 9.6 完整示例：安全地写一个文本文件

```applescript
on writeTextFile(posixPath, theText, appendMode)
	set fileRef to POSIX file posixPath
	set fh to missing value
	try
		set fh to open for access fileRef with write permission
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
		log "写入失败 " & posixPath & ": " & errMsg & " (#" & errNum & ")"
		return false
	end try
end writeTextFile

on readTextFile(posixPath)
	set fileRef to POSIX file posixPath
	set fh to missing value
	try
		set fh to open for access fileRef
		set theText to read fh as «class utf8»
		close access fh
		return theText
	on error errMsg number errNum
		if fh is not missing value then
			try
				close access fh
			end try
		end if
		if errNum is -39 or errNum is -43 then return missing value   -- 文件不存在
		error errMsg number errNum
	end try
end readTextFile

-- ⚠️ 不用 System Events 的 exists file：查「不存在的文件」且在 TCC 保护目录里
-- 会无限挂起并卡死 System Events（见 §9.5）。用 shell 的 test 代替。
on fileExists(posixPath)
	try
		return (do shell script "test -f " & quoted form of posixPath & " && echo yes || echo no") is "yes"
	on error
		return false
	end try
end fileExists
```

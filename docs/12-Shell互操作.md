# 12 Shell 互操作

`do shell script` 是 AppleScript 最重要的「逃生舱」：文本处理、正则、JSON、网络、
文件批量操作，凡是 AppleScript 自己做不好的，都可以交给 Unix 工具。

## 12.1 基本用法

```applescript
do shell script "echo hello"                 --> "hello"
do shell script "ls /tmp"                    --> 多行文本
do shell script "whoami"                     --> 当前用户名
```

### ⚠️ 用的是 `/bin/sh`，不是你的登录 shell

实测：

```applescript
do shell script "echo $SHELL"    --> "/bin/zsh"   ← 环境变量继承
do shell script "echo $0"        --> "sh"         ← 实际执行者是 /bin/sh
```

所以**不能用 zsh/bash 特有的语法**：

```bash
# ❌ 这些在 /bin/sh 下会失败
[[ -f x ]]              # 用 [ -f x ]
echo ${var//a/b}        # 用 sed
arr=(1 2 3)             # 不支持数组
source ./x.sh           # 用 . ./x.sh
```

要用 bash/zsh，显式指定：

```applescript
do shell script "/bin/zsh -lc " & quoted form of "echo ${PATH}"
do shell script "/bin/bash -c " & quoted form of "arr=(1 2 3); echo ${arr[1]}"
```

⚠️ `-l`（login shell）会加载 `.zprofile`/`.bash_profile`，慢一些但能拿到你配置的 PATH。
定时任务里尤其需要（见下）。

### ⚠️ PATH 极简

从 `launchd` 或无终端环境调用时，PATH 通常只有 `/usr/bin:/bin:/usr/sbin:/sbin`。
Homebrew（`/opt/homebrew/bin`）、pyenv、nvm 装的工具都找不到。

```applescript
-- 方案 1：写绝对路径（最稳）
do shell script "/opt/homebrew/bin/jq --version"

-- 方案 2：显式设置 PATH
do shell script "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; mycommand"

-- 方案 3：用 login shell
do shell script "/bin/zsh -lc " & quoted form of "mycommand"
```

## 12.2 ⚠️ 换行符会被改写（大坑）

实测：Shell 输出的 `\n`（LF，id 10）会被换成 `\r`（CR，id 13），末尾换行被去掉。

```applescript
do shell script "printf 'a\\nb'"
-- 得到 3 个字符，id 依次是 97, 13, 98   ⚠️ 13 是 CR 不是 LF
```

后果：直接按 `linefeed` 切分会切不开。

**解决方案一：关掉转换**

```applescript
do shell script "printf 'a\\nb'" altering line endings false
-- 得到 id 97, 10, 98   ✅ 标准 LF
```

⚠️⚠️ **副作用：`altering line endings false` 会保留输出末尾的换行符。**
实测 `do shell script "pwd" altering line endings false` 得到的是 `"/private/tmp/asv/rename\n"`
（长度 24，末尾 id 10），而默认模式下末尾换行会被剥掉（长度 23）。

后果很隐蔽：

```applescript
set targetDir to do shell script "cd " & quoted form of userDir & " && pwd -P" altering line endings false
folderExists(targetDir)     -- ❌ false！因为路径尾巴上带了个 \n
```

**用 `altering line endings false` 时必须自己 trim 末尾换行**：

```applescript
on trimLineEnds(theText)
	set charList to characters of theText
	set eolChars to {linefeed, return}
	repeat while (count of charList) > 0 and (item -1 of charList) is in eolChars
		set charList to item 1 thru -2 of charList
	end repeat
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to ""
	set theResult to charList as text
	set AppleScript's text item delimiters to oldDelims
	return theResult
end trimLineEnds
```

（`examples/lib/stdlib.applescript` 里的 `runShell` 已经内置了这个处理。）

**解决方案二：按 CR 切分**

```applescript
set AppleScript's text item delimiters to return      -- 注意是 return，不是 linefeed
set theLines to text items of (do shell script "ls /tmp")
set AppleScript's text item delimiters to ""
```

**解决方案三：先规范化**

```applescript
on shellLines(cmd)
	set rawResult to do shell script cmd altering line endings false
	set AppleScript's text item delimiters to linefeed
	set theLines to text items of rawResult
	set AppleScript's text item delimiters to ""
	-- 去掉末尾可能的空行
	if (count of theLines) > 0 and (item -1 of theLines) is "" then
		set theLines to item 1 thru -2 of theLines
	end if
	return theLines
end shellLines
```

## 12.3 stdout / stderr / 退出码

| 项目 | 行为 |
| --- | --- |
| stdout | 作为返回值 |
| stderr | ⚠️ **被丢弃**，不会返回也不会显示 |
| 退出码 0 | 正常返回 |
| 退出码非 0 | 抛错，**错误码 = 退出码**（实测 `exit 3` → `on error … number 3`） |

```applescript
try
	set theResult to do shell script "someCommand"
on error errMsg number errNum
	-- errNum 就是进程退出码（也可能是 AppleScript 自己的错误码，如 -128）
	log "命令失败，退出码 " & errNum & "：" & errMsg
end try
```

⚠️ **要拿到 stderr，必须在 shell 里重定向**：

```applescript
-- 合并到 stdout
set output to do shell script "mycommand 2>&1"

-- 或者分别写到临时文件
do shell script "mycommand > /tmp/out.txt 2> /tmp/err.txt; true"
set outText to read (POSIX file "/tmp/out.txt") as «class utf8»
set errText to read (POSIX file "/tmp/err.txt") as «class utf8»
```

⚠️ 命令失败时 `2>&1` 的内容可能拿不到（因为抛错了）。用 `; true` 或 `|| true` 强制退出码为 0：

```applescript
set output to do shell script "mycommand 2>&1 || true"
```

## 12.4 引号与注入防护（必做）

⚠️⚠️ **永远不要手工拼接用户输入到 shell 命令里。**

```applescript
-- ❌ 危险：文件名含单引号或 $() 就会被注入
do shell script "rm " & userPath

-- ✅ 用 quoted form of
do shell script "rm " & quoted form of userPath
```

`quoted form of` 实测效果：

```applescript
quoted form of "/tmp/a b.txt"     --> "'/tmp/a b.txt'"
quoted form of "a'b\"c d$e`f`"    --> "'a'\\''b\"c d$e`f`'"   ✅ 安全
```

它会正确处理单引号、双引号、`$`、反引号、空格。

### 更安全的做法：用参数而不是拼接

```applescript
-- ❌ 拼接
do shell script "grep " & quoted form of pattern & " " & quoted form of filePath

-- ✅ 把数据写进临时文件，或用 stdin
do shell script "cat " & quoted form of filePath & " | grep -F -- " & quoted form of pattern
```

`grep -F` 表示按字面字符串匹配，不当正则解释；`--` 表示后面的不是选项，防止文件名以 `-` 开头被误解析。

### 传大量数据：走临时文件

```applescript
on runPython(scriptText, inputData)
	set tmpScript to (POSIX path of (path to temporary items)) & "as_py_" & (do shell script "echo $RANDOM") & ".py"
	set tmpData to tmpScript & ".json"
	my writeTextFile(tmpScript, scriptText, false)
	my writeTextFile(tmpData, inputData, false)
	set theResult to do shell script "/usr/bin/python3 " & quoted form of tmpScript & " " & quoted form of tmpData
	do shell script "rm -f " & quoted form of tmpScript & " " & quoted form of tmpData
	return theResult
end runPython
```

## 12.5 管理员权限

```applescript
do shell script "mkdir -p /usr/local/myapp" with administrator privileges
```

会弹出系统的密码框。可以定制提示语和指定账号：

```applescript
do shell script "someCommand" with administrator privileges with prompt "需要安装组件"

-- ⚠️ 不要在代码里硬编码密码
do shell script "someCommand" with administrator privileges user name "admin" password thePassword
```

⚠️ 注意事项：

- 用户点「取消」会抛 **-128**，要处理。
- 一次授权只对**这一条命令**有效，连续多条提权命令会连续弹框。
  把多条命令合并成一条 `sh -c` 调用。
- **定时任务里无法弹框**（没有交互会话），提权命令会直接失败。
  这类任务应改用 `sudoers` 里的免密规则，或用 root 权限的 launchd daemon。

## 12.6 AppleScript ← Shell 反向调用

### Shell 里跑 AppleScript

```bash
# 单行
osascript -e 'tell app "Finder" to activate'

# 传参（推荐，避免引号地狱）
osascript myscript.applescript "$1" "$2"

# heredoc
osascript - "$NAME" <<'EOF'
on run argv
	return "hello " & (item 1 of argv)
end run
EOF
```

### 让 AppleScript 输出 JSON 给 Shell 消费

```applescript
on jsonEscape(s)
	set s to my replaceText(s, "\\", "\\\\")
	set s to my replaceText(s, "\"", "\\\"")
	set s to my replaceText(s, linefeed, "\\n")
	set s to my replaceText(s, return, "\\n")
	set s to my replaceText(s, tab, "\\t")
	return s
end jsonEscape

on toJson(pairs)
	set parts to {}
	repeat with p in pairs
		set k to item 1 of (contents of p)
		set v to item 2 of (contents of p)
		set end of parts to "\"" & my jsonEscape(k) & "\":\"" & my jsonEscape(v) & "\""
	end repeat
	set AppleScript's text item delimiters to ", "
	set body to parts as text
	set AppleScript's text item delimiters to ""
	return "{" & body & "}"
end toJson
```

```bash
osascript -s s report.applescript | jq -r '.name'
```

⚠️ 如果数据结构复杂，**直接让 AppleScript 调 `python3` 生成 JSON** 比手写转义可靠得多：

```applescript
set theJSON to do shell script "/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' " ¬
	& quoted form of valueA & " " & quoted form of valueB
```

## 12.7 什么时候用 Shell，什么时候用原生

| 任务 | 推荐 | 理由 |
| --- | --- | --- |
| 递归列文件 | `do shell script "find …"` | Finder 递归枚举极慢 |
| 批量重命名 | Shell `mv` 或 Finder（要撤销支持时用 Finder） | Shell 快，Finder 可撤销 |
| 读写小文本文件 | 原生 `read`/`write` | 无需转义，编码可控 |
| 处理大文件/日志 | Shell（`grep`/`awk`/`sed`） | AppleScript 会全量载入内存 |
| JSON / HTTP | Shell（`curl` + `python3`/`jq`） | AppleScript 原生支持很差 |
| 压缩打包 | Shell（`zip`/`tar`/`ditto`） | 简单可靠 |
| 控制 App | 原生 `tell` | Shell 做不到 |
| 需要撤销/废纸篓 | 原生 Finder | Shell 的 `rm` 不可恢复 |

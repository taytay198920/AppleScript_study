# 14 常用 App 自动化

本章的属性名/命令名全部取自本机 macOS 26.6 的 `sdef` 输出，可直接照抄。

⚠️ **通用前提**：第一次控制某个 App，macOS 会弹「xxx 想要控制 yyy」授权框。
点了「不允许」之后脚本会报 `-1743`，需要去 **系统设置 → 隐私与安全性 → 自动化** 手动打开。
详见 `docs/15-打包-定时任务与权限.md`。

---

## 14.1 Safari

字典路径：`/Applications/Safari.app`（⚠️ 不在 `/System/Applications`）

**类**：`tab`
**命令**：`do JavaScript`、`email contents`、`search the web`、`show bookmarks`、`add reading list item`

```applescript
tell application "Safari"
	activate

	-- 打开新标签页
	tell window 1
		set current tab to (make new tab with properties {URL:"https://example.com"})
	end tell

	-- 没有窗口时先建一个
	if (count of windows) is 0 then make new document with properties {URL:"https://example.com"}

	-- 读取当前页
	set theURL to URL of current tab of window 1
	set theTitle to name of current tab of window 1
	set pageText to text of document 1              -- 页面纯文本
	set pageHTML to source of document 1           -- 页面 HTML 源码

	-- 遍历所有窗口的所有标签页
	set allTabs to {}
	repeat with w in windows
		repeat with t in tabs of w
			set end of allTabs to {name of t, URL of t}
		end repeat
	end repeat

	-- 执行 JavaScript
	do JavaScript "document.title" in current tab of window 1

	-- 关闭标签页 / 切换
	close current tab of window 1
	set current tab of window 1 to tab 2 of window 1
end tell
```

**tab 的属性**（sdef 实测）：`name`、`URL`、`index`、`visible`
**document 的属性**：`source`（HTML）、`text`（纯文本）、`URL`

⚠️ **`do JavaScript` 默认被禁用**。需要在 Safari 里手动打开：
Safari → 设置 → 高级 → 勾选「在菜单栏中显示"开发"菜单」，
然后 开发菜单 → 勾选「允许 JavaScript from Apple Events」。
不打开会报 `-1751` 或提示需要在开发菜单中启用。

⚠️ `text of document 1` 对未加载完成的页面会返回空或抛错。等待加载：

```applescript
on waitUntilLoaded(maxSeconds)
	set deadline to (current date) + maxSeconds
	tell application "Safari"
		repeat while (current date) < deadline
			try
				if (do JavaScript "document.readyState" in current tab of window 1) is "complete" then return true
			end try
			delay 0.5
		end repeat
	end tell
	return false
end waitUntilLoaded
```

### 只读取当前 URL（不启动 Safari）

```applescript
tell application "System Events"
	if (exists process "Safari") then
		tell application "Safari" to set theURL to URL of current tab of window 1
	else
		set theURL to missing value
	end if
end tell
```

---

## 14.2 Google Chrome（脚本支持比 Safari 更好）

```applescript 🔵
tell application "Google Chrome"
	-- 新开标签
	tell window 1 to make new tab with properties {URL:"https://example.com"}

	-- 读取
	set theURL to URL of active tab of window 1
	set theTitle to title of active tab of window 1

	-- 执行 JS（⚠️ 需在 Chrome 菜单 → 视图 → 开发者 → 允许 Apple 事件中的 JavaScript）
	set jsResult to execute active tab of window 1 javascript "document.title"

	-- 遍历所有标签
	repeat with w in windows
		repeat with t in tabs of w
			log (title of t) & " → " & (URL of t)
		end repeat
	end repeat

	-- 等待加载完成
	repeat while (loading of active tab of window 1)
		delay 0.3
	end repeat
end tell
```

⚠️ Chrome 用的是 `active tab`（Safari 是 `current tab`）、`title`（Safari 是 `name`）、
`execute … javascript`（Safari 是 `do JavaScript … in`）。两者 API **不通用**。

⚠️ 别把返回值存进 `result`——它是隐式全局，每条语句后都会被覆盖（§16.2⑳），上面用 `jsResult`。

🔵 本机未安装 Chrome，这一小节按 Chrome 官方 sdef 术语书写，**未做编译校验**；
装了 Chrome 后可用 `sdef "/Applications/Google Chrome.app"` 自行核对。

---

## 14.3 Mail

**关键类**：`account`、`mailbox`、`message`、`outgoing message`、`attachment`、`header`、`rule`、`signature`
**关键命令**：`check for new mail`、`send`、`reply`、`forward`、`redirect`、`move`、`delete`、`synchronize`

```applescript
tell application "Mail"
	-- 读信
	set theMessages to messages of mailbox "INBOX" of account 1
	set unread to (every message of mailbox "INBOX" of account 1 whose read status is false)

	repeat with m in unread
		set theSubject to subject of m
		set theSender to sender of m
		set theContent to content of m
		set theDate to date received of m
	end repeat

	-- 标记已读 / 加旗标
	set read status of m to true
	set flagged status of m to true

	-- 发信
	set newMsg to make new outgoing message with properties ¬
		{subject:"周报", content:"正文内容", visible:true}
	tell newMsg
		make new to recipient at end of to recipients with properties {address:"a@example.com", name:"张三"}
		make new cc recipient at end of cc recipients with properties {address:"b@example.com"}
		-- 加附件
		make new attachment with properties {file name:(POSIX file "/tmp/report.pdf")} at after last paragraph of content
	end tell
	send newMsg
end tell
```

**message 的属性**（sdef 实测）：`subject`、`sender`、`content`、`date received`、`date sent`、
`read status`、`flagged status`、`flag index`、`deleted status`、`junk mail status`、
`message id`、`message size`、`source`（原始邮件全文）、`all headers`、`reply to`、
`was replied to`、`was forwarded`、`mailbox`

**outgoing message 的属性**：`subject`、`content`、`sender`、`visible`、`html content`、
`message signature`、`vcard path`

⚠️ **Mail 是出了名的慢**。`messages of mailbox "INBOX"` 在上万封邮件的邮箱上可能要几十秒甚至超时。
务必：

```applescript
with timeout of 300 seconds
	tell application "Mail" to set theSubjects to subject of (messages 1 thru 50 of mailbox "INBOX" of account 1)
end timeout
```

⚠️ `send` 会把邮件真的发出去，没有撤回。**开发阶段先用 `set visible of newMsg to true` 打开草稿窗口人工检查**，
确认无误再改成 `send`。

⚠️ Mail 还需要「完全磁盘访问权限」才能读取某些数据（尤其 iCloud 账户）。

---

## 14.4 Calendar（日历）

**类**：`calendar`、`event`、`attendee`、`display alarm`、`mail alarm`、`sound alarm`、`open file alarm`
**命令**：`reload calendars`、`save`、`switch view`、`view calendar`、`create calendar`

```applescript
set startDate to my makeDate(2026, 11, 20, 14, 0)
set endDate to startDate + (1 * hours)

tell application "Calendar"
	-- 列出所有日历
	set calNames to name of every calendar

	-- 建事件
	tell calendar "工作"
		set newEvent to make new event with properties ¬
			{summary:"项目评审", start date:startDate, end date:endDate, ¬
			location:"3 号会议室", description:"带上原型图", url:"https://example.com/doc"}

		-- 加提醒（提前 15 分钟弹通知）
		tell newEvent
			make new display alarm at end with properties {trigger interval:-15}
		end tell
	end tell

	-- 查某天的事件
	set todayStart to my startOfDay(current date)
	set todayEnd to todayStart + (1 * days)
	set todaysEvents to (every event of calendar "工作" whose start date ≥ todayStart and start date < todayEnd)

	-- 改 / 删
	set summary of newEvent to "项目评审（改期）"
	delete newEvent

	save            -- ⚠️ 建议显式保存
end tell
```

**event 的属性**（sdef 实测）：`summary`（标题，⚠️ 不是 `name` 也不是 `title`）、
`description`（备注）、`start date`、`end date`、`allday event`、`location`、`url`、
`recurrence`、`stamp date`、`excluded dates`、`status`、`sequence`、`uid`

⚠️⚠️ **事件标题的属性名是 `summary`**，这是最常见的错误：

```applescript
make new event with properties {name:"会议"}       -- ❌ 静默忽略或报错
make new event with properties {summary:"会议"}    -- ✅
```

⚠️ Calendar 的 sdef 里声明了 `access-group`（`com.apple.iCal.read` / `com.apple.iCal.read-write`），
对应系统设置里的「日历」隐私权限。未授权时报 `-1743` 或返回空列表。

⚠️ 全天事件：`{allday event:true}`，此时 `start date` 的时间部分会被忽略，
`end date` 通常设为次日。

---

## 14.5 Reminders（提醒事项）

**类**：`account`、`list`、`reminder`

```applescript
tell application "Reminders"
	set listNames to name of every list

	tell list "工作"
		-- 新建
		set newReminder to make new reminder with properties ¬
			{name:"提交周报", body:"包含本周数据", due date:(current date) + (1 * days), priority:1}

		-- 只要日期不要具体时间
		make new reminder with properties {name:"买牛奶", allday due date:(current date) + (2 * days)}

		-- 查询未完成的
		set pending to (every reminder whose completed is false)

		-- 完成
		set completed of newReminder to true
	end tell
end tell
```

**reminder 的属性**（sdef 实测）：`name`（⚠️ 这里就是 `name`，和 Calendar 不同）、`id`、
`body`、`completed`、`completion date`、`due date`、`allday due date`、`remind me date`、
`priority`（0=无，1=高，5=中，9=低）、`creation date`、`modification date`、`container`

⚠️ Reminders 查询很慢（走 CloudKit）。`every reminder whose completed is false`
在大列表上可能要几十秒，一定要包 `with timeout`。

---

## 14.6 Notes（备忘录）

**类**：`account`、`folder`、`note`、`attachment`

```applescript
tell application "Notes"
	-- 新建（body 是 HTML）
	tell account "iCloud"
		make new note at folder "Notes" with properties ¬
			{name:"会议记录", body:"<h1>会议记录</h1><p>内容……</p>"}
	end tell

	-- 读取
	set theNotes to every note of folder "Notes" of account "iCloud"
	repeat with n in theNotes
		set theTitle to name of n
		set theHTML to body of n            -- HTML
		set thePlain to plaintext of n      -- 纯文本
	end repeat

	-- 按标题找
	set found to (first note whose name is "会议记录")
end tell
```

**note 的属性**（sdef 实测）：`name`、`id`、`body`（HTML）、`plaintext`（纯文本）、
`creation date`、`modification date`、`password protected`、`shared`、`container`、`attachment`

⚠️ `body` 是 **HTML**，写入时要带标签（`<br>`、`<div>`、`<h1>`）。直接写纯文本会全挤成一行。
只要读文本用 `plaintext` 更省事。

⚠️ 加密备忘录（`password protected` 为 true）读 `body` 会失败。

---

## 14.7 Music（音乐）

**关键命令**：`play`、`pause`、`playpause`、`stop`、`next track`、`back track`、
`previous track`、`fast forward`、`rewind`、`search`、`add`、`export`、`convert`、`reveal`

```applescript
tell application "Music"
	-- 播放控制
	playpause
	next track
	set player position to 0          -- 回到开头
	set sound volume to 50            -- 0-100

	-- 当前曲目信息
	set theTrack to current track
	set info to {name of theTrack, artist of theTrack, album of theTrack, duration of theTrack}

	-- 搜索
	set found to search playlist "资料库" for "周杰伦"

	-- 播放指定曲目
	play (first track of playlist "资料库" whose name is "晴天")

	-- 播放状态
	set playerState to player state   --> stopped / playing / paused
end tell
```

⚠️ 状态变量**不能叫 `st`**：`st`/`nd`/`rd`/`th` 是未公开的保留标记，
`set st to player state` 会报 `Expected expression but found "st". (-2741)`（§2.9）。

⚠️ Music 首次访问资料库需要「媒体与 Apple 服务」权限，且资料库大时 `search` 很慢。

⚠️ 老脚本里的 `tell application "iTunes"` 在 macOS 10.15+ 上会被自动重定向到 Music，
但部分属性名有变化，建议直接改写为 Music。

---

## 14.8 Terminal

**类**：`window`、`tab`、`settings set`
**命令**：`do script`（核心）

```applescript
tell application "Terminal"
	-- 在新窗口执行
	do script "cd ~/Projects && git status"

	-- 在当前最前的标签执行
	do script "ls -la" in window 1

	-- 读取输出（tab 的属性）
	set theOutput to contents of tab 1 of window 1     -- 当前屏幕内容
	set theHistory to history of tab 1 of window 1      -- 完整历史
	set isBusy to busy of tab 1 of window 1             -- 命令是否还在跑
	set theTTY to tty of tab 1 of window 1
	set theProcs to processes of tab 1 of window 1

	-- 指定配色方案
	set current settings of tab 1 of window 1 to settings set "Basic"

	-- 等命令跑完
	repeat while busy of tab 1 of window 1
		delay 0.5
	end repeat
end tell
```

**tab 的属性**（sdef 实测）：`contents`、`history`、`busy`、`processes`、`selected`、`tty`、
`current settings`、`number of rows`、`number of columns`、`custom title`、
`cursor color`、`background color`、`normal text color`、`bold text color`

⚠️ `do script` 返回的是 **tab 引用**，不是命令输出。要拿输出得读 `contents`/`history`。

⚠️ **只是想跑 shell 命令、不需要用户看到终端窗口，请直接用 `do shell script`**，
比 Terminal 快得多也不会打扰用户。用 Terminal 的唯一理由是「需要交互式 TTY」或「要让用户看到过程」。

---

## 14.9 TextEdit

TextEdit 没有自定义 suite，用的是 Cocoa 标准字典：

```applescript
tell application "TextEdit"
	-- 新建文档
	set newDoc to make new document with properties {text:"内容"}

	-- 打开文件
	open (POSIX file "/tmp/a.txt")

	-- 读写内容
	set theText to text of document 1
	set text of document 1 to "新内容"

	-- 保存 / 关闭
	save document 1
	close document 1 saving yes      -- 或 saving no / ask
end tell
```

⚠️ 纯文本读写完全不需要 TextEdit，用 §9.3 的 `read`/`write` 更快，也不会弹出 GUI。
TextEdit 的价值在于处理 **RTF/RTFD 富文本**。

---

## 14.10 Photos

**命令**：`import`、`export`、`search`、`spotlight`、`start slideshow`、`stop slideshow`
**类**：`album`、`folder`、`media item`、`moment`、`container`

```applescript
tell application "Photos"
	-- 导入
	import {POSIX file "/tmp/photo1.jpg"} into album "导入" skip check duplicates yes

	-- 导出
	set theItems to search items "关键词"
	export theItems to (POSIX file "/tmp/export") with using originals

	-- 遍历相册
	repeat with a in albums
		log (name of a) & ": " & (count of media items of a)
	end repeat
end tell
```

⚠️ Photos 需要「照片」隐私权限，且首次访问会锁定资料库，脚本期间不要手动操作 Photos。

---

## 14.11 无法脚本化的 App 怎么办

有些常用 App **没有脚本字典**：Messages（大部分功能）、Preview、Slack、微信、钉钉、多数 Electron 应用。

三条替代路线，按优先级：

1. **官方 CLI / API**：例如 Slack 有 Web API，可以用 `do shell script` + `curl`。
2. **URL Scheme**：很多 App 支持自定义 URL。
   ```applescript
   open location "slack://channel?team=T123&id=C456"
   open location "tel:+8613800138000"
   open location "mailto:a@b.com?subject=hi"
   ```
3. **UI Scripting**（最后手段）：见 `docs/10-SystemEvents与界面自动化.md` §10.5。

判断方法：

```bash
sdef /Applications/SomeApp.app 2>&1 | head -5
# 输出为空 / 报错 → 不可脚本化
```

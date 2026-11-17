# 08 读懂脚本字典：Suite、术语与 sdef

初学者最常见的困惑是：打开 Script Editor 的字典（Library），看到一堆
`Suite`、`Commands`、`Classes`，每个条目后面跟着 `v`、`n`、`r/o`、方括号、箭头，
完全不知道该怎么把它翻译成能跑的代码。

这一章就干一件事：**把字典的排版符号逐条拆开，并给出「字典条目 → AppleScript 句子」的固定翻译公式。**

> 前置知识：`docs/07-应用控制模型.md`（术语解析规则）。本章是它的「查手册」篇。

---

## 8.1 字典到底是什么

一个 App 的**脚本字典**（scripting dictionary）是一份 XML 文件，叫 **sdef**
（Scripting Definition）。它声明了「这个 App 能听懂哪些英文词、每个词怎么组句」。

⚠️ **字典不是 API 文档，而是通信协议说明书。**
它描述的是 Apple Event 的形状（见 §7.1），不是函数调用。这就是为什么字典里的
「参数」叫 `direct parameter` / `labeled parameter`，而不是 `argument`。

### 字典的三个来源

一个 App 在 Script Editor 里显示的字典，实际上由三部分拼起来：

| 来源 | 内容 | 位置 |
| --- | --- | --- |
| **Standard Suite** | `open`/`close`/`save`/`quit`/`count`/`make`/`delete`/`exists`/`get`/`set` 以及 `application`/`window`/`document`/`item` 等基础类 | `/System/Library/ScriptingDefinitions/CocoaStandard.sdef`，几乎所有 App 通过 `xi:include` 引入 |
| **App 自己的 Suite** | 该 App 独有的类与命令，例如 Notes 的 `note`/`folder`/`account`、Finder 的 `Finder window`/`eject` | App bundle 内的 `Resources/*.sdef`，或编译进二进制的 `aete` 资源 |
| **Scripting Additions** | 不属于任何 App，全局可用：`display dialog`、`do shell script`、`current date`、`read`/`write`、`choose file` | `/System/Library/ScriptingAdditions/StandardAdditions.osax` |

⚠️⚠️ **第三类不在 App 字典里，但在你的脚本里可以直接用。**
很多人翻遍 Safari 字典也找不到 `display dialog`，因为它来自 StandardAdditions.osax。
查它的字典要单独执行：

```bash
sdef /System/Library/ScriptingAdditions/StandardAdditions.osax
```

本机实测，StandardAdditions 分成 9 个 Suite：

| Suite | 命令数 | 代表命令 |
| --- | --- | --- |
| User Interaction | 14 | `beep`、`choose file`、`choose folder`、`choose from list`、`delay`、`display alert`、`display dialog`、`display notification`、`say` |
| File Commands | 7 | `info for`、`list disks`、`list folder`、`mount volume`、`path to`、`path to resource` |
| String Commands | 5 | `ASCII character`、`ASCII number`、`localized string`、`offset`、`summarize` |
| Clipboard Commands | 3 | `the clipboard`、`set the clipboard to`、`clipboard info` |
| File Read/Write | 6 | `open for access`、`close access`、`read`、`write`、`get eof`、`set eof` |
| Scripting Commands | 4 | `load script`、`store script`、`run script`、`scripting components` |
| Miscellaneous Commands | 9 | `current date`、`do shell script`、`random number`、`round`、`system info`、`time to GMT` |
| Folder Actions | 5 | `opening folder`、`adding folder items to` |
| Internet Suite | 2 | `open location`、`handle CGI request` |

### ⚠️ `sdef` 不会展开 `xi:include`

`sdef` 输出的 XML 里，Standard Suite 常常只是一行引用：

```xml
<xi:include href="file://localhost/System/Library/ScriptingDefinitions/CocoaStandard.sdef"
            xpointer="xpointer(/dictionary/suite)"/>
```

直接 `grep` 就看不到 `open`/`close`/`make` 这些命令。**Script Editor 会展开，`sdef` 不会。**
要在命令行看完整字典，得自己把 include 内联进来（`tools/sdef2txt.py` 已经做了这件事，见 §8.7），
或者单独 dump 那个公共文件：

```bash
sdef /System/Library/ScriptingDefinitions/CocoaStandard.sdef
```

---

## 8.2 打开字典的五种方式

| 方式 | 命令 / 操作 | 适合场景 |
| --- | --- | --- |
| **Script Editor 字典窗口** | ⇧⌘O（文件 → 打开字典） | 日常首选，排版最友好，类名可点击跳转 |
| **命令行 `sdef`** | `sdef /System/Applications/Mail.app` | 脚本化检索、diff 版本差异、CI 里核对 |
| **`osadecompile` / Script Editor 反编译** | 把别人的 `.scpt` 打开看 | 学习现成写法 |
| **让 App 自己报告** | `tell application "Mail" to get version` | 确认版本，字典可能随版本变 |
| **App 官网的 scripting 文档** | 例如 Microsoft Office、BBEdit | 官方通常附带大量示例，比字典好用 |

⚠️ **`sdef` 失败不代表 App 不可脚本化。** 本机实测：

```bash
sdef /System/Applications/Safari.app
# sdef: couldn't get sdef for /System/Applications/Safari.app (error -43)
```

Safari 的字典受系统保护，`sdef` 拿不到，但 Script Editor ⇧⌘O 里能正常打开，
Safari 也完全可脚本化（见 §14.1）。遇到 `-43` 改用 Script Editor。

反过来，`Preview.app`、`TextEdit.app` 在本机 `sdef` 直接失败且 Script Editor 里也没有
有意义的字典——它们才是真的不可脚本化，只能走 UI Scripting（§10.5）。

### 常用 `sdef` 检索命令

```bash
APP="/System/Applications/Mail.app"

# 所有 Suite 名
sdef "$APP" | grep -oE '<suite name="[^"]+"'

# 所有命令名
sdef "$APP" | grep -oE '<command name="[^"]+"'

# 所有类名
sdef "$APP" | grep -oE '<class name="[^"]+"'

# 某个命令的完整定义
sdef "$APP" | grep -A20 '<command name="send"'

# 格式化后翻页看
sdef "$APP" | xmllint --format - | less
```

---

## 8.3 Script Editor 字典窗口的排版符号（核心）

字典窗口分三块（Apple 官方 Mac Automation Scripting Guide 的定义）：

| 区域 | 内容 |
| --- | --- |
| **Toolbar** | 搜索框、「按 Suite 分组 / 按字母排序」切换按钮 |
| **Navigation pane**（左侧） | 术语树：Suite → Command / Class / Property |
| **Detail pane**（右侧） | 选中条目的完整定义 |

左侧导航栏里每个条目前面有一个**类型标记字母**：

| 标记 | 含义 | 对应 sdef 标签 |
| --- | --- | --- |
| `v` | **verb**，命令（动词） | `<command>` |
| `n` | **noun**，类（名词） | `<class>` |
| `r/o` | 只读属性，只能 `get` 不能 `set` | `<property access="r">` |
| `c/o` | 只能写不能读（极少见） | `<property access="w">` |

### 命令条目怎么读

以 Finder 的 `move` 为例，字典里显示成（缩进代表从属关系，长描述已省略）：

```
move v : Move object(s) to a new location
  move reference : the object(s) to move
    to location specifier : the new location for the object(s)
    [replacing boolean] : replace items in the destination that have the same name?
    [positioned at list] : positions for the destination items (local window coordinates)
    [routing suppressed boolean] : whether or not to autoroute items (default false)
  → reference : to the object(s) after they have been moved
```

逐行拆解：

| 字典里的写法 | 含义 | 写代码时变成 |
| --- | --- | --- |
| `move v` | 这是个动词，名字叫 `move` | 句子开头写 `move` |
| `: Move object(s)…` | 冒号后是说明文字，**不是语法** | 忽略 |
| `move reference` | **直接宾语**（direct parameter），紧跟命令名，类型是 reference（对象引用） | `move 那个对象` |
| `to location specifier` | **必选**具名参数，标签是 `to`，类型 location specifier | `to 目标位置` |
| `[positioned at list]` / `[routing suppressed boolean]` | 另外两个可选参数，通常用不到 | 忽略 |
| `[replacing boolean]` | **可选**具名参数（方括号 = optional），标签 `replacing`，类型 boolean | 想要才写 `replacing true` |
| `→ reference` | **返回值**类型 | `set 结果 to move …` |

⚠️ **方括号是「可选」的意思，写代码时不要真的打方括号。**

⚠️ **具名参数的顺序可以随意**，因为它们靠标签识别：

```applescript
tell application "Finder"
	move fileA to folderB replacing true     -- ✅
	move fileA replacing true to folderB     -- ✅ 同样合法
end tell
```

### 类条目怎么读

以 Numbers 的 `table` 类为例，字典实际渲染如下：

```
table n : A table in a sheet

elements
  contains cells, columns, ranges, rows; contained by sheets.

properties
  cell range ( range, r/o ) : The range describing every cell in the table.
  column count ( integer ) : The number of columns in the table.
  filtered ( boolean ) : Whether the table is currently filtered.
  name ( text ) : The table's name.

responds to
  delete, exists, make, sort
```

四个固定小节的含义：

| 小节 | 含义 | 写代码时怎么用 |
| --- | --- | --- |
| **类名 + `n`** | 这是个名词（类），可被引用、可 `make new` | `make new table`、`every table` |
| **elements** | 容器关系。`contains A, B` = 我能取出 A/B；`contained by C` = 我住在 C 里 | `cells of table 1`、`table 1 of sheet 1` |
| **properties** | 属性清单，括号里是 `(类型, 读写标记)` | `name of table 1`、`set filtered of table 1 to true` |
| **responds to** | 这个类能被哪些命令作用 | `delete table 1`、`exists table 1` |

⚠️ **`responds to` 不是全集。** `get` / `set` 是 AppleScript 语言自带的隐含命令，
几乎所有类都支持，但通常**不会**列在 `responds to` 里。别因为它没列就以为不能读属性。

⚠️ **`elements` 里的 `contained by` 是反向线索**，帮你拼出完整的 `of` 链：

```
table 的 elements 写着 "contained by sheets"
sheet 的 elements 写着 "contained by documents"
        ↓
cell 1 of table 1 of sheet 1 of document 1
```

### 常见类型名对照

字典里的类型名和 AppleScript 的字面量写法不完全一样：

| 字典里的类型 | 实际含义 | 传值示例 |
| --- | --- | --- |
| `text` | 字符串 | `"hello"` |
| `integer` | 整数 | `42` |
| `real` / `number` | 浮点 / 任意数值 | `3.14` |
| `boolean` | 布尔 | `true` / `false` |
| `date` | 日期对象 | `current date` |
| `file` / `alias` | 文件（可以是 POSIX file / HFS 路径） | `POSIX file "/tmp/a.txt"` |
| `list` | 列表 | `{"a", "b"}` |
| `record` | 记录 | `{name:"x", value:1}` |
| `reference` / `specifier` | **对象引用**，不是值 | `document 1`、`file "x" of folder "y"` |
| `constant` | 字典里定义的枚举常量 | `ask`、`yes`、`no` |
| `type` / `type class` | 「类型本身」，用于 `count each`、`make new` | `folder`、`text` |
| `any` | 什么都行 | — |
| `list of X` | X 类型的列表 | `{doc1, doc2}` |

⚠️ `reference` / `specifier` 是最容易误读的类型。它表示「**这里要放一个对象引用**」，
而不是字符串。写 `close "文档1"` 通常失败，要写 `close document "文档1"`。

### 枚举（Enumerations）

字典里还有第四类条目 `Enumerations`，列出可用的常量：

```
save options :
  • yes
  • no
  • ask
```

这些是**裸词**，不加引号：

```applescript
tell application "TextEdit"
	close document 1 saving yes      -- ✅ 裸词
	close document 1 saving "yes"    -- ❌ 类型错误 -1700
end tell
```

---


## 8.4 sdef XML 与英文句子的一一对应

命令行看到的 sdef 是 XML。它和字典窗口是**同一份数据的两种渲染**。
认清对应关系后，`sdef` 比 GUI 更适合检索、diff 和脚本化处理。

### 命令：`<command>`

本机 StandardAdditions 里 `do shell script` 的真实定义（已去掉 `<documentation>`）：

```xml
<command name="do shell script" code="sysoexec"
         description="Execute a shell script using the ‘sh’ shell">
	<direct-parameter type="text" description="the shell script to execute."/>
	<parameter name="as" code="rtyp" type="type class" optional="yes"
	           description="the desired type of result; default is text (UTF-8)"/>
	<parameter name="administrator privileges" code="badm" type="boolean" optional="yes"
	           description="execute the command as the administrator"/>
		
### 类：`<class>`

`/System/Library/ScriptingDefinitions/CocoaStandard.sdef` 里的 `window`：

```xml
<class name="window" code="cwin" description="A window.">
	<cocoa class="NSWindow"/>
	<property name="name" code="pnam" type="text" access="r"
	          description="The title of the window.">
		<cocoa key="title"/>
	</property>
	<property name="index" code="pidx" type="integer"
	          description="The index of the window, ordered front to back.">
		<cocoa key="orderedIndex"/>
	</property>
		<property name="closeable" code="hclb" type="boolean" access="r"
	          description="Does the window have a close button?">
		<cocoa key="hasCloseBox"/>
	</property>
	<element type="document">
		<cocoa key="documents"/>
	</element>
</class>
```

| XML | 字典窗口里显示 | 写代码时 |
| --- | --- | --- |
| `<class name="window">` | `window n` | `window 1`、`every window` |
| `code="cwin"` | 不显示 | 四字符事件码，见 §8.8 |
| `inherits="container"` | 该类自动拥有父类全部属性 | 父类属性能直接用在子类上 |
| `plural="folders"` | — | `every folder` 用的就是这个复数名 |
| `<property name="name" access="r">` | `name ( text, r/o )` | `name of window 1`，**不能** `set` |
| `<property>` 无 `access` | `index ( integer )` | 可读可写 |
| `<element type="document">` | `contains documents` | `documents of window 1` |
| `<cocoa class>` / `<cocoa key>` | 不显示 | **写脚本时完全忽略**，是给 ObjC 桥接用的 |

⚠️ `access` 属性缺省即 `rw`。看到 `access="r"` 就去掉「我要 `set` 它」的念头，
硬写会得到 `-10006`（`errAEEventNotPermitted`）或 `-1743`。

### 给已有类加属性：`<class-extension>`

Notes 没有自己定义 `application` 类，而是**扩展**了 Standard Suite 的 `application`：

```xml
<class-extension extends="application" description="the Notes application">
	<cocoa class="NSApplication"/>
	<property name="default account" code="dfac" type="account"
	          description="the default account for creating notes">
		<cocoa key="scriptingDefaultAccount"/>
	</property>
	<property name="selection" code="seln" description="the selected note(s)">
		<type type="note" list="yes"/>
		<cocoa key="scriptingSelection"/>
	</property>
	<element type="note">
		<cocoa key="scriptingNotes" insert-at-beginning="yes"/>
	</element>
</class-extension>
```

三个要点：

- `extends="application"` 才是「我扩展谁」，**不是** `<class name>`。
  ⚠️ 用 `grep '<class name='` 统计类会漏掉所有 extension。
- `<property>` 里没有 `type=` 属性时，类型写在子元素 `<type type="note"/>` 里。
- `list="yes"` 表示「note 的列表」，所以 `selection of application "Notes"` 返回的是 list，
  单个选中也要写 `item 1 of (selection …)`。

### `<responds-to>`、`<enumeration>`、`<access-group>`

Notes 的 `note` 类声明它能响应 `show` 命令：

```xml
<class name="note" code="note" description="a note in the Notes application">
	<cocoa class="ICScriptingNote"/>
	<responds-to command="show">
		<cocoa method="handleShowScriptCommand:"/>
	</responds-to>
	<element type="attachment">…</element>
</class>
```

Calendar 的枚举定义：

```xml
<enumeration name="participation status" code="wre6">
	<enumerator name="unknown"   code="E6na" description="No anwser yet"/>
	<enumerator name="accepted"  code="E6ap" description="Invitation has been accepted"/>
	<enumerator name="declined"  code="E6dp" description="Invitation has been declined"/>
	<enumerator name="tentative" code="E6tp" description="Invitation has been tentatively accepted"/>
</enumeration>
```

用法是裸词：`set participation status of theAttendee to accepted`。

`<access-group>` 表示「这条术语需要 entitlement 才能用」。CocoaStandard 的 `close` 里写
`<access-group identifier="*"/>`（人人可用）；System Events 的 `window` 元素写
`<access-group identifier="com.apple.systemevents.window.position" access="r"/>`，
意味着读窗口位置需要系统给这个 App 签了对应权限——这也是 §10 里 UI Scripting
常常「字典里有、跑起来报错」的根源之一。

### 可以直接忽略的标签

| 标签 | 作用 |
| --- | --- |
| `<cocoa class="…">` | 对应的 Objective-C 类名 |
| `<cocoa key="…">` | 对应的 KVC 属性名 |
| `<cocoa method="…">` | 对应的处理函数 |
| `<synonym name="…">` | 该术语的别名（老写法兼容） |
| `<documentation>` | 给人看的 HTML 说明 |
| `code="…"` | 四字符事件码，只有写原始事件时才需要（§8.8） |

写 AppleScript 只需要关心：`name`、`type`、`optional`、`access`、`inherits`、`plural`。

---

## 8.5 从字典反推句子的四条公式

看懂条目只是第一步，关键是**机械地把它拼成句子**。四个公式覆盖 95% 的场景。

### 公式一：命令句

```
命令名  直接宾语  标签1 值1  标签2 值2 …
```

本机 Mail 的真实定义：

```xml
<command name="send" code="emsgsend" description="Sends a message.">
	<direct-parameter type="outgoing message" description="the message to send"/>
	<result type="boolean" description="true if sending was successful, false if not"/>
</command>
```

→ 直接宾语类型是 `outgoing message`，所以句子是：

```applescript
tell application "Mail"
	set theMessage to make new outgoing message with properties {subject:"Hi", content:"body"}
	send theMessage          -- 直接宾语紧跟命令名，无标签
end tell
```

⚠️ 直接宾语类型写的是 `outgoing message`，不是 `message`。
传错类会报 `-1704`（`errAEWrongDataType`）。

### 公式二：属性句

```
属性名 of 对象引用          -- 读
set 属性名 of 对象引用 to 值  -- 写（仅当 access 不含 r）
```

字典里 Notes `note` 类的属性清单：

```
name            ( text, r/o? 无 )   ← 可读写
id              ( text, r/o )       ← 只读
plaintext       ( text, r/o )       ← 只读
body            ( text )            ← 可读写
```

句子：

```applescript
tell application "Notes"
	get name of note 1                 -- ✅
	set body of note 1 to "<b>hi</b>"  -- ✅ body 可写
	set plaintext of note 1 to "hi"    -- ❌ r/o，报 -10006 / -1743
end tell
```

⚠️ `of` 链要从**最里层往最外层**倒着写：`cell 1 of table 1 of sheet 1 of document 1`。

### 公式三：元素句

```
every 类名复数 of 对象引用
类名 索引 of 对象引用
类名 whose 条件 of 对象引用
```

`<element type="note">` 出现在 `folder` 类里 → `notes of folder 1` 合法。
反过来 `folder` 类的 `contained by` 告诉你它能被谁包含。

```applescript
tell application "Notes"
	count of notes of folder "工作" of account "iCloud"
	get name of every note whose name contains "会议"
	get body of note 2 of folder 1
end tell
```

### 公式四：创建句

Standard Suite 的 `make` 是万能的：

```
make new 类名 at 位置 with properties 记录
make new 类名 at the beginning of 位置 with data 值
```

本机 CocoaStandard.sdef 里 `make` 有 4 个具名参数 + 1 个返回值，`new` 是唯一必选的：

| XML 里的参数 | 是否可选 | 类型 | 句子里写成 |
| --- | --- | --- | --- |
| `name="new"` | 必选 | `type` | `make new note` |
| `name="at"` | optional="yes" | `location specifier` | `at end of folder 1` |
| `name="with data"` | optional="yes" | `any` | `with data "内容"` |
| `name="with properties"` | optional="yes" | `record` | `with properties {name:"x"}` |
| `<result>` | — | `specifier` | `set n to make new …` |

⚠️ `new` 后面跟的是**类名裸词**（`note`、`folder`、`document`），不是字符串。
字典里它的类型是 `type`，意思就是「一个类型本身」。

```applescript
set startDate to (current date)
set year of startDate to 2026
set month of startDate to 11
set day of startDate to 20
set time of startDate to 10 * hours

tell application "Calendar"
	tell calendar "工作"
		set newEvent to make new event at end with properties ¬
			{summary:"周会", start date:startDate, allday event:false}
	end tell
end tell
```

两个只能靠字典确认、猜不出来的点：

- Calendar 的事件标题属性叫 **`summary`**，不是 `name` 也不是 `title`；
  备注属性叫 `description`（`code="wr12"`），全天标记叫 `allday event`。
- ⚠️ **不要用 `date "2026年11月20日 10:00:00"` 这种硬编码字面量。**
  本机（区域 `en_CN`）实测编译期直接失败：
  `Invalid date and time date 2026年11月20日 10:00:00. (-30720)`。
  日期字面量的格式由**系统区域设置**决定，换台机器就崩。
  `date "2026-11-20 10:00:00"` 在本机能过，但同样不保证跨机器。
  可移植写法是上面那种「`current date` + 逐项赋值」。详见 `docs/04-日期时间与数字.md`。

---

## 8.6 实战：用三种字典练手

本机实测的三个字典，正好代表三种典型形态。

### 形态一：小而全 —— Notes

```
SUITE Standard Suite   Commands (11)  Classes (3)
SUITE Notes Suite      Commands (2)   Classes (5)
```

只有两个 Suite。`Standard Suite` 是 `xi:include` 进来的公共部分，
`Notes Suite` 才是它自己的：类是 `account` / `folder` / `note` / `attachment` / `application`。

**读法**：先看 `Notes Suite` 的 Classes，弄清容器链
`account → folder → note → attachment`，再回到 Standard Suite 找 `make` / `delete` / `count`。
Notes 自己只额外提供了 2 个命令，其余全靠标准命令组合：

```
v open note location  — Open a note URL.
    <text>  [direct object]  — The URL to be opened.
v show  — Show an object in the UI
    <account | folder | note | attachment>  [direct object]  — The object to be shown
    [separately bool]
    → account | folder | note | attachment
```

`show` 的直接宾语写成 `account | folder | note | attachment`，
竖线 `|` 表示**多态**：四种类型任选一种都行。在 sdef XML 里它对应多个并列的 `<type>` 标签。
同理 `folder` 类的 `container (account | folder, r/o)` 表示「读出来的可能是 account 也可能是 folder」，
写代码时要用 `class of` 判断：

```applescript
tell application "Notes"
	show note 1                       -- 把笔记滚到可见位置
	if (class of (container of folder 1)) is account then
		get name of (container of folder 1)
	end if
end tell
```

⚠️ 这类「自己命令极少」的 App，字典里 Classes 的价值远大于 Commands。
别因为「没几个命令」就以为它不能自动化。

### 形态二：按功能切分 —— Finder

```
SUITE Standard Suite            Commands (13)
SUITE Finder Basics             Commands (3)   Classes (1)
SUITE Finder items              Commands (6)   Classes (1)
SUITE Containers and folders                   Classes (6)
SUITE Files                                    Classes (7)
SUITE Window classes                           Classes (6)
SUITE Legacy suite              Commands (3)   Classes (4)
SUITE Type Definitions                         Classes (8)
SUITE Enumerations
```

**读法**：Finder 的 Suite 是**按对象种类切的，不是按功能切的**。
想操作文件就去 `Files`，想操作窗口就去 `Window classes`。
`Type Definitions` 和 `Enumerations` 两个 Suite 里没有可执行命令，
只是给别处的属性提供类型和常量，翻字典时可以先跳过。
`Legacy suite` 是历史兼容，新脚本别用。

### 形态三：巨型多面手 —— System Events

本机实测 17 个 Suite、90 个类：

```
SUITE System Events Suite         Commands (3)   Classes (1)
SUITE Disk-Folder-File Suite      Commands (3)   Classes (13)
SUITE Processes Suite             Commands (5)   Classes (47)
SUITE Property List Suite                        Classes (5)
SUITE Login Items Suite                          Classes (2)
SUITE Hidden Suite                Commands (12)  Classes (1)
…（还有 Accounts / Appearance / Desktop / Dock / Network / Power / XML 等）
```

**读法**：System Events 是**一堆互不相干的功能塞进一个进程**。
翻字典时必须先认准 Suite 名，否则会以为「文件操作」和「点击按钮」有什么关联——没有。

`Processes Suite` 只有 5 个命令，但 47 个类，是 UI Scripting 的全部词汇：

| 命令 | 直接宾语类型 | 作用 |
| --- | --- | --- |
| `click` | `UI element` | 模拟点击；加 `[at {x, y}]` 可按全局坐标点 |
| `key code` | `integer` 或其列表 | 发送物理键码，`[using …]` 带修饰键 |
| `keystroke` | `text` | 发送字符，`[using …]` 带修饰键 |
| `perform` | `action` | 执行控件自带的动作（`AXPress` 等） |
| `select` | `UI element` | 设为选中状态 |

⚠️ `pick`、`confirm`、`cancel`、`increment`、`key down` 这些**在 `Hidden Suite` 里**。
Script Editor 默认不显示 Hidden Suite，但它们确实能用（§10 会用到 `pick`）。
想知道完整能力必须直接读 sdef：

```bash
python3 tools/sdef2txt.py "/System/Library/CoreServices/System Events.app" --suite "Hidden Suite"
```

`UI element` 是所有 UI 类的根类，47 个类里绝大多数都 `inherits="UI element"`。
这意味着**读一遍 `UI element` 的属性表，就等于读完了所有控件的公共属性**——
这是 System Events 字典最高效的读法，详见 §10.5。

---

## 8.7 本仓库工具：`tools/sdef2txt.py`

`sdef` 的原始 XML 噪音太多（一半是 `<cocoa …>` 桥接标签），
`tools/sdef2txt.py` 把它转成贴近 Script Editor 排版、但**可以在终端里 grep** 的文本，
并且会自动内联 `xi:include`（把 Standard Suite 补回来）。

```bash
# 整个字典
python3 tools/sdef2txt.py /System/Applications/Notes.app

# 只看某个 Suite（可重复）
python3 tools/sdef2txt.py "/System/Library/CoreServices/System Events.app" --suite "Processes Suite"

# 按名字过滤
python3 tools/sdef2txt.py /System/Library/CoreServices/Finder.app --grep window

# 只要命令 / 只要类
python3 tools/sdef2txt.py /System/Applications/Mail.app --commands-only
python3 tools/sdef2txt.py /System/Applications/Mail.app --classes-only

# 从已保存的 sdef 文件读（配合 - ）
sdef /System/Applications/Mail.app > /tmp/mail.sdef
python3 tools/sdef2txt.py - < /tmp/mail.sdef
```

输出长这样（本机 Finder `move` 的真实输出，过长的描述用 `…` 截断）：

```
SUITE Standard Suite  [code=CoRe]
  Commands (1)
  v move  — Move object(s) to a new location
      <reference>  [direct object]  — the object(s) to move
      to location specifier  — the new location for the object(s)
      [replacing bool]  — Specifies whether or not to replace items in the destination …
      [positioned at list]  — Gives a list (in local window coordinates) of positions …
      [routing suppressed bool]  — Specifies whether or not to autoroute items …
      → reference  — to the object(s) after they have been moved
```

对照 §8.3 的符号表：`v` = 命令，`<…>` = 直接宾语，`[…]` = 可选具名参数，
无括号 = 必选具名参数，`→` = 返回值，`r/o` = 只读属性。

⚠️ 路径带空格要加引号：`"/System/Library/CoreServices/System Events.app"`。
⚠️ Safari 用 `sdef` 会 `-43`（§8.2），这个工具也拿不到，改用 Script Editor。

---

## 8.8 常见误读陷阱

### 陷阱一：字典里有 ≠ 能用

最常踩的一个。字典描述的是**协议**，不是**授权**。跑起来可能是：

| 错误码 | 名字 | 典型原因 |
| --- | --- | --- |
| `-1708` | `errAEEventNotHandled` | 该 App 声明了术语但没实现处理函数 |
| `-10000` | `errAEEventFailed` | 处理函数跑了但内部失败 |
| `-10006` | `errAECantAssign` | 想 `set` 一个 `access="r"` 的属性 |
| `-1743` | — | 没有「自动化」权限（TCC 拦截） |
| `-25211` | — | 没有「辅助功能」权限（UI Scripting） |
| `-1719` | `errAEIllegalAccess` | 同上，另一种表现 |

⚠️⚠️ `-1708` 特别阴：字典里明明列着这个命令，App 却没实现。
遇到就换成 `get`/`set` 属性或 UI Scripting，别死磕。

### 陷阱二：Hidden Suite 与 `hidden="yes"`

Script Editor 的字典窗口**不显示** Hidden Suite，也不显示标了 `hidden="yes"` 的术语。
本机 System Events 有 59 处 `hidden="yes"`。
所以「Script Editor 里搜不到」不等于「不存在」。完整能力只能从 sdef 原文看：

```bash
sdef "/System/Library/CoreServices/System Events.app" | grep -c 'hidden="yes"'
# 59
```

### 陷阱三：术语冲突（同名不同义）

`name`、`window`、`document`、`close`、`count` 这些词在**每个 App 的字典里都有一份定义**，
彼此并不相同。`tell` 块用的是**目标 App 的那份**（§7.2）。
System Events 的 sdef 里根本没有 `<class name="window">`——它的 `window` 是从
Standard Suite 继承来的；而 Finder 的 `window` 和 TextEdit 的 `window` 又是两套属性。

⚠️ 结论：**永远不要在 `tell` 块外面凭记忆写 App 术语**，也不要把 A App 的属性名搬到 B App。

### 陷阱四：四字符 code 与原始事件

XML 里的 `code="coreclos"`、`code="sysoexec"` 是 Apple Event 的四字符码。
平时写不到它，只有两种情况会撞上：

1. 术语没被正确解析时，Script Editor 会把它显示成 `«event coreclos»` 这种尖括号形式。
2. 你要给一个**没有字典**的 App 发原始事件时，才手写 `«event …»`。

```applescript
-- 等价于 tell application "Finder" to close window 1
tell application "Finder" to «event coreclos» window 1
```

看到自己脚本里冒出 `«»`，说明**术语没解析成功**——通常是 `tell` 目标写错了、
App 名字打错了，或者在 `use framework` 之后术语被顶掉了（§16）。

### 陷阱五：以为字典是稳定的

字典随 App 版本变化。macOS 大版本升级后，Apple 自家 App 的术语经常增删
（Calendar、Notes、Music 都发生过）。所以：

- 生产脚本里对关键属性做 `try` + `exists` 兜底；
- 用 `tell application "X" to get version` 记录版本，方便事后排查；
- 别把字典输出硬编码进注释就完事，升级后要重新核对。

---

## 8.9 一句话流程

拿到一个陌生 App，按这个顺序问自己：

1. **它有字典吗？** → Script Editor ⇧⌘O 看得到吗？`sdef <路径>` 有输出吗？
2. **有 → 走术语路线**：找 Classes 里的容器链，用 `of` 拼路径，用 Standard Suite 的
   `make`/`delete`/`count`/`get`/`set` 干活。这是最稳的路（§7、§9、§14）。
3. **没有，或有但缺你要的功能 → 走 UI Scripting**：System Events + Accessibility
   Inspector 定位控件（§10、§11）。这是最后手段。
4. **都不行 → 走 Shell**：`do shell script` 调 CLI、`defaults`、`sqlite3`、App 自带的
   命令行工具（§12）。

# 10 System Events 与界面自动化

System Events 是 macOS 自动化的「万能钥匙」：它既能替代 Finder 做文件操作，
又能枚举进程、发送按键、模拟点击——即使目标 App 完全没有脚本字典。

## 10.1 两类完全不同的能力

| 类别 | 例子 | 需要的权限 |
| --- | --- | --- |
| **系统级查询/操作** | 进程列表、登录项、plist 读写、文件存在性 | 通常不需要额外授权 |
| **UI Scripting（模拟人操作）** | `keystroke`、`click button`、读取窗口控件 | **辅助功能（Accessibility）** |

⚠️ 检查当前是否有辅助功能权限：

```applescript
tell application "System Events"
	UI elements enabled     --> false 表示没授权
end tell
```

授权路径：**系统设置 → 隐私与安全性 → 辅助功能**，把运行脚本的宿主程序加进去。

⚠️⚠️ **要授权的是「宿主程序」，不是脚本本身**：

| 你怎么跑脚本 | 要授权谁 |
| --- | --- |
| 终端里 `osascript xxx.applescript` | **终端 App**（Terminal / iTerm / Warp） |
| Script Editor 里按 ⌘R | **Script Editor** |
| 编译成 `.app` 双击运行 | **那个 .app** |
| `launchd` 定时任务 | 通常需要给 `osascript` 或包装 App 授权，且**无头环境下 UI Scripting 会失败** |
| 从 Automator / 快捷指令 | 对应的宿主 |

没授权时的典型报错：`-25211`（assistive access is not allowed）或
`osascript is not allowed to send keystrokes`。

## 10.2 进程管理（不需要辅助功能权限）

```applescript
tell application "System Events"
	-- 所有有界面的 App
	set visibleApps to name of (every process whose background only is false)

	-- 当前最前台的 App（实测返回如 "ChatGPT"）
	set frontApp to first process whose frontmost is true
	set frontName to name of frontApp
	set frontBundle to bundle identifier of frontApp
	set frontPID to unix id of frontApp

	-- 某个 App 是否在运行
	set isRunning to (exists process "Safari")

	-- 让它到前台
	set frontmost of process "Safari" to true
end tell
```

⚠️ `exists process "Safari"` 用的是**进程名**（通常等于 App 显示名），不是 bundle id。
要按 bundle id 找：

```applescript
tell application "System Events"
	set p to first process whose bundle identifier is "com.apple.Safari"
end tell
```

### 启动 / 退出 App

```applescript
-- 启动（三种方式）
tell application "Safari" to activate              -- 会等 App 就绪，并拉到前台
tell application "System Events" to launch "Safari" -- 只启动，不抢焦点
do shell script "open -a Safari"                    -- shell 方式

-- 退出
tell application "Safari" to quit
tell application "System Events" to set visible of process "Safari" to false   -- 只是隐藏

-- 强杀（不推荐，可能丢数据）
do shell script "pkill -x Safari"
```

⚠️ `activate` 会把 App 拉到前台并**抢走焦点**。在自动化流程里这常常是必要的
（UI Scripting 要求目标在前台），但也会打断用户。

### 等待 App 就绪

```applescript
on waitForProcess(processName, maxSeconds)
	set deadline to (current date) + maxSeconds
	repeat while (current date) < deadline
		tell application "System Events"
			if (exists process processName) then return true
		end tell
		delay 0.5
	end repeat
	return false
end waitForProcess
```

⚠️ `with timeout` 对这种本地循环无效（见 §6.3），必须自己做截止时间判断。

## 10.3 登录项

```applescript
tell application "System Events"
	-- 列出
	set itemNames to name of every login item

	-- 添加
	make login item at end with properties {path:"/Applications/Safari.app", hidden:false}

	-- 删除
	delete login item "Safari"
end tell
```

⚠️ 现代 macOS 上很多 App 用 `SMAppService` 注册后台项，**不会出现在 `login items` 里**。
这个 API 只能管理经典登录项。

## 10.4 plist 文件读写（很实用）

System Events 原生支持读写 `.plist`，比 `defaults` 命令更好用（实测可用）：

```applescript
set plistPath to "/Users/taylor/Library/Preferences/com.example.myapp.plist"

tell application "System Events"
	tell property list file plistPath
		-- 读
		set theValue to value of property list item "name"

		-- 改
		set value of property list item "name" to "新值"

		-- 增
		make new property list item at end with properties {name:"count", value:42}
		make new property list item at end with properties {name:"tags", value:{"a", "b"}}

		-- 列所有键
		set allKeys to name of every property list item
	end tell
end tell
```

⚠️ **文件必须已存在**，System Events 不会替你创建空 plist。先建一个：

```applescript
do shell script "touch " & quoted form of plistPath
do shell script "plutil -create xml " & quoted form of plistPath   -- 或写入一个最小 plist
```

⚠️ 修改系统或其他 App 的偏好设置 plist 后，**目标 App 可能已经把旧值缓存在内存里**。
需要先退出该 App，或 `killall cfprefsd` 刷新偏好缓存：

```applescript
do shell script "killall cfprefsd"
```

### 命令行等价写法

```applescript
do shell script "defaults read com.example.myapp name"
do shell script "defaults write com.example.myapp count -int 42"
do shell script "/usr/libexec/PlistBuddy -c 'Print :name' " & quoted form of plistPath
```

## 10.5 UI Scripting：从分层模型开始

**为什么这一节这么长**：绝大多数 macOS App 没有脚本字典（Preview、TextEdit、
系统设置、几乎所有第三方 App）。这时唯一的自动化手段就是「像人一样点界面」。
而「点界面」不是猜控件名，而是操作一棵有严格层次的树——不理解这棵树的构造，
脚本就会写成「碰运气」。

> **验证标记说明**
> - ✅ **实测通过**：本机（macOS 26.6.2）实际运行验证。
> - 🔵 **语法校验通过**：`osacompile` 编译通过，但本机运行脚本的宿主进程
>   **没有辅助功能权限**（`UI elements enabled` 返回 `false`），
>   因此 UI Scripting 代码未做运行时验证。涉及权限时报 `-25211` / `-1719`。
> - 本章所有表格里的 role / subrole / attribute / action 常量，
>   均来自本机 SDK 头文件实测（`AXRoleConstants.h`、`AXAttributeConstants.h`、
>   `AXActionConstants.h`、`AXNotificationConstants.h`）。

### 10.5.1 官方文档里的分层概念

Apple 的 Accessibility 与 AppleScript 文档把界面自动化拆成四层。
**分清自己在哪一层写代码，是排查 UI 脚本问题的第一步。**

| 层 | 名称 | 你写的东西 | 术语来自哪里 | 什么时候用 |
| --- | --- | --- | --- | --- |
| **L0** | Apple Event 层 | `«event coreclos»` 这类原始事件 | AppleScript 语言本身 | 目标 App 无字典且术语解析失败（§8.8） |
| **L1** | Accessibility 对象模型（AX API） | `AXRole`、`AXTitle`、`AXPress`、`AXModal` | `HIServices.framework` 的 C 常量 | **读文档 / 看 Inspector 时**；AppleScript 里通过 `attribute` 访问 |
| **L2** | System Events 术语层 | `click button 1 of window 1` | System Events 的 `Processes Suite`（47 个类） | **日常写脚本的主战场** |
| **L3** | 几何层 | `click process "X" at {512, 300}` | 同 L2，但按屏幕坐标 | L2 定位不到时的兜底 |

关键认知：

⚠️⚠️ **L2 是 L1 的一层薄封装，但名字不一样。**
System Events 的每个 UI 类对应一个 `AXRole`，每个属性对应一个 `AXAttribute`，
`perform action` 对应 `AXAction`。所以：

- Accessibility Inspector（§11）显示给你的是 **L1 的名字**：`AXButton`、`AXTitle`、`AXPress`
- 你写 AppleScript 用的是 **L2 的名字**：`button`、`title`、`click`
- 两者之间需要一张对照表 → §10.5.4、§10.5.6

这张对照关系没搞清，是「Inspector 里明明看到了，代码里却写不出来」的头号原因。

⚠️ **L1 里有的东西，L2 不一定暴露。** System Events 只把最常用的 **19 个** AX 属性
做成了 `UI element` 的属性；而本机 SDK 的 `AXAttributeConstants.h` 里定义了 **152 个**，
全部 HIServices 头文件加起来 **268 个**。差集必须用 `attribute "AXxxx"` 读（§10.5.6）。
反过来，有些 AXRole 在 System Events 里**根本没有对应类**（§10.5.4 标 ❌ 的那些），
只能用 `UI element whose role is "AXCell"` 这种通用写法。

#### 这棵树的实际形状

从系统根节点往下，每层都是一个 Element：

```
AXSystemWide                      ← 整个系统（System Events 里没有对应类）
 └─ AXApplication                 ← 一个进程 = System Events 的 process
     ├─ AXMenuBar                 ← menu bar 1
     │   └─ AXMenuBarItem         ← menu bar item "文件"
     │        └─ AXMenu           ← menu 1 of menu bar item "文件"
     │             ├─ AXMenuItem  ← menu item "新建"
     │             └─ AXMenuItem  ← menu item "打开子菜单"
     │                  └─ AXMenu → AXMenuItem …   ← 子菜单可无限嵌套
     ├─ AXWindow                  ← window 1
     │   ├─ AXToolbar             ← toolbar 1
     │   ├─ AXSheet               ← sheet 1（模态子面板，挂在窗口下）
     │   ├─ AXGroup / AXTabGroup / AXScrollArea / AXSplitGroup
     │   │    └─ AXButton / AXTextField / AXCheckBox / AXPopUpButton / AXStaticText …
     │   └─ AXTable → AXRow → AXCell / AXColumn
     └─ AXWindow (subrole=AXDialog)   ← App 级模态对话框，是独立 window！
AXApplication "Dock"
 └─ AXList → AXDockItem …
AXApplication "NotificationCenter"
 └─ AXWindow → …                    ← 通知横幅在这里，不在目标 App 里
```

⚠️⚠️ **最后两行是全章最重要的提醒**：
系统级弹窗（权限请求、密码框、通知横幅）**不属于你正在操作的那个进程**。
在 `tell process "Safari"` 里找系统授权弹窗，永远找不到。详见 §10.5.10。

### 10.5.2 AX 四元组：Element / Attribute / Action / Notification

L1 的对象模型只有四个概念。AppleScript 能用到前三个：

| 概念 | 是什么 | AppleScript 里怎么写 | 可用性 |
| --- | --- | --- | --- |
| **Element** | 树上的节点 | `button 1 of window 1`、`UI element whose role is "AXButton"` | ✅ 完整 |
| **Attribute** | 节点的键值属性 | `title of …`、`value of …`、`attribute "AXModal" of …` | ✅ 完整 |
| **Action** | 节点可被执行的动作 | `perform action "AXPress" of button 1 of window 1` | ✅ 完整 |
| **Notification** | 节点主动发出的事件 | — | ❌ **AppleScript 收不到** |

⚠️⚠️ **Notification 是 AppleScript 的能力边界。**
AX API 定义了 37 种通知（本机 SDK 实测），比如：

```
kAXWindowCreatedNotification            kAXSheetCreatedNotification
kAXUIElementDestroyedNotification       kAXFocusedUIElementChangedNotification
kAXFocusedWindowChangedNotification     kAXMainWindowChangedNotification
kAXValueChangedNotification             kAXTitleChangedNotification
kAXMenuOpenedNotification               kAXMenuItemSelectedNotification
kAXApplicationActivatedNotification     kAXLayoutChangedNotification
kAXRowExpandedNotification              kAXSelectedChildrenChangedNotification
kAXAnnouncementRequestedNotification    …
```

用 C / Swift / Python(pyobjc) 可以注册回调，事件一来就唤醒。
**AppleScript 没有事件循环，只能轮询**（`repeat` + `delay`，见 §10.5.12）。
这决定了所有「等某个控件出现」的逻辑都必须写成轮询，也决定了 UI 脚本天生有延迟。

#### Action 全集与对应命令

本机 SDK 实测共 **11 个** AXAction：

| AXAction 常量 | 字符串值 | System Events 里的命令 | 所在 Suite |
| --- | --- | --- | --- |
| `kAXPressAction` | `AXPress` | `click` | Processes |
| `kAXPickAction` | `AXPick` | `pick` | ⚠️ Hidden |
| `kAXConfirmAction` | `AXConfirm` | `confirm` | ⚠️ Hidden |
| `kAXCancelAction` | `AXCancel` | `cancel` | ⚠️ Hidden |
| `kAXIncrementAction` | `AXIncrement` | `increment` | ⚠️ Hidden |
| `kAXDecrementAction` | `AXDecrement` | `decrement` | ⚠️ Hidden |
| `kAXRaiseAction` | `AXRaise` | —（用 `perform action`） | — |
| `kAXAcceptAction` | `AXAccept` | —（用 `perform action`） | — |
| `kAXShowMenuAction` | `AXShowMenu` | —（用 `perform action`） | — |
| `kAXShowAlternateUIAction` | `AXShowAlternateUI` | — | — |
| `kAXShowDefaultUIAction` | `AXShowDefaultUI` | — | — |

⚠️ `UI element` 的 `responds to` 只列了 7 个：
`click, select, increment, decrement, confirm, pick, cancel`。
其中 5 个在 Hidden Suite，Script Editor 字典里看不到（§8.6、§8.8）。

**列出某个元素实际支持哪些 action**（比查文档准）：

```applescript
tell application "System Events" to tell process "Safari"
	get name of every action of button 1 of window 1
	-- 例如 {"AXPress", "AXShowMenu"}
	get description of action "AXPress" of button 1 of window 1
end tell
```
🔵

### 10.5.3 System Events 术语层：一个根类撑起整棵树

本机实测 System Events 共 **17 个 Suite、90 个类**，其中 `Processes Suite` 占 **47 个类**。
除了 `action`、`attribute`、`process`、`application process`、`desk accessory process` 之外，
**其余全部 `inherits="UI element"`**。

这意味着：**读懂 `UI element` 一个类，就读懂了所有控件的公共能力。**

#### `UI element` 的 19 个属性（本机 sdef 原文）

| 属性 | 类型 | r/o | 含义与用途 |
| --- | --- | --- | --- |
| `class` | type | ✓ | 该元素的 System Events 类，用于 `if class of e is button` |
| `role` | text | ✓ | AXRole 字符串，如 `AXButton` |
| `subrole` | text \| mv \| any | ✓ | AXSubrole，如 `AXDialog`、`AXSearchField`（§10.5.5） |
| `role description` | text | ✓ | role 的本地化描述，如「按钮」 |
| `title` | text | ✓ | **屏幕上显示的标题**，本地化敏感 |
| `description` | text \| mv \| any | ✓ | 有 accessibility description 就用它，否则回落到 role description |
| `accessibility description` | text \| mv \| any | ✓ | 开发者提供的完整能力描述 |
| `help` | text \| mv \| any | ✓ | 详细帮助文本（tooltip） |
| `name` | text | ✓ | 容器内的标识名，**不一定等于 title** |
| `value` | reference \| number \| text \| any | | 当前值。文本框是 text，滑块是 number |
| `enabled` | bool \| mv \| any | ✓ | 是否接受点击 |
| `focused` | bool \| mv \| any | | 是否有焦点（**可写**：`set focused to true`） |
| `selected` | bool \| mv \| any | | 是否选中（**可写**） |
| `position` | list of number \| mv \| any | | `{x, y}` 全局屏幕坐标（可写） |
| `size` | list of number \| mv \| any | | `{宽, 高}`（可写） |
| `orientation` | text \| mv \| any | ✓ | `AXHorizontal` / `AXVertical` |
| `minimum value` | number \| mv \| any | ✓ | 数值下限（slider、incrementor） |
| `maximum value` | number \| mv \| any | ✓ | 数值上限 |
| `entire contents` | list of reference | ✓ | **递归展开整棵子树**，很慢（§10.5.13） |

⚠️⚠️ **注意类型里的 `| missing value | any`。**
同一个属性在不同控件上可能返回**不同类型**，也可能返回 `missing value`。
`value of text field 1` 是 text，`value of slider 1` 是 number，
`value of button 1` 常常是 `missing value`。
写通用遍历代码时，任何属性读取都要 `try` 兜底，不能假设类型。

#### `UI element` 能响应的命令

sdef 里的 `responds to`：`click, select, increment, decrement, confirm, pick, cancel`。
其中 5 个在 Hidden Suite（§10.5.2）。另外 Standard Suite 的 `get`/`set`/`exists`/`count`
对所有 UI 类都有效，但不会列在 `responds to` 里（§8.3）。

#### ⚠️ `window` 是扩展来的，不是定义的

System Events 的 sdef 里搜不到 `<class name="window">`，只有：

```xml
<class-extension extends="window" description="A window belonging to a process">
	<responds-to command="click">…</responds-to>
	<element type="button">…</element>
	<!-- 共 40 个 element + 7 个 responds-to -->
</class-extension>
```

后果很实际：

- `name of window 1`、`index of window 1`、`bounds of window 1` 来自 **Standard Suite**；
- `buttons of window 1`、`sheets of window 1`、`click window 1` 来自 **System Events 的扩展**；
- 用 `grep '<class name='` 查字典会**完全看不到 window**，误以为不支持（§8.4、§8.6）。

`process` 类同样是 `inherits="UI element"`，额外有 `menu bar` 和 `window` 两种 element，
以及 `bundle identifier`、`unix id`、`frontmost`、`visible`、`background only` 等属性。
`application process` 再继承 `process`，多一个 `application file`。

### 10.5.4 AXRole ↔ System Events 类名完整对照表

本机 SDK 实测共 **58 个 AXRole**，其中 **41 个**在 System Events 里有对应类，
**17 个没有**。没有对应类的，只能用通用写法：

```applescript
tell application "System Events" to tell process "SomeApp"
	-- ❌ System Events 里没有 "cell" 这个类，这样写编译不过
	-- get every cell of table 1 of window 1

	-- ✅ 用通用 UI element + role 过滤
	get (every UI element of row 1 of table 1 of window 1 whose role is "AXCell")
end tell
```
🔵

⚠️⚠️ **`whose` 子句必须写在容器表达式的最后面。** 下面两种写法只差语序，
但第一种**编译期**就失败：

```applescript
-- ❌ 编译报错：Can’t get "AXCell" of row 1 …  Access not allowed. (-1723)
get every UI element whose role is "AXCell" of row 1 of table 1 of window 1

-- ✅ whose 放在整个 of 链之后
get (every UI element of row 1 of table 1 of window 1 whose role is "AXCell")
```

⚠️ `-1723` 的信息是「Access not allowed」，很有误导性——它其实是**语序错**，不是权限问题。
建议给 `whose` 表达式整体加括号，可读性和正确率都会提高。

⚠️ 反过来，System Events 的每个 UI 类都能对应到一个 AXRole（实测无孤儿类），
所以**看到 Inspector 里的 `AXxxx`，一定能查这张表翻译成代码**。

| AXRole | System Events 类名 | 代码写法 |
| --- | --- | --- |
| `AXApplication` | `process` / `application process` | `process "Safari"` |
| `AXBrowser` | `browser` | `browser 1 of window 1` |
| `AXBusyIndicator` | `busy indicator` | `busy indicator 1 of window 1` |
| `AXButton` | `button` | `button 1 of window 1` |
| `AXCell` | ❌ 无 | `UI element whose role is "AXCell"` |
| `AXCheckBox` | `checkbox` | `checkbox 1 of window 1` |
| `AXColorWell` | `color well` | `color well 1 of window 1` |
| `AXColumn` | `column` | `column 1 of window 1` |
| `AXComboBox` | `combo box` | `combo box 1 of window 1` |
| `AXDateField` | ❌ 无 | `UI element whose role is "AXDateField"` |
| `AXDisclosureTriangle` | ❌ 无 | `UI element whose role is "AXDisclosureTriangle"` |
| `AXDockItem` | ❌ 无 | `UI element whose role is "AXDockItem"` |
| `AXDrawer` | `drawer` | `drawer 1 of window 1` |
| `AXGrid` | ❌ 无 | `UI element whose role is "AXGrid"` |
| `AXGroup` | `group` | `group 1 of window 1` |
| `AXGrowArea` | `grow area` | `grow area 1 of window 1` |
| `AXHandle` | ❌ 无 | `UI element whose role is "AXHandle"` |
| `AXHeading` | ❌ 无 | `UI element whose role is "AXHeading"` |
| `AXHelpTag` | ❌ 无 | `UI element whose role is "AXHelpTag"` |
| `AXImage` | `image` | `image 1 of window 1` |
| `AXIncrementor` | `incrementor` | `incrementor 1 of window 1` |
| `AXLayoutArea` | ❌ 无 | `UI element whose role is "AXLayoutArea"` |
| `AXLayoutItem` | ❌ 无 | `UI element whose role is "AXLayoutItem"` |
| `AXLevelIndicator` | ❌ 无 | `UI element whose role is "AXLevelIndicator"` |
| `AXList` | `list` | `list 1 of window 1` |
| `AXMatte` | ❌ 无 | `UI element whose role is "AXMatte"` |
| `AXMenu` | `menu` | `menu 1 of window 1` |
| `AXMenuBar` | `menu bar` | `menu bar 1 of window 1` |
| `AXMenuBarItem` | `menu bar item` | `menu bar item 1 of window 1` |
| `AXMenuButton` | `menu button` | `menu button 1 of window 1` |
| `AXMenuItem` | `menu item` | `menu item 1 of window 1` |
| `AXOutline` | `outline` | `outline 1 of window 1` |
| `AXPopover` | `pop over` | `pop over 1 of window 1` |
| `AXPopUpButton` | `pop up button` | `pop up button 1 of window 1` |
| `AXProgressIndicator` | `progress indicator` | `progress indicator 1 of window 1` |
| `AXRadioButton` | `radio button` | `radio button 1 of window 1` |
| `AXRadioGroup` | `radio group` | `radio group 1 of window 1` |
| `AXRelevanceIndicator` | `relevance indicator` | `relevance indicator 1 of window 1` |
| `AXRow` | `row` | `row 1 of window 1` |
| `AXRuler` | ❌ 无 | `UI element whose role is "AXRuler"` |
| `AXRulerMarker` | ❌ 无 | `UI element whose role is "AXRulerMarker"` |
| `AXScrollArea` | `scroll area` | `scroll area 1 of window 1` |
| `AXScrollBar` | `scroll bar` | `scroll bar 1 of window 1` |
| `AXSheet` | `sheet` | `sheet 1 of window 1` |
| `AXSlider` | `slider` | `slider 1 of window 1` |
| `AXSplitGroup` | `splitter group` | `splitter group 1 of window 1` |
| `AXSplitter` | `splitter` | `splitter 1 of window 1` |
| `AXStaticText` | `static text` | `static text 1 of window 1` |
| `AXSystemWide` | ❌ 无 | `UI element whose role is "AXSystemWide"` |
| `AXTabGroup` | `tab group` | `tab group 1 of window 1` |
| `AXTable` | `table` | `table 1 of window 1` |
| `AXTextArea` | `text area` | `text area 1 of window 1` |
| `AXTextField` | `text field` | `text field 1 of window 1` |
| `AXTimeField` | ❌ 无 | `UI element whose role is "AXTimeField"` |
| `AXToolbar` | `toolbar` | `toolbar 1 of window 1` |
| `AXUnknown` | ❌ 无 | `UI element whose role is "AXUnknown"` |
| `AXValueIndicator` | `value indicator` | `value indicator 1 of window 1` |
| `AXWindow` | `window`（class-extension，§10.5.3） | `window 1 of process "Safari"` |

**17 个无对应类的 role**，按出现频率分三类：

| 类别 | role | 实际怎么办 |
| --- | --- | --- |
| **表格/网格类** | `AXCell`、`AXGrid`、`AXRow`有类但`AXCell`没有 | 表格优先用 `row`/`column` + `value of static text 1 of UI element 1 of row 3`；或 `entire contents` 兜底 |
| **Web/ARIA 类** | `AXHeading`、`AXLayoutArea`、`AXLayoutItem`、`AXLevelIndicator`、`AXDateField`、`AXTimeField`、`AXImageMap`、`AXUnknown` | 只在 Safari/WebView 里出现。⚠️ 网页内容**优先用 `do JavaScript`**（§14.1），别爬 AX 树 |
| **装饰/罕见类** | `AXDisclosureTriangle`、`AXHandle`、`AXHelpTag`、`AXMatte`、`AXRuler`、`AXRulerMarker`、`AXDockItem`、`AXSystemWide` | 一般不需要点它们。三角展开用 `disclosure triangle` 的替代：`click` 它的父 `row`，或 `perform action "AXPress"` |

⚠️ `AXImageMap` 不在 `AXRoleConstants.h` 里，而在 `AXWebConstants.h`——
Web 相关的 role/subrole 是单独一套头文件，查的时候要一起看。

### 10.5.5 subrole：区分「这是哪一种窗口」——模态定位的钥匙

`role` 只告诉你「这是个 window」，**`subrole` 才告诉你「这是个对话框」**。
本机 SDK 实测 `AXRoleConstants.h` 里有 37 个原生 subrole，加上 `AXWebConstants.h`
等文件里的 Web/ARIA subrole，全部头文件合计 **93 个**（其中 `AXWebConstants.h` 占 56 个）。

#### 与「弹窗/对话框」直接相关的 subrole

| subrole 字符串 | SDK 常量 | 含义 | 典型来源 |
| --- | --- | --- | --- |
| `AXStandardWindow` | `kAXStandardWindowSubrole` | 普通窗口 | 绝大多数 App 主窗口 |
| `AXDialog` | `kAXDialogSubrole` | **App 自己的对话框** | `NSAlert`、自绘对话框 |
| `AXSystemDialog` | `kAXSystemDialogSubrole` | **系统级对话框** | 系统弹窗 |
| `AXFloatingWindow` | `kAXFloatingWindowSubrole` | 浮动面板 | 工具面板、调色板 |
| `AXSystemFloatingWindow` | `kAXSystemFloatingWindowSubrole` | 系统浮动面板 | 系统级浮层 |
| `AXApplicationDialog` | `kAXApplicationDialogSubrole` | Web `role=dialog` | Safari / WebView |
| `AXApplicationAlert` | `kAXApplicationAlertSubrole` | Web `role=alert` | Safari / WebView |
| `AXApplicationAlertDialog` | `kAXApplicationAlertDialogSubrole` | Web `role=alertdialog` | Safari / WebView |

⚠️ 后三个是 **Web/ARIA 专用**，定义在 `AXWebConstants.h`。
Safari 里 `alert()` / 模态 `<dialog>` 会呈现成这些 subrole，
但它们**挂在 Safari 的 window 之下，不是独立 window**。

#### 与控件相关的常用 subrole

| subrole | 用途 |
| --- | --- |
| `AXCloseButton` / `AXMinimizeButton` / `AXZoomButton` / `AXFullScreenButton` | 窗口左上角「红绿灯」+ 全屏按钮。**比 `button 1 of window 1` 可靠得多** |
| `AXSearchField` | 搜索框（`text field` 的一种） |
| `AXSecureTextField` | 密码框（⚠️ 读不到 `value`，系统禁止） |
| `AXToolbarButton` | 工具栏按钮，用于和普通按钮区分 |
| `AXSortButton` | 表格排序按钮 |
| `AXSwitch` / `AXToggle` | 开关型控件 |
| `AXRatingIndicator` | 星级评分 |
| `AXContentList` / `AXTableRow` / `AXOutlineRow` | 列表/表格行的细分 |
| `AXIncrementArrow` / `AXDecrementArrow` / `AXIncrementPage` / `AXDecrementPage` | 滚动箭头与翻页区 |
| `AXProcessSwitcherList` | ⌘Tab 切换器 |
| `AXTimeline` / `AXDecorative` / `AXUnknown` | 时间轴 / 纯装饰 / 未知 |
| `AXDocumentDockItem` / `AXFolderDockItem` / `AXTrashDockItem` / `AXURLDockItem` / `AXMinimizedWindowDockItem` / `AXSeparatorDockItem` / `AXApplicationDockItem` / `AXDockExtraDockItem` | Dock 里的各类图标（属 Dock 进程） |

### 10.5.6 attribute：读那 130 多个没暴露成属性的 AXAttribute

System Events 只把 19 个 AX 属性做成了 `UI element` 的原生属性（§10.5.3）。
其余全部要通过 `attribute` 类访问：

```applescript
tell application "System Events" to tell process "Safari"
	set w to window 1

	-- 1) 先列出这个元素到底支持哪些 AX 属性（比查文档准）
	get name of every attribute of w

	-- 2) 读单个属性
	get value of attribute "AXModal" of w          --> true / false
	get value of attribute "AXMain" of w           --> 是否主窗口
	get value of attribute "AXDocument" of w       --> "file:///Users/…/a.pdf"

	-- 3) 读某个子元素的稳定 ID（最重要的定位锚点，见 §10.5.8）
	get value of attribute "AXIdentifier" of button 1 of toolbar 1 of w

	-- 4) 遍历属性名+值，做调试快照
	set snapshot to {}
	repeat with anAttr in (attributes of w)
		set end of snapshot to {(name of anAttr), (value of anAttr)}
	end repeat
end tell
```
🔵

⚠️ **不是每个元素都支持每个属性。** `attribute "AXModal" of button 1` 会直接抛错，
不是返回 `missing value`。任何 `attribute` 读取都要套 `try`。

⚠️ `AXSheets` **不是** attribute（本机 SDK 里没有这个常量）。
sheet 在 System Events 里是 `window` 的一种 **element**：`sheet 1 of window 1`。

#### 定位与弹窗排查最常用的 AXAttribute

| AX 属性 | 类型 | 用途 |
| --- | --- | --- |
| `AXIdentifier` | text | **开发者手设的稳定 ID**。不受本地化、不受 UI 重排影响，是最可靠的锚点 |
| `AXModal` | bool | 该窗口是否模态 → **判断「有没有弹窗挡住」的第一手段** |
| `AXMain` | bool | 是否主窗口 |
| `AXFrontmost` | bool | 在 `process` 上：是否最前台 |
| `AXTopLevelUIElement` | list | 在 `process` 上：所有顶层元素（窗口 + 菜单栏） |
| `AXParent` / `AXChildren` | element / list | 手动上下遍历树，绕开 System Events 的类名限制 |
| `AXDefaultButton` / `AXCancelButton` | element | **直接拿到对话框的「默认按钮」和「取消按钮」**，不用猜按钮名（§10.5.10） |
| `AXCloseButton` / `AXMinimizeButton` / `AXZoomButton` / `AXFullScreenButton` | element | 红绿灯按钮的稳定引用 |
| `AXShownMenuUIElement` | element | 当前展开的菜单对象 |
| `AXDocument` | text (file URL) | 窗口对应的文件路径 |
| `AXFocused` / `AXFocusedUIElement` | bool / element | 焦点状态；后者在 `process`/`application` 上取当前焦点元素 |
| `AXPlaceholderValue` | text | 输入框的占位提示文字，常用于辨认「这是搜索框还是地址栏」 |
| `AXSelectedText` / `AXSelectedTextRange` | text / AXValue | 文本选中内容与范围 |
| `AXNumberOfCharacters` | int | 文本长度 |
| `AXExpanded` / `AXDisclosing` | bool | 展开状态（ disclosure、outline row） |
| `AXRoleDescription` / `AXValueDescription` | text | 本地化描述文本 |
| `AXHelp` | text | 帮助/tooltip 文本 |
| `AXTabs` / `AXContents` / `AXWindows` | list | 标签页、内容区、窗口集合 |

#### `attribute` vs 原生属性：什么时候必须用哪个

```applescript
tell application "System Events" to tell process "TextEdit"
	-- 这两个等价，优先用上面的（更快、错误信息更清楚）
	get title of button 1 of window 1
	get value of attribute "AXTitle" of button 1 of window 1

	-- 这个只能用 attribute（System Events 没暴露 AXIdentifier）
	get value of attribute "AXIdentifier" of button 1 of window 1
end tell
```
🔵

⚠️ 用 `attribute` 比用原生属性**慢**，因为多一层对象封装。批量遍历时优先原生属性。

### 10.5.7 元素引用的五种写法

```applescript
tell application "System Events" to tell process "Safari"

	-- ① 按索引：最脆，UI 一变就错位
	click button 2 of toolbar 1 of window 1

	-- ② 按 name / title：直观，但本地化敏感
	click button "重新载入" of toolbar 1 of window 1

	-- ③ 按 whose 过滤任意属性：最灵活，可组合多条件
	click (first button of toolbar 1 of window 1 whose description contains "重新载入")
	click (first UI element of window 1 whose role is "AXButton" and title is "OK")

	-- ④ 按 AXIdentifier：最稳（前提是开发者设了）
	click (first button of window 1 whose value of attribute "AXIdentifier" is "com.apple.Safari.reload")

	-- ⑤ 按 subrole：定位对话框/特殊窗口的唯一可靠手段
	set dlg to (first window of process "Safari" whose subrole is "AXSystemDialog")

end tell
```
🔵

⚠️ ④ 的写法要注意：`whose value of attribute "AXIdentifier" is …` 在某些 macOS 版本上
过滤效率极低甚至超时。稳妥做法是先取候选集再在 AppleScript 侧筛：

```applescript
tell application "System Events" to tell process "Safari"
	set allButtons to every button of window 1
	repeat with b in allButtons
		try
			if (value of attribute "AXIdentifier" of b) is "com.apple.Safari.reload" then
				click b
				exit repeat
			end if
		end try
	end repeat
end tell
```
🔵

⚠️ `whose` 里能用的是**该类的属性名**。`UI element` 的 19 个属性都可以，
但 `attribute "AXxxx"` 这种嵌套取值在 `whose` 里支持得不稳定，能避就避。

### 10.5.8 定位可靠性排序（照这个顺序选）

| 排名 | 定位方式 | 稳定性 | 代价 |
| --- | --- | --- | --- |
| **1** | `AXIdentifier` | ★★★★★ 不随语言、不随布局变 | 需要开发者设了才有；很多 App 没设 |
| **2** | `subrole` + `role` 组合 | ★★★★☆ 语义稳定 | 需要 Inspector 确认（§11） |
| **3** | `title` / `description` | ★★★☆☆ | ⚠️ **本地化敏感**：中文系统 `"关闭"`，英文系统 `"Close"` |
| **4** | 结构路径（`toolbar 1 of window 1`） | ★★☆☆☆ | App 改版即失效 |
| **5** | 纯索引（`button 2`） | ★☆☆☆☆ | 最脆，只在结构绝对固定时用 |
| **6** | 坐标（`click at {x, y}`） | ☆☆☆☆☆ | 分辨率/窗口位置一变就废，**仅做最后兜底** |

#### 处理本地化的正确姿势

不要硬编码按钮文字。三种可行方案：

```applescript
-- 方案 A：双语候选表
set okNames to {"好", "确定", "OK", "Continue", "继续"}
tell application "System Events" to tell process "SomeApp"
	repeat with n in okNames
		if exists (button n of window 1) then
			click button n of window 1
			exit repeat
		end if
	end repeat
end tell

-- 方案 B：用 AXDefaultButton / AXCancelButton（完全绕开文字，强烈推荐）
tell application "System Events" to tell process "SomeApp"
	set w to window 1
	set defBtn to value of attribute "AXDefaultButton" of w
	click defBtn
end tell

-- 方案 C：按 role + 位置推断（如「最右下角的按钮」）
```
🔵

⚠️⚠️ **方案 B 是处理系统弹窗的正解**：系统对话框一定设了 `AXDefaultButton`，
且不随语言变化。详见 §10.5.10。

### 10.5.9 动态定位元素的标准流程（七步法）

「动态定位」= 控件的位置、索引、甚至是否存在都不确定（异步加载、
可选弹窗、A/B 界面、多窗口）。**不要边猜边写**，按下面七步走。

#### 第 1 步：确认权限，失败就立刻退出

```applescript
on assertAccessibility()
	tell application "System Events"
		if not (UI elements enabled) then
			error "未获得辅助功能权限。请到「系统设置 → 隐私与安全性 → 辅助功能」" & ¬
				"把当前宿主程序（终端 / Script Editor / 你的 .app）加进去并勾选，然后完全退出重开。" & ¬
				"注意：授权后必须重启宿主进程才生效。" number 10001
		end if
	end tell
end assertAccessibility
```
✅ 本函数中 `UI elements enabled` 实测可正常运行（本机返回 `false`，即未授权）。

⚠️⚠️ 没权限时的报错**不止一种**，本机实测：

| 你写的代码 | 实测报错码 |
| --- | --- |
| `count of windows of process "X"` | `-25211` |
| `name of window 1 of process "X"` | `-1719` |
| `UI elements of window 1` | `-1719` |
| `name of every window of process "NotificationCenter"` | `-1728` |
| `keystroke "a"` | `-25211` |

本机实测 `-1728` 的完整信息是：

```
System Events got an error: osascript is not allowed assistive access. (-1728)
```

⚠️⚠️ 同一个根因（无辅助功能权限），**错误码至少有 `-25211` / `-1719` / `-1728` 三种**，
而 `-1728` 的官方含义是 `errAEUnknownObject`（找不到对象），`-1719` 是 `errAEIllegalAccess`。
**别去查错误码表，要看错误信息文本里有没有 `assistive access`。**
有 → 权限问题；没有 → 才真的是定位/语法问题。

#### 第 2 步：确认进程存在、能拿到窗口

```applescript
on ensureReady(procName)
	tell application "System Events"
		if not (exists process procName) then
			error "进程不存在：" & procName number 10002
		end if
		set frontmost of process procName to true
	end tell
	-- 轮询等窗口出现，而不是死等固定秒数
	set deadline to (current date) + 10
	repeat while (current date) < deadline
		tell application "System Events"
			if (count of windows of process procName) > 0 then return true
		end tell
		delay 0.2
	end repeat
	error "进程已启动但 10 秒内没出现窗口：" & procName number 10003
end ensureReady
```
🔵

⚠️ `count of windows` 本身就需要辅助功能权限。无权限时这一步会直接 `-25211`，
所以第 1 步必须先跑。

#### 第 3 步：用 Accessibility Inspector 抓特征，不要靠猜

打开 Accessibility Inspector（§11），悬停到目标控件上，抄下这四项：

| Inspector 字段 | 记什么 | 对应代码 |
| --- | --- | --- |
| **Role** | `AXButton` | 决定用哪个类名（`button`）或 `role is "AXButton"` |
| **Subrole** | `AXCloseButton` / `AXDialog` | 区分同类控件 |
| **Title / Description** | 屏幕上的文字 | `title` / `description` |
| **Value / Identifier** | `AXIdentifier` 有没有值 | 有 → 直接用它，定位问题解决 |

⚠️ 别跳过这一步。「我看它像个按钮就写 `button 1`」是 UI 脚本失败的最大来源。
很多看起来是按钮的东西，AX 树里其实是 `AXGroup` 里的 `AXStaticText` + `AXImage`，
`click` 上去毫无反应。

#### 第 4 步：按 §10.5.8 的顺序选锚点，并写成「查找函数」

不要在业务逻辑里散落 `button 2 of toolbar 1 of window 1`。
把定位收敛成函数，改起来只改一处：

```applescript
-- 按 role + title 在容器里找，找不到返回 missing value
on findByRoleAndTitle(theContainer, theRole, theTitle)
	tell application "System Events"
		set candidates to (every UI element of theContainer whose role is theRole)
		repeat with c in candidates
			try
				if (title of c) is theTitle then return c
			end try
			try
				if (description of c) is theTitle then return c
			end try
		end repeat
	end tell
	return missing value
end findByRoleAndTitle
```
🔵

#### 第 5 步：先 `exists` 再操作，操作后 `delay`

```applescript
tell application "System Events" to tell process "Safari"
	set theButton to my findByRoleAndTitle(toolbar 1 of window 1, "AXButton", "重新载入")
	if theButton is missing value then
		-- 走降级路径，而不是让脚本报错崩掉
		keystroke "r" using {command down}
	else if (enabled of theButton) then
		click theButton
		delay 0.5      -- ⚠️ 必须等，UI 更新是异步的
	end if
end tell
```
🔵

⚠️ `exists` 对**结构不合法**的引用会抛错而不是返回 `false`。
例如 `exists button 99 of window 1` 通常返回 false，
但 `exists menu bar item "不存在的菜单" of menu bar 1` 在某些 App 上会抛错。
所以外层永远套 `try`。

#### 第 6 步：失败时 dump 子树，而不是继续猜

把这段存成常用工具，定位失败时跑一次，胜过盯屏幕半小时：

```applescript
-- 递归导出 UI 树。maxDepth 控制深度，避免 entire contents 那样炸开
on dumpUI(theElement, depth, maxDepth, outRef)
	set indent to ""
	repeat depth times
		set indent to indent & "  "
	end repeat
	tell application "System Events"
		set theRole to "?"
		set theTitle to ""
		set theSub to ""
		try
			set theRole to role of theElement
		end try
		try
			set theTitle to title of theElement
		end try
		try
			set theSub to subrole of theElement
		end try
	end tell
	set theLine to indent & theRole
	if theSub is not "" and theSub is not missing value then set theLine to theLine & "/" & theSub
	if theTitle is not "" and theTitle is not missing value then set theLine to theLine & "  \"" & theTitle & "\""
	my writeLine(outRef, theLine)
	if depth ≥ maxDepth then return
	tell application "System Events"
		try
			set kids to UI elements of theElement
		on error
			return
		end try
	end tell
	repeat with k in kids
		my dumpUI(k, depth + 1, maxDepth, outRef)
	end repeat
end dumpUI

on writeLine(outRef, theLine)
	write theLine & linefeed to outRef as «class utf8»
end writeLine

-- 用法：把整个窗口树导到文件
set outPath to ((path to desktop as text) & "ui-dump.txt")
set fh to open for access file outPath with write permission
set eof fh to 0
tell application "System Events" to tell process "Safari"
	my dumpUI(window 1, 0, 6, fh)
end tell
close access fh
```
🔵

要点：

- **`maxDepth` 必须设**。不加限制时深层树可能几万个节点，跑几分钟。
- 每个属性读取都单独 `try`：不同控件支持的属性不同（§10.5.6）。
- 用 `write … as «class utf8»`，否则中文标题会写坏（§9）。
- 比 `entire contents` 好：`entire contents` 一次性返回整棵树的引用列表，
  内存和耗时都不可控（§10.5.13）。

#### 第 7 步：超时后降级，别让脚本卡死

降级顺序（从可靠到粗暴）：

| 顺序 | 手段 | 说明 |
| --- | --- | --- |
| 1 | **键盘快捷键** | `keystroke "s" using {command down}`。不依赖任何控件定位，最稳 |
| 2 | **菜单栏** | `click menu item "存储" of menu "文件" of menu bar 1`。菜单结构比窗口内容稳定得多 |
| 3 | **`perform action`** | `perform action "AXPress" of …`。有些控件 `click` 无效但 `AXPress` 有效 |
| 4 | **换属性重试** | title 不行换 description，再不行换 `AXIdentifier` |
| 5 | **坐标点击** | `click process "X" at {x, y}`。最后手段，必须先记录当前分辨率与窗口位置 |
| 6 | **放弃并报告** | 写日志 + `display notification`，让人来接手 |

```applescript
on clickWithFallback(procName, theTitle, fallbackKeystroke, fallbackMods)
	tell application "System Events" to tell process procName
		repeat with n in theTitle
			try
				if exists (button n of window 1) then
					click button n of window 1
					delay 0.4
					return "clicked:" & n
				end if
			end try
		end repeat
	end tell
	tell application "System Events"
		keystroke fallbackKeystroke using fallbackMods
		delay 0.4
	end tell
	return "fallback:keystroke"
end clickWithFallback

-- 用法
clickWithFallback("TextEdit", {"存储", "Save"}, "s", {command down})
```
🔵

### 10.5.10 模态消息框与系统弹窗的定位

这是 UI Scripting 里最容易翻车的一块。「弹窗」在 macOS 上其实有**四种完全不同的东西**，
它们在 AX 树里的位置、宿主进程、可操作性都不一样。先分清是哪一种，再写代码。

| 类别 | 长什么样 | AX 树位置 | 宿主进程 | 能否自动化 |
| --- | --- | --- | --- | --- |
| **A. Sheet（抽屉面板）** | 从窗口顶部滑下来的面板 | 目标 window 的**子元素** | 目标 App | ✅ 可以 |
| **B. App 模态对话框** | 独立浮出的对话框，挡住父窗口 | **独立的 window**，`subrole` = `AXDialog` / `AXSystemDialog` | 目标 App | ✅ 可以 |
| **C. 系统弹窗（TCC/权限/密码）** | 「XX 想访问你的通讯录」「允许/不允许」 | 独立 window | ⚠️ **不是目标 App**，是系统进程 | ⚠️ 部分可以 |
| **D. 通知横幅** | 右上角滑出的通知 | 独立 window | `NotificationCenter` | ⚠️ 基本不该点 |

⚠️⚠️ **最大的坑：在错误的进程里找弹窗。**
`tell process "Safari"` 里永远找不到「Safari 想访问你的位置」这个系统弹窗——
它的宿主是系统进程。本机实测，当前正在运行的相关系统进程有：

```
UserNotificationCenter        ← TCC 权限弹窗（「XX 想访问…」）的宿主
NotificationCenter            ← 通知横幅的宿主
SecurityPrivacyExtension      ← 安全/隐私相关扩展 UI
loginwindow                   ← 登录、锁屏、注销确认
ControlCenter                 ← 控制中心
Dock                          ← Dock 与部分系统浮层
```

对应的 bundle id（本机实测）：

| 进程名 | bundle id | App 路径 |
| --- | --- | --- |
| `UserNotificationCenter` | `com.apple.UserNotificationCenter` | `/System/Library/CoreServices/UserNotificationCenter.app` |
| `NotificationCenter` | `com.apple.notificationcenterui` | `/System/Library/CoreServices/NotificationCenter.app` |

#### 类别 A：Sheet

sheet 是 **window 的子元素**，不是独立窗口：

```applescript
tell application "System Events" to tell process "Finder"
	if (count of sheets of window 1) > 0 then
		set theSheet to sheet 1 of window 1
		-- sheet 内部照常找控件
		get name of every button of theSheet
		-- 最稳的按法：用 AXDefaultButton
		try
			click (value of attribute "AXDefaultButton" of theSheet)
		on error
			click button 1 of theSheet
		end try
	end if
end tell
```
🔵

判断「有没有 sheet 挡着」：

```applescript
tell application "System Events" to tell process "Finder"
	set hasSheet to false
	repeat with w in (windows)
		if (count of sheets of w) > 0 then
			set hasSheet to true
			exit repeat
		end if
	end repeat
end tell
```
🔵

⚠️ sheet 出现有动画，`count of sheets` 可能在动画期间返回 0。用轮询等待（§10.5.12）。

#### 类别 B：App 模态对话框（独立 window）

App 自己弹的 `NSAlert` 通常是**独立 window**，靠 `subrole` 辨认：

```applescript
on findAppDialog(procName, timeoutSec)
	set deadline to (current date) + timeoutSec
	repeat while (current date) < deadline
		tell application "System Events" to tell process procName
			-- 依次尝试各种对话框 subrole
			repeat with sub in {"AXSystemDialog", "AXDialog", "AXApplicationAlertDialog", "AXApplicationDialog"}
				try
					set w to (first window whose subrole is sub)
					if exists w then return w
				end try
			end repeat
			-- 兜底：靠 AXModal 属性
			try
				set w to (first window whose value of attribute "AXModal" is true)
				if exists w then return w
			end try
		end tell
		delay 0.25
	end repeat
	return missing value
end findAppDialog
```
🔵

拿到对话框后，**优先用 `AXDefaultButton` / `AXCancelButton`，不要猜按钮文字**：

```applescript
tell application "System Events" to tell process "TextEdit"
	set dlg to my findAppDialog("TextEdit", 5)
	if dlg is not missing value then
		try
			click (value of attribute "AXCancelButton" of dlg)   -- 「不存储」
		on error
			try
				click (value of attribute "AXDefaultButton" of dlg)  -- 「存储」
			on error
				click (last button of dlg)   -- 最后兜底
			end try
		end try
	end if
end tell
```
🔵

⚠️ `AXDefaultButton` 是「按回车会触发的那个」，`AXCancelButton` 是「按 Esc 会触发的那个」。
**它们和「左边/右边的按钮」没有固定对应关系**，不同 App 布局不同。
所以更稳的做法其实是——直接发按键：

```applescript
tell application "System Events"
	key code 53    -- Esc = 取消
	key code 36    -- Return = 默认按钮
end tell
```
🔵

#### 类别 C：系统弹窗（权限请求、密码框）

⚠️⚠️ **这类弹窗不在目标 App 的进程里。** 正确做法是「全系统扫描」：

```applescript
-- 扫描所有进程，找出任何 subrole 是对话框 / 或 AXModal 为 true 的窗口
on findModalAnywhere(timeoutSec)
	set deadline to (current date) + timeoutSec
	set dialogSubroles to {"AXSystemDialog", "AXDialog", "AXApplicationAlertDialog"}
	repeat while (current date) < deadline
		tell application "System Events"
			repeat with p in (every process whose background only is false)
				set procName to name of p
				try
					repeat with w in (windows of p)
						set sub to ""
						try
							set sub to subrole of w
						end try
						if dialogSubroles contains sub then
							return {procName, w, sub}
						end if
					end repeat
				end try
			end repeat
			-- TCC 弹窗宿主：UserNotificationCenter 是 background only，要单独扫
			if (exists process "UserNotificationCenter") then
				set unp to process "UserNotificationCenter"
				repeat with w in (windows of unp)
					return {"UserNotificationCenter", w, "TCC"}
				end repeat
			end if
		end tell
		delay 0.3
	end repeat
	return missing value
end findModalAnywhere
```
🔵

⚠️ `repeat with p in (every process …)` 拿到的是**引用**，对循环变量直接 `as text`
会报 `-1700`。要么用 `name of p`，要么先 `set procName to contents of p`（§16）。

本机实测该错误信息为：

```
Can’t make «class pcap» "Terminal" of application "System Events" into type text. (-1700)
```

⚠️ 注意里面的 `«class pcap»`——这就是 §8.8 说的「四字符码裸露」现象：
`process` 类的 code 是 `pcap`，术语没被解析成可读名字。看到 `«»` 就知道是术语层出了问题。

##### 关于 TCC 权限弹窗的现实建议

⚠️⚠️ **不要试图用脚本自动点掉权限弹窗。** 三个理由：

1. **设计上就是防自动化的**。系统会检测合成点击（`AXPress` 由非用户发起），
   某些弹窗对合成事件无响应。
2. **需要给脚本宿主辅助功能权限才能点**，而「授予辅助功能权限」本身就是一个
   TCC 弹窗——形成死循环：你需要权限去点那个授予权限的弹窗。
3. **正确解法是预先授权**，见 `docs/15-打包-定时任务与权限.md`。

如果只是想**检测**「有没有权限弹窗挡住了」然后中止脚本，用上面的
`findModalAnywhere` 就够了；检测到就报错退出，让人来处理。

#### 类别 D：通知横幅

宿主是 `NotificationCenter`（bundle id `com.apple.notificationcenterui`）。

⚠️ **不建议点通知横幅**：它几秒后自动消失，AX 树里生命周期极短，
且点击会打开对应 App，副作用不可控。

正确做法：

```applescript
-- 要「发」通知，用 StandardAdditions，不要去操作 NotificationCenter 的 UI
display notification "备份完成" with title "备份脚本" sound name "Glass"
```

要「读」通知，**AppleScript 没有官方途径**。
通知数据库受 TCC 保护、路径随 macOS 版本变化：本机实测
`~/Library/Group Containers/group.com.apple.UserNotifications/` 目录为空（读不到内容），
`$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/` 则根本不存在。
所以别指望这条路。要留痕就在发通知的同时自己写日志文件（§9）。

#### 四种弹窗的定位速查

```applescript
tell application "System Events"
	-- A. sheet
	tell process "Finder" to get buttons of sheet 1 of window 1

	-- B. App 对话框
	tell process "TextEdit" to get first window whose subrole is "AXDialog"

	-- C. 系统 TCC 弹窗
	if exists process "UserNotificationCenter" then
		tell process "UserNotificationCenter" to get buttons of window 1
	end if

	-- D. 通知横幅（只读，别点）
	if exists process "NotificationCenter" then
		tell process "NotificationCenter" to get name of every window
	end if
end tell
```
🔵

⚠️ `exists process "UserNotificationCenter"` 这类**进程存在性检查不需要辅助功能权限**（✅ 实测），
但一旦访问它的 `windows` / `buttons` 就需要。所以「探测在不在」很便宜，「读里面」要权限。

### 10.5.11 键盘与鼠标

#### `keystroke` vs `key code`：什么时候用哪个

| | `keystroke "文本"` | `key code 数字` |
| --- | --- | --- |
| 发送的是 | **字符** | **物理键位** |
| 受键盘布局影响 | ✅ 受影响（德语键盘上 `keystroke "z"` 打出 `y`） | ❌ 不受影响 |
| 能打中文/emoji | ✅ 可以 | ❌ 不行 |
| 能打方向键、F1~F12、Esc | ❌ **不行** | ✅ 只能这样打 |
| 典型用途 | 输入文字内容 | 按功能键、跨布局稳定按键 |

```applescript
tell application "System Events"
	keystroke "hello 世界"                       -- 输入文字
	keystroke "s" using {command down}            -- ⌘S
	keystroke "c" using {command down, shift down} -- ⇧⌘C
	key code 36                                   -- Return
	key code 53                                   -- Esc
	key code 125                                  -- ↓
	key code 125 using {shift down}               -- ⇧↓ 扩展选区
	key code {123, 123, 124}                      -- 可以传列表，连续按 ←←→
	delay 0.3
end tell
```
🔵

修饰键常量只有 **4 个**（本机 sdef 里 `eMds` 枚举的完整成员）：

```xml
<enumeration name="eMds" code="eMds">
	<enumerator name="command down" code="Kcmd"/>
	<enumerator name="control down" code="Kctl"/>
	<enumerator name="option down"  code="Kopt"/>
	<enumerator name="shift down"   code="Ksft"/>
</enumeration>
```

⚠️⚠️ **没有 `fn down`。** 网上大量教程写 `using {fn down}`，本机实测直接编译失败：

```
compilation error: Expected “,” or “}” but found application constant or consideration. (-2741)
```

要模拟 fn 组合键只能用 `key code` 配合系统设置里的 fn 行为，或走 `CGEvent`（§12）。

#### key code 完整对照表

来源：本机 SDK `HIToolbox.framework/Headers/Events.h` 的 `kVK_*` 常量（实测提取）。

⚠️ 这套码是**美式 ANSI 键盘布局的物理键位**，与键帽上印的字符无关。
| 键 | key code | SDK 常量 |
| --- | --- | --- |
| **常用编辑/导航键** |  |  |
| Return ↵ | `36` | `kVK_Return` |
| Tab ⇥ | `48` | `kVK_Tab` |
| 空格 | `49` | `kVK_Space` |
| ⌫ 退格 | `51` | `kVK_Delete` |
| ⌦ 前向删除 | `117` | `kVK_ForwardDelete` |
| Esc | `53` | `kVK_Escape` |
| Home ↖ | `115` | `kVK_Home` |
| End ↘ | `119` | `kVK_End` |
| Page Up ⇞ | `116` | `kVK_PageUp` |
| Page Down ⇟ | `121` | `kVK_PageDown` |
| Help ? | `114` | `kVK_Help` |
| ← 左 | `123` | `kVK_LeftArrow` |
| → 右 | `124` | `kVK_RightArrow` |
| ↑ 上 | `126` | `kVK_UpArrow` |
| ↓ 下 | `125` | `kVK_DownArrow` |
| **修饰键（单独按）** |  |  |
| ⌘ 左 Command | `55` | `kVK_Command` |
| ⌘ 右 Command | `54` | `kVK_RightCommand` |
| ⇧ 左 Shift | `56` | `kVK_Shift` |
| ⇧ 右 Shift | `60` | `kVK_RightShift` |
| ⌥ 左 Option | `58` | `kVK_Option` |
| ⌥ 右 Option | `61` | `kVK_RightOption` |
| ⌃ 左 Control | `59` | `kVK_Control` |
| ⌃ 右 Control | `62` | `kVK_RightControl` |
| ⇪ 大写锁定 | `57` | `kVK_CapsLock` |
| fn | `63` | `kVK_Function` |
| **功能键** |  |  |
| F1 | `122` | `kVK_F1` |
| F2 | `120` | `kVK_F2` |
| F3 | `99` | `kVK_F3` |
| F4 | `118` | `kVK_F4` |
| F5 | `96` | `kVK_F5` |
| F6 | `97` | `kVK_F6` |
| F7 | `98` | `kVK_F7` |
| F8 | `100` | `kVK_F8` |
| F9 | `101` | `kVK_F9` |
| F10 | `109` | `kVK_F10` |
| F11 | `103` | `kVK_F11` |
| F12 | `111` | `kVK_F12` |
| F13 | `105` | `kVK_F13` |
| F14 | `107` | `kVK_F14` |
| F15 | `113` | `kVK_F15` |
| **音量键** |  |  |
| 音量 + | `72` | `kVK_VolumeUp` |
| 音量 − | `73` | `kVK_VolumeDown` |
| 静音 | `74` | `kVK_Mute` |

**字母键**（`kVK_ANSI_*`，注意编号不按字母顺序）：

| 键 | code | 键 | code | 键 | code | 键 | code |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `A` | `0` | `B` | `11` | `C` | `8` | `D` | `2` |
| `E` | `14` | `F` | `3` | `G` | `5` | `H` | `4` |
| `I` | `34` | `J` | `38` | `K` | `40` | `L` | `37` |
| `M` | `46` | `N` | `45` | `O` | `31` | `P` | `35` |
| `Q` | `12` | `R` | `15` | `S` | `1` | `T` | `17` |
| `U` | `32` | `V` | `9` | `W` | `13` | `X` | `7` |
| `Y` | `16` | `Z` | `6` |  |  |  |  |

**数字与符号键**（`kVK_ANSI_*`）：

| 键 | code | SDK 常量 |
| --- | --- | --- |
| `0 )` | `29` | `kVK_ANSI_0` |
| `1 !` | `18` | `kVK_ANSI_1` |
| `2 @` | `19` | `kVK_ANSI_2` |
| `3 #` | `20` | `kVK_ANSI_3` |
| `4 $` | `21` | `kVK_ANSI_4` |
| `5 %` | `23` | `kVK_ANSI_5` |
| `6 ^` | `22` | `kVK_ANSI_6` |
| `7 &` | `26` | `kVK_ANSI_7` |
| `8 *` | `28` | `kVK_ANSI_8` |
| `9 (` | `25` | `kVK_ANSI_9` |
| `- _` | `27` | `kVK_ANSI_Minus` |
| `= +` | `24` | `kVK_ANSI_Equal` |
| `[ {` | `33` | `kVK_ANSI_LeftBracket` |
| `] }` | `30` | `kVK_ANSI_RightBracket` |
| `\ |` | `42` | `kVK_ANSI_Backslash` |
| `; :` | `41` | `kVK_ANSI_Semicolon` |
| `' "` | `39` | `kVK_ANSI_Quote` |
| `, <` | `43` | `kVK_ANSI_Comma` |
| `. >` | `47` | `kVK_ANSI_Period` |
| `/ ?` | `44` | `kVK_ANSI_Slash` |
| `` ~` | `50` | `kVK_ANSI_Grave` |

#### 鼠标：坐标点击与鼠标位置

`click` 支持 `at` 参数，用**全局屏幕坐标**（原点在主屏左上角，y 向下增长）：

```applescript
tell application "System Events"
	-- 在屏幕 (512, 300) 处点一下（发给 process 对象时用 at）
	click process "Finder" at {512, 300}
end tell
```
🔵

sdef 原文对 `at` 的说明：
`when sent to a "process" object, the { x, y } location at which to click, in global coordinates`。

⚠️⚠️ 坐标点击是**最后手段**：分辨率、缩放、窗口位置、菜单栏高度、多显示器排布
任一变化都会让它点错地方。用之前先读控件自己的 `position` / `size` 算中心点：

```applescript
on clickCenter(theElement)
	tell application "System Events"
		set p to position of theElement
		set s to size of theElement
	end tell
	set cx to (item 1 of p) + ((item 1 of s) / 2)
	set cy to (item 2 of p) + ((item 2 of s) / 2)
	tell application "System Events" to click process "Finder" at {cx, cy}
end clickCenter
```
🔵

读当前鼠标位置要用 Objective-C 桥（AppleScript 没有原生命令）。本机实测可用版本：

```applescript
use framework "AppKit"
use scripting additions      -- ⚠️ 必须加，否则 current date 等全废（§16）

set p to current application's NSEvent's mouseLocation()
set mouseX to x of p          -- ⚠️ 返回的是 record {x:…, y:…}，不是 list
set mouseY to y of p

-- 转成 AX 的「左上原点」坐标系
set screenH to item 2 of item 2 of (current application's NSScreen's mainScreen()'s frame())
set topLeftY to screenH - mouseY
```
✅ 实测通过（本机返回 `{x:1497.9, y:-40.1}`，`screenH` = 1080.0）。

⚠️⚠️ **两套坐标系原点是反的**：

| 来源 | 原点 | y 方向 |
| --- | --- | --- |
| AX `position` / `click at {x,y}` | 主屏**左上角** | 向下增大 |
| `NSEvent mouseLocation` / Cocoa `NSRect` | 主屏**左下角** | 向上增大 |

混用会导致点击位置上下颠倒。换算就是 `topLeftY = 屏幕高 - cocoaY`。
⚠️ 多显示器时 `cocoaY` 可能是负数（副屏在主屏下方），换算后 > 屏幕高，这是正常的。

⚠️ AppleScript **没有原生的「移动鼠标」「拖拽」「滚轮」命令**。
需要这些就得靠 `cliclick`（第三方 CLI，`brew install cliclick`）
或 Objective-C 桥调用 `CGEvent`。详见 §12。

### 10.5.12 等待与同步：把 `delay 3` 换成轮询

固定 `delay` 是 UI 脚本最常见的坏味道：设短了偶发失败，设长了慢得要死。
**永远用「轮询 + 超时」**。

#### 通用等待器

```applescript
-- 轮询直到 checker 返回 true，或超时返回 false
-- checker 是一个 script 对象，实现 check() 返回 boolean
on waitUntil(checker, timeoutSec, intervalSec)
	set deadline to (current date) + timeoutSec
	repeat while (current date) < deadline
		try
			if checker's check() then return true
		end try
		delay intervalSec
	end repeat
	return false
end waitUntil

-- 用法：等某个按钮出现
script buttonAppeared
	property procName : "Safari"
	on check()
		tell application "System Events" to tell process procName
			return exists (button "重新载入" of toolbar 1 of window 1)
		end tell
	end check
end script

if not my waitUntil(buttonAppeared, 10, 0.25) then
	error "等待超时：按钮没出现" number 10010
end if
```
🔵

⚠️ `checker's check()` 必须套 `try`：控件不存在时 `exists` 有时会抛错而不是返回 false（§10.5.9 第 5 步）。

#### 几个常用的等待条件

| 等什么 | 条件 |
| --- | --- |
| App 启动完成 | `(exists process "X")` 且 `(count of windows of process "X") > 0` |
| App 退出 | `not (exists process "X")` |
| 窗口标题变化 | `(name of window 1) contains "…"` |
| 加载结束 | `not (exists busy indicator 1 of window 1)`，或 `(value of attribute "AXBusy" …)` |
| 弹窗出现 | §10.5.10 的 `findAppDialog(…)` |
| 弹窗消失 | `findAppDialog(…)` 返回 `missing value` |
| 控件可用 | `(enabled of theButton) is true` |
| 文本框有内容 | `(value of textField) is not ""` |

#### 等待「不忙」的实用写法

```applescript
on waitNotBusy(procName, timeoutSec)
	set deadline to (current date) + timeoutSec
	repeat while (current date) < deadline
		tell application "System Events" to tell process procName
			try
				-- 有 busy indicator 说明还在转圈
				if (count of busy indicators of window 1) is 0 then return true
			end try
			try
				-- 有些 App 用 progress indicator
				if (count of progress indicators of window 1) is 0 then return true
			end try
		end tell
		delay 0.3
	end repeat
	return false
end waitNotBusy
```
🔵

⚠️ 轮询间隔别小于 `0.1` 秒。每次 `exists` 都是一个 Apple Event 往返，
太密会把 CPU 打满，还可能让目标 App 卡顿。`0.2`~`0.5` 是合理区间。

⚠️ AppleScript 收不到 AX Notification（§10.5.2），所以**没有真正的事件驱动等待**。
如果脚本对延迟极敏感，改用 Swift / Python(pyobjc) 注册
`kAXWindowCreatedNotification` 之类的回调。

### 10.5.13 可靠性忠告与性能

#### 可靠性

1. **能用字典就别用 UI Scripting。** UI Scripting 是「最后手段」（§8.9）。
   App 一升级，UI 层级就可能变，脚本随之失效；字典术语则相对稳定。
2. **别硬编码本地化字符串。** `click button "Close"` 在中文系统上是 `button "关闭"`。
   用 §10.5.8 的方案 A/B/C。
3. **操作前 `exists`，操作后 `delay`。** UI 更新是异步的，点完立刻读下一个控件
   常常读到旧状态。`delay 0.3`~`1` 是常态。
4. **目标 App 必须在前台且未被遮挡。** `set frontmost of process "X" to true`。
   ⚠️ 部分控件在窗口不可见时 `click` 会静默失败——不报错，但也没反应。
   必要时先 `perform action "AXRaise" of window 1` 把窗口提到前面。
5. **无头会话下 UI Scripting 基本会失败。** `launchd` 定时任务、SSH 会话、
   Screen Sharing 的某些模式下没有可用的 WindowServer 会话。
   定时任务里别依赖 UI Scripting（§15）。
6. **每一步都要有降级路径**（§10.5.9 第 7 步），并写日志，方便事后排查。
7. **把定位逻辑收敛到函数里**，别散落在业务流程中。UI 一变只改一处。

#### 性能

| 写法 | 速度 | 说明 |
| --- | --- | --- |
| `button 1 of window 1` | 最快 | 直接索引，一次事件 |
| `button "标题" of window 1` | 快 | System Events 内部匹配 |
| `every button of window 1` + 本地循环 | 中 | 一次取回列表，比逐个查询快 |
| `UI element whose role is "AXButton"` | 慢 | 要遍历该层全部子元素 |
| `entire contents` | **很慢** | ⚠️ 递归展开整棵树，大窗口可能几万个节点、几十秒 |
| `attribute "AXxxx"` | 慢 | 比原生属性多一层封装 |

优化要点：

```applescript
-- ❌ 慢：循环里每次都发一个 Apple Event
repeat with i from 1 to 50
	tell application "System Events" to get title of button i of window 1
end repeat

-- ✅ 快：一次取回整个列表，之后在本地处理
tell application "System Events"
	set allTitles to title of every button of window 1
end tell
repeat with t in allTitles
	-- 本地处理，无 IPC 开销
end repeat
```
🔵

⚠️ **`tell` 块要包住整个循环，而不是放在循环体里。**
每次跨进 `tell application "System Events"` 都有会话开销，
把 `tell` 提到循环外通常能快数倍。

⚠️ 避免 `entire contents`。真需要全树就用 §10.5.9 第 6 步的 `dumpUI`，
它带 `maxDepth` 限制，可控得多。

## 10.6 什么时候用 System Events，什么时候不用

| 需求 | 推荐 |
| --- | --- |
| 判断文件是否存在 | ❌ **别用** System Events `exists file`：查「不存在」且在 TCC 保护目录会挂死（§9.5）。改用 `do shell script "test -f …"` |
| 读写 plist | ✅ System Events `property list file` |
| 枚举/启动/退出 App | ✅ System Events |
| 复制文件、建文件夹 | ⚠️ 都行，但 `do shell script` 的 `cp`/`mkdir` 更快更可控 |
| 读取 App 内部数据（邮件、日历、网页内容） | ❌ 用 App 自己的字典，别用 UI Scripting |
| App 无字典但需要操作 | ✅ UI Scripting（唯一选择） |
| 定时后台任务里操作 UI | ❌ 无头会话下基本会失败，改用其他方案 |

---

## 10.7 下一步

写 UI 脚本的实际工作流是「**Inspector 看 → 本章翻译 → 轮询等待 → 降级兜底**」。
中间那步「怎么在 Inspector 里看清一个控件」是独立技能，见
`docs/11-用AccessibilityInspector定位UI元素.md`——那里有 Inspector 每个字段
到 AppleScript 写法的逐条对照表。

# 11 用 Accessibility Inspector 定位 UI 元素

`docs/10-SystemEvents与界面自动化.md` 讲了 UI Scripting 的分层模型和写法，
但**没讲怎么知道该写什么**。这一章补上那一环：用 Accessibility Inspector
把屏幕上任意控件的 AX 信息读出来，再翻译成 AppleScript。

> 前置知识：§10.5.1（四层模型）、§10.5.4（role ↔ 类名对照表）、§10.5.5（subrole）。
> 本章所有「Inspector 读数 → 代码」的映射都依赖那三节。

> **验证标记说明**
> - ✅ 实测：本机（macOS 26.6.2 / Xcode 26.6，build 17F113）实际确认。
> - Inspector 的版本、路径、bundle id、菜单项、界面字符串、快捷键，
>   全部从本机 App bundle 的 `Info.plist`、`Localizable.strings`、
>   `MainMenu.nib` 中直接提取，非凭记忆。
> - ⚠️ 本机运行脚本的宿主进程**没有辅助功能权限**，因此涉及 UI 读写的
>   AppleScript 代码标 🔵（`osacompile` 编译通过，未做运行时验证）。

---

## 11.1 它是什么、在哪里、怎么打开

**Accessibility Inspector** 是 Apple 官方的辅助功能检查工具，随 Xcode 一起安装。
它把 §10.5.1 里说的 **L1 层（AX 对象模型）可视化**：鼠标悬停到任何控件上，
就能看到它的 Role、Subrole、Title、Description、Value、Position、Size、
支持的 Actions、以及全部 AXAttributes。

本机实测信息：

| 项 | 值 |
| --- | --- |
| 路径 | `/Applications/Xcode.app/Contents/Applications/Accessibility Inspector.app` |
| Bundle ID | `com.apple.AccessibilityInspector` |
| 版本 | `5.0`（build `187.40`） |
| 最低系统要求 | macOS 14.0（`LSMinimumSystemVersion`） |
| 界面语言 | ⚠️ **只有英文**（Resources 下只有 `Base.lproj` 和 `en.lproj`） |
| 随附工具 | Color Contrast Calculator、Audit、Notifications、Device Settings |

### 三种打开方式

```bash
# ① 直接 open（最快，推荐做成别名）
open "/Applications/Xcode.app/Contents/Applications/Accessibility Inspector.app"

# ② 从 Xcode 菜单：Xcode → Open Developer Tool → Accessibility Inspector

# ③ 用 AppleScript 打开
osascript -e 'tell application "Accessibility Inspector" to activate'
```
✅ 方式 ①③ 实测可用（`ls -d` 确认路径存在）。

⚠️ **必须先装完整版 Xcode**，只有 Command Line Tools 是没有的：

```bash
xcode-select -p          # 应指向 /Applications/Xcode.app/Contents/Developer
xcodebuild -version      # 本机：Xcode 26.6 / Build version 17F113
```

⚠️ `Accessibility Inspector.app` **不在 `/Applications` 根目录下**，而是嵌在
Xcode 包里（本机实测 `ls -d /Applications/*Accessibility*` 无匹配）。
不过 Spotlight 索引能找到它，实测：

```bash
mdfind -name "Accessibility Inspector"
# /Applications/Xcode.app/Contents/Applications/Accessibility Inspector.app
```

想省事可以把它拖到 Dock，或做个别名：

```bash
alias axinsp='open "/Applications/Xcode.app/Contents/Applications/Accessibility Inspector.app"'
```

---

## 11.2 授权：Inspector 自己也要辅助功能权限

⚠️⚠️ 这是新手卡住的第一关。**Inspector 要读别的 App 的 AX 树，
它自己就必须有辅助功能权限。**

- 授权对象：`Accessibility Inspector`（bundle id `com.apple.AccessibilityInspector`）
- 授权路径：**系统设置 → 隐私与安全性 → 辅助功能**
- ⚠️ **授权后必须完全退出 Inspector 再重开**（⌘Q，不是关窗口），否则不生效

没授权时的表现：

| 现象 | 含义 |
| --- | --- |
| Point to Inspect 悬停后什么都不显示 / 显示 `No target` | 没权限，读不到 AX 树 |
| 目标选择器里只有 `All processes` 但列表是空的 | 同上 |
| 只能看到 Inspector 自己的界面元素 | 同上 |

⚠️ 这个权限和 §10.1 里「跑脚本的宿主程序要授权」是**两件独立的事**：

| 谁 | 授权什么 | 干什么用 |
| --- | --- | --- |
| `Accessibility Inspector` | 辅助功能 | 让你能**看**控件信息 |
| 终端 / Script Editor / 你的 `.app` | 辅助功能 | 让脚本能**操作**控件 |
| 终端 / Script Editor | 自动化（Automation） | 让脚本能 `tell application "System Events"` |

⚠️ 给 Inspector 授权**不会**顺带给 osascript 授权。两个都要单独加。

命令行快速检查当前授权状态（读 TCC 用户库，需要「完全磁盘访问」或会失败）：

```bash
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT client, auth_value FROM access WHERE service='kTCCServiceAccessibility';" 2>&1
```

⚠️ 这条命令在多数机器上会因 TCC 保护而失败（`unable to open database file`），
失败是正常的。最可靠的判断方式还是在脚本里跑 `UI elements enabled`（§10.5.9 第 1 步）。

---

## 11.3 界面分区（本机 nib 实测结构）

主窗口工具栏从左到右由三个部件组成（来自 `Base.lproj/AppChrome.nib`）：

| 部件 | 类 | 作用 |
| --- | --- | --- |
| **目标选择器** | `XRTargetChooserToolbarItem` | 选择要检查哪个进程。菜单项含 `All processes`、`Catalyst`，以及当前所有可检查的 App |
| **Point Inspection 开关** | `XRCSegmentsToolbarItem`（tooltip：`Inspection Pointer`） | 开/关「鼠标悬停即检查」。动作 `togglePointInspection:` |
| **模式切换（3 段）** | `XRCSegmentsToolbarItem` | `Inspection` / `Audit` / `Settings` |

三个模式对应的面板（本机 nib 文件名可佐证）：

| 模式 | 面板 | 相关文件 | 用途 |
| --- | --- | --- | --- |
| **Inspection** | Element Inspector | `ElementInspector.nib`、`InspectorView.nib`、`InspectorSection.nib`、`InspectorCellTree.nib`、`InspectorCellText.nib`、`InspectorCellAction.nib`、`InspectorLabelValue.nib`、`InspectorValueList.nib`、`InspectorEditValue.nib`、`InspectorQuicklook.nib` | **写脚本时 99% 的时间都在这里**：看树 + 看属性 + 看动作 |
| **Audit** | Audit Issues | `AuditIssues.nib`、`AuditOptionsPopover.nib`、`AuditTestTypeCheckbox.nib` | 无障碍合规检查，与写自动化脚本关系不大（§11.9） |
| **Settings** | Device Settings | `DeviceSettingSlider.nib`、`DeviceSettingCheckbox.nib`、`DeviceSettingFontSlider.nib`、`Preferences.nib` | 模拟辅助功能设置（§11.10） |

另外还有两个**独立窗口**（不在模式切换里）：

| 窗口 | 打开方式 | 用途 |
| --- | --- | --- |
| **Notifications** | 菜单 `View → Show Notifications` | 实时显示目标 App 发出的 AX 通知（§11.8） |
| **Color Contrast Calculator** | 菜单 `View → Show Color Contrast Calculator` | 颜色对比度计算（`ColorContrast.nib`） |

`Resources/` 里还有 4 个工具栏图标资源：
`TBLR_Magnifier`、`TBLR_Control`、`TBLR_Check`、`TBLR_Warnings`（各有 selected/unselected 两态）。

### Inspection 面板的内部结构

开启 Point to Inspect 并悬停到某个控件后，Inspection 面板分成几块：

| 区块 | 内容 | 对应 §10.5 的层 |
| --- | --- | --- |
| **顶部标题行** | 元素名 + `Role`（如 `AXButton`） | L1 role → L2 类名（§10.5.4） |
| **Hierarchy（层级树）** | 从 `AXApplication` 到当前元素的完整路径，可展开兄弟节点 | 拼 `of` 链的依据（§11.7） |
| **属性区** | Role / Subrole / Title / Description / Value / Label / Identifier / Position / Size / Enabled / Focused … | L1 attribute（§10.5.6） |
| **Actions 区** | 该元素支持的 `AXPress`、`AXShowMenu` 等 | `perform action`（§11.6） |
| **Traits 区** | 元素的 trait 标记 | — |

面板上还有几个小按钮（本机字符串实测）：

| 按钮 | tooltip 原文 | 作用 |
| --- | --- | --- |
| 编辑 | `Edit the value` | **直接改控件的值**，等价于 `set value of … to …` |
| 定位 | `Change focus to the associated element` | 把系统焦点移到该元素 |
| 预览 | `See a preview of the list` | Quick Look 预览 |
| `go to element` | — | 跳到树中对应节点 |

⚠️ `Edit the value` 会**真的修改目标 App 的状态**。调试时小心别改坏数据。

### Point to Inspect 的两个附加开关

本机字符串实测：

| 开关 | 原文 | 含义 |
| --- | --- | --- |
| 悬停模式 | `Start inspection follows point` / `Stop inspection follows point` | 开启后鼠标移到哪就检查哪；关闭则冻结在当前元素 |
| 触发时机 | `Inspect on all actions` | 每次鼠标移动都刷新 |
| 触发时机 | `Inspect on next action only` | **只检查下一个动作**，然后自动冻结。抓「一闪而过」的弹窗必用 |

⚠️⚠️ **抓转瞬即逝的弹窗（tooltip、右键菜单、下拉菜单）时，
一定要切到 `Inspect on next action only`。** 否则菜单一移开就没了。

---

## 11.4 Point to Inspect 实操：抓一个控件的完整流程

以「找到 Safari 工具栏的重新载入按钮」为例，标准 8 步：

1. **打开 Inspector 并确认已授权**（§11.2）。没授权的话后面全是空的。
2. **在目标选择器里选中目标 App**（如 `Safari`）。
   - 选具体进程比 `All processes` 快得多，树也干净。
   - ⚠️ 找不到目标 App？它可能没在运行，或者它本身不暴露 AX 树（极少数）。
3. **打开 Point to Inspect**（工具栏 `Inspection Pointer` 按钮，
   或菜单 `Inspection → Enable Point to Inspect`）。
4. **把鼠标移到目标控件上**，Inspector 会实时显示。
   - ⚠️ 鼠标经过 Inspector 自己的窗口时，抓到的是 Inspector 自己。
   - 建议开 `Window → Always on Top`，这样不用来回切窗口。
5. **抄下 Role 和 Subrole**。查 §10.5.4 的表把 Role 翻译成 System Events 类名。
6. **抄下 Title / Description / Value / Identifier**，按 §10.5.8 的可靠性排序选锚点。
   - `Identifier` 有值 → 直接用，收工。
   - 没值 → 用 Title，但要考虑本地化。
7. **看 Hierarchy 面板**，从当前元素往上抄路径，拼成 `of` 链（§11.7）。
8. **关掉 Point to Inspect，回 Script Editor 写代码**，用 `osacompile`（⌘K）验证。

⚠️ 抓**菜单**的正确姿势：菜单一弹出鼠标就不能乱动。

- 先切到 `Inspect on next action only`；
- 或者用键盘导航：菜单打开后按 `⌃⌘→` / `⌃⌘←` 在元素间移动（§11.11），
  这样不用碰鼠标，菜单不会关。

⚠️ 抓**右键上下文菜单**：先右键弹出菜单，再开 Point to Inspect，
或者用 `Inspect on next action only` 然后右键。

---

## 11.5 Inspector 字段 → AppleScript 写法对照表（核心）

这张表是本章的重点。**左边是你在 Inspector 里看到的，右边是你该写的代码。**

| Inspector 字段 | 示例值 | AppleScript 写法 | 说明 |
| --- | --- | --- | --- |
| **Role** | `AXButton` | 类名 `button`（查 §10.5.4） | 决定用哪个 System Events 类 |
| **Role**（无对应类时） | `AXCell` | `UI element whose role is "AXCell"` | §10.5.4 标 ❌ 的 17 个 role |
| **Subrole** | `AXCloseButton` | `subrole of e` | 区分同类控件（§10.5.5） |
| **Title** | `重新载入` | `title of e` / `button "重新载入"` | ⚠️ 本地化敏感 |
| **Description** | `重新载入当前页面` | `description of e` / `button whose description is "…"` | 通常比 title 稳定，仍可能本地化 |
| **Label** | — | `description of e`（AX 的 Label 映射到 Description） | Web/ARIA 元素常见 |
| **Value** | `https://…` | `value of e` | ⚠️ 类型随控件而变（§10.5.3） |
| **Identifier** | `com.apple.Safari.reload` | `value of attribute "AXIdentifier" of e` | ⭐ **最可靠的锚点**，但很多 App 没设 |
| **Position** | `{120, 45}` | `position of e` | 全局坐标，左上原点（§10.5.11） |
| **Size** | `{28, 24}` | `size of e` | `{宽, 高}` |
| **Enabled** | `True` | `enabled of e` | ⚠️ 只读 |
| **Focused** | `False` | `focused of e` | 可写：`set focused of e to true` |
| **Selected** | `False` | `selected of e` | 可写 |
| **Role Description** | `按钮` | `role description of e` | 本地化的 role 名 |
| **Help** | `重新载入页面` | `help of e` | tooltip 文本 |
| **Modal** | `true` | `value of attribute "AXModal" of e` | ⚠️ 不在 19 个原生属性里 |
| **Parent** | `AXGroup` | `value of attribute "AXParent" of e` | 手动上溯 |
| **Children** | 列表 | `value of attribute "AXChildren" of e` | 或直接用 `UI elements of e` |
| **Placeholder Value** | `搜索` | `value of attribute "AXPlaceholderValue" of e` | 辨认输入框用途 |
| **Class**（`Show Element Class Name` 开启后） | `NSButton` | — | ⚠️ **ObjC 类名，AppleScript 用不上**，仅供开发 App 的人参考 |

### ⚠️ 三个最容易搞错的映射

**① Inspector 显示的是 L1 名字，代码要用 L2 名字。**

```
Inspector:  Role = AXPopUpButton      →  代码: pop up button
Inspector:  Role = AXStaticText       →  代码: static text
Inspector:  Role = AXSplitGroup       →  代码: splitter group    ← 注意不是 "split group"
Inspector:  Role = AXPopover          →  代码: pop over          ← 注意不是 "popover"
```

**② Inspector 里有的字段，System Events 没有原生属性。**
`Identifier`、`Modal`、`PlaceholderValue`、`DefaultButton`、`CancelButton` 等
必须走 `attribute "AXxxx" of …`（§10.5.6）。

**③ Inspector 的 `Class` 字段和 AppleScript 的 `class` 属性是两回事。**

```applescript
-- Inspector 显示 Class = NSButton（ObjC 类，写脚本没用）
-- AppleScript 的 class 返回的是 System Events 的类：
tell application "System Events" to tell process "Safari"
	get class of button 1 of toolbar 1 of window 1   --> button
end tell
```
🔵

---

## 11.6 Actions 面板 → `perform action`

Inspector 的 Actions 区列出该元素**实际支持**的动作（对应 `InspectorCellAction.nib`）。
这比查文档准，因为每个控件支持的动作都不一样。

| Inspector 里看到 | AppleScript 写法 |
| --- | --- |
| `AXPress` | `click e` 或 `perform action "AXPress" of e` |
| `AXShowMenu` | `perform action "AXShowMenu" of e` |
| `AXRaise` | `perform action "AXRaise" of e`（把窗口提到前面） |
| `AXPick` | `pick e`（⚠️ Hidden Suite 命令）或 `perform action "AXPick" of e` |
| `AXConfirm` / `AXCancel` | `confirm e` / `cancel e`（⚠️ Hidden Suite） |
| `AXIncrement` / `AXDecrement` | `increment e` / `decrement e`（⚠️ Hidden Suite） |
| `AXAccept` | `perform action "AXAccept" of e`（没有对应的 System Events 命令） |
| `AXShowAlternateUI` / `AXShowDefaultUI` | 只能用 `perform action` |

```applescript
tell application "System Events" to tell process "Safari"
	set b to button 1 of toolbar 1 of window 1

	-- 1) 先看它支持哪些动作
	get name of every action of b          --> {"AXPress", "AXShowMenu"}
	get description of action "AXPress" of b

	-- 2) 执行
	perform action "AXPress" of b
end tell
```
🔵

⚠️⚠️ **`click` 和 `perform action "AXPress"` 不完全等价。**
`click` 是 System Events 合成一次鼠标事件；`AXPress` 是直接让控件执行它的动作。
有些控件（尤其是自绘控件、Web 元素）`click` 无效但 `AXPress` 有效，反之也有。
**一个不行就换另一个**，这是 §10.5.9 第 7 步降级顺序里的第 3 档。

⚠️ Actions 区是空的？说明该元素不支持任何动作，
你只能靠 `set value`、`set focused`、`keystroke` 或坐标点击。

---

## 11.7 Hierarchy 面板 → 拼出 `of` 链

Hierarchy 显示从 `AXApplication` 一路到当前元素的完整路径。
**翻译规则：从下往上读，每层之间插入 `of`。**

Inspector 里看到：

```
AXApplication "Safari"
└─ AXWindow "Apple"
   └─ AXToolbar
      └─ AXGroup
         └─ AXButton "重新载入"      ← 当前选中
```

翻译成代码（**从最里层往外写**）：

```applescript
tell application "System Events" to tell process "Safari"
	click button "重新载入" of group 1 of toolbar 1 of window 1
end tell
```
🔵

三条实用规则：

1. **索引可以省略**：`window 1` 在只有一个窗口时可写成 `window`，
   但**建议始终写索引**，多窗口时不会出错。
2. **`AXApplication` 那一层不写进路径**，它就是 `process "Safari"` 本身。
3. **中间的 `AXGroup` 常常可以跳过**。System Events 允许
   `button "重新载入" of toolbar 1 of window 1` 这种「隔层引用」——
   它会向下搜索。⚠️ 但这有歧义风险（多个同名按钮时会取到错的那个），
   **生产代码建议写完整路径**。

⚠️ Hierarchy 里的层数可能很深（十几层）。逐层写死路径很脆。
折中方案：**只写关键的 2~3 层 + 用 title/identifier 定位**：

```applescript
tell application "System Events" to tell process "Safari"
	-- ❌ 不稳：路径太长，App 改版就废
	click button 3 of group 2 of group 1 of toolbar 1 of splitter group 1 of window 1

	-- ✅ 稳：短路径 + 语义锚点
	click (first button of toolbar 1 of window 1 whose title is "重新载入")
end tell
```
🔵

---

## 11.8 Notifications 面板：看 App 到底发了什么事件

菜单 `View → Show Notifications` 打开独立窗口（`Notification.nib`），
实时滚动显示目标 App 发出的 AX 通知（§10.5.2 的那 37 种）。

⚠️⚠️ **这个面板的价值是「理解」，不是「抄代码」。**
AppleScript **收不到**这些通知，只能轮询（§10.5.12）。
但它能告诉你：

| 你观察到 | 说明 | 脚本该怎么写 |
| --- | --- | --- |
| 点击后立刻冒出 `AXValueChanged` | 值确实变了 | 可以轮询 `value` 判断完成 |
| 点击后冒出 `AXWindowCreated` | 弹了新窗口 | 轮询 `count of windows` |
| 点击后冒出 `AXSheetCreated` | 弹了 sheet | 轮询 `count of sheets of window 1` |
| 点击后**什么都没发** | 你的点击根本没生效 | 换 `perform action "AXPress"` 或坐标点击 |
| 冒出 `AXLayoutChanged` 一串 | 界面在重排 | 等它停了再读，别在动画中途取值 |

⚠️ 最后一行尤其有用：**「点击后没有任何通知」是判断
`click` 是否真的生效的最快方法**，比反复试代码高效得多。

---

## 11.9 Audit：无障碍合规检查

切到工具栏的 `Audit` 段，可以自动扫描目标 App 的无障碍问题。

本机实测的相关字符串：

| UI 元素 | 原文 |
| --- | --- |
| 运行按钮 | `Run Audit` |
| 运行中 | `Auditing...` |
| 结果分组 | `Group by Audit`、表头 `Audit %@` |
| 保存报告 | `Save Audit Report As...` |
| 清空 | 菜单 `Inspection → Clear All Audit Warnings`，确认框标题 `Clear results?`，正文 `Target application changed.` |
| 未选目标 | `Select a target App to view accessibility warnings and audit information.` |
| 连接中 | `Connecting to target...` |
| 修复建议 | 每条问题下方 `Fix Suggestion: ` |

检查项可以勾选（`AuditTestTypeCheckbox.nib`），
本机二进制里的属性名是 `activelyCheckedAuditTypes` / `allSupportedAuditTypes` /
`auditTypesSupportedByDevice` —— 说明**可选的检查类型取决于目标设备**。

⚠️ **Audit 是给 App 开发者做无障碍合规用的，对写自动化脚本帮助不大。**
它报告的是「这个控件缺 label」这类问题，不是「你该怎么点它」。
写脚本时你只需要 `Inspection` 模式。

---

## 11.10 Settings 模式与 Color Contrast Calculator

### Settings（`DeviceSetting*.nib`）

模拟各种辅助功能设置，看 App 在这些设置下的表现。
本机 `Localizable.strings` 里实测到的开关项：

| 设置 | 原文 key |
| --- | --- |
| 粗体文本 | `deviceSetting.BOLD_FONTS` → `Bold text` |
| 按钮形状 | `deviceSetting.BUTTON_SHAPES` → `Button shapes` |
| 不用颜色区分 | `deviceSetting.DIFFERENTIATE_WITHOUT_COLOR` |
| 动态字体 | `deviceSetting.DYNAMIC_TYPE` → `Dynamic Type` |
| 字幕 | `deviceSetting.ENABLE_CAPTIONS` → `Enable captions` |
| 灰度 | `deviceSetting.GRAYSCALE` → `Grayscale` |
| 增强对比度 | `deviceSetting.INCREASE_CONTRAST` |
| 反转颜色 | `deviceSetting.INVERT_COLORS` |
| 全键盘控制 | `deviceSetting.KEYBOARD_ACCESS` → `Full Keyboard Access` |
| 开/关标签 | `deviceSetting.ON_OFF_LABELS` → `On/Off labels` |
| 减弱动态效果 | `deviceSetting.REDUCE_MOTION` |
| 降低透明度 | `deviceSetting.REDUCE_TRANSPARENCY` |

⚠️ 其中 **`Bold text`、`Button shapes`、`On/Off labels`、`Increase contrast`**
会**改变控件的实际外观和 AX 描述**。如果你在开着这些设置时抓控件特征，
关掉后 title / description 可能就变了。**抓特征前先确认这些设置是关的**，
否则脚本会莫名其妙失效。

### Color Contrast Calculator（`ColorContrast.nib`）

菜单 `View → Show Color Contrast Calculator`。本机实测到的输出文案：

| 结果 | 原文 |
| --- | --- |
| 全部通过 | `Passes for any text size` |
| 部分通过 | `Passes %dpt Regular and %dpt Bold` |
| 全部失败 | `Fails for all text sizes.` |
| 建议 | `Try text color %@` / `Try background color %@` |

⚠️ 与自动化脚本无关，做 UI 设计时才用。

---

## 11.11 Inspection 菜单与快捷键

菜单项来自本机 `MainMenu.nib` 实测提取。写 UI 脚本时最常用的是 `Inspection` 菜单。

### `Inspection` 菜单（核心）

| 菜单项 | 作用 | 什么时候用 |
| --- | --- | --- |
| `Enable Point to Inspect` | 开/关悬停检查 | 抓控件 |
| `Move to Next Item` | 移到导航顺序的下一个元素 | **不用鼠标遍历界面**，抓菜单/弹窗必备 |
| `Move to Previous Item` | 上一个元素 | 同上 |
| `Move to Parent Item` | 上溯到父元素 | 找容器，确定 `of` 链 |
| `Move to Child Item` | 下钻到第一个子元素 | 展开容器看里面有什么 |
| `Refresh` | 重新读取当前元素的 AX 数据 | 界面变了但面板没更新 |
| `Show Element Class Name` / `Hide Element Class Name` | 显示/隐藏 ObjC 类名 | ⚠️ 写脚本时用不上（§11.5） |
| `Show Ignored Elements` / `Hide Ignored Elements` | 显示被 AX 忽略的元素 | 树里出现 `<ignored>` 时打开它 |
| `Enable Auto-Interact into Elements` / `Disable Auto-Interact into Elements` | 是否自动钻入元素内部 | 树太深时关掉 |
| `Run Audit` | 运行合规检查 | §11.9 |
| `Clear All Audit Warnings` | 清空检查结果 | §11.9 |
| `Show Internal Attributes` / `Hide Internal Attributes` | 显示内部属性 | 调试用，属性列表会变很长 |

### `View` / `Window` / `Help` 菜单

| 菜单 | 有用项 |
| --- | --- |
| `View` | `Show Color Contrast Calculator`、`Show Notifications`、`Show Main Window`、`Show Toolbar`、`Customize Toolbar`、`Group by Screen` |
| `Window` | `Always on Top`（⭐ 强烈推荐打开）、`Bring All to Front` |
| `Help` | `Accessibility Inspector Help`、`Report to Radar` |

### 快捷键

本机 tooltip 原文实测：

| 快捷键 | 功能 | 原文说明 |
| --- | --- | --- |
| `⌃⌘→` | 下一个元素 | `Go to the next element in navigation order. Keyboard shortcut is ⌃⌘→. Long press or ctrl+click to jump to first element.` |
| `⌃⌘←` | 上一个元素 | `Go to the previous element in navigation order. Keyboard shortcut is ⌃⌘←. Long press or ctrl+click to jump to last element.` |
| 长按 / `⌃`+点击 Next | 跳到第一个元素 | `Jump to the first element` |
| 长按 / `⌃`+点击 Previous | 跳到最后一个元素 | `Jump to last element` |

⚠️⚠️ **`⌃⌘→` / `⌃⌘←` 是本章最实用的两个快捷键。**
它们按**导航顺序**遍历元素，完全不用碰鼠标，因此：

- 菜单不会因为你移动鼠标而关闭；
- 可以稳定地一个个走过工具栏、侧边栏、表格里的所有控件；
- 配合 Hierarchy 面板能完整摸清一个窗口的结构。

---

## 11.12 完整实例：从 Inspector 读数到可运行脚本

把前面所有东西串起来。目标：**点击 TextEdit 工具栏里的某个按钮**。

### 第 1 步：Inspector 读数

悬停后记下（示例数据）：

```
Role:            AXButton
Subrole:         AXToolbarButton
Title:           粗体
Description:     粗体
Identifier:      （空）        ← 没设，用不了最稳的锚点
Position:        {204, 60}
Size:            {32, 24}
Enabled:         True
Actions:         AXPress
Hierarchy:       AXApplication "TextEdit"
                   └─ AXWindow "未命名"
                      └─ AXToolbar
                         └─ AXButton "粗体"
```

### 第 2 步：翻译成代码

按 §11.5 的表和 §11.7 的路径规则：

```applescript
-- 主方案：短路径 + title
tell application "TextEdit" to activate
delay 0.5
tell application "System Events" to tell process "TextEdit"
	set b to (first button of toolbar 1 of window 1 whose title is "粗体")
	if exists b and (enabled of b) then
		perform action "AXPress" of b
	end if
end tell
```
🔵

### 第 3 步：加本地化与降级

`Identifier` 是空的，`Title` 又本地化敏感，所以按 §10.5.8 加候选表和降级：

```applescript
on clickToolbarButton(procName, titleCandidates, fallbackKeystroke, fallbackMods)
	tell application "System Events" to tell process procName
		repeat with t in titleCandidates
			try
				set b to (first button of toolbar 1 of window 1 whose title is t)
				if exists b and (enabled of b) then
					perform action "AXPress" of b
					delay 0.4
					return "pressed:" & t
				end if
			end try
		end repeat
	end tell
	-- 降级 1：菜单
	-- 降级 2：快捷键
	tell application "System Events"
		keystroke fallbackKeystroke using fallbackMods
		delay 0.4
	end tell
	return "fallback:keystroke"
end clickToolbarButton

clickToolbarButton("TextEdit", {"粗体", "Bold"}, "b", {command down})
```
🔵

### 第 4 步：验证

```bash
# 只验证语法，不执行
osacompile -o /tmp/check.scpt 你的脚本.applescript

# 确认权限（返回 false 就别试了，先去授权）
osascript -e 'tell application "System Events" to UI elements enabled'
```
✅ 第二条实测可运行（本机返回 `false`）。

### 这个流程的通用模板

任何 UI 自动化任务都可以套这四步：

| 步骤 | 做什么 | 关键工具 |
| --- | --- | --- |
| 1 | Inspector 读 Role/Subrole/Title/Identifier/Hierarchy | 本章 §11.4~§11.7 |
| 2 | 查表翻译成 System Events 代码 | §10.5.4、§11.5 |
| 3 | 加 `exists` 检查、本地化候选、降级路径、轮询等待 | §10.5.8、§10.5.9、§10.5.12 |
| 4 | `osacompile` 验语法 → `UI elements enabled` 验权限 → 实跑 | 本节 |

---

## 11.13 没有 Xcode 怎么办

Xcode 有十几 GB，很多人不想装。三个替代方案：

### 方案 A：纯 AppleScript 的「文字版 Inspector」（推荐）

下面这个脚本能输出和 Inspector 几乎等价的信息，不需要 Xcode，
只需要跑脚本的宿主有辅助功能权限：

```applescript
-- 打印一个 UI 元素的完整「身份证」，等价于 Inspector 的属性面板
on inspectElement(theElement)
	set out to ""
	tell application "System Events"
		try
			set out to out & "Role:        " & (role of theElement) & linefeed
		end try
		try
			set out to out & "Subrole:     " & (subrole of theElement) & linefeed
		end try
		try
			set out to out & "Title:       " & (title of theElement) & linefeed
		end try
		try
			set out to out & "Description: " & (description of theElement) & linefeed
		end try
		try
			set out to out & "Value:       " & ((value of theElement) as text) & linefeed
		end try
		try
			set out to out & "Enabled:     " & ((enabled of theElement) as text) & linefeed
		end try
		try
			set out to out & "Position:    " & ((position of theElement) as text) & linefeed
			set out to out & "Size:        " & ((size of theElement) as text) & linefeed
		end try
		try
			set out to out & "Identifier:  " & ¬
				(value of attribute "AXIdentifier" of theElement) & linefeed
		end try
		try
			set out to out & "Actions:     " & ¬
				((name of every action of theElement) as text) & linefeed
		end try
		try
			set out to out & "Attributes:  " & ¬
				((name of every attribute of theElement) as text) & linefeed
		end try
		try
			set out to out & "Children:    " & ¬
				((count of UI elements of theElement) as text) & linefeed
		end try
	end tell
	return out
end inspectElement

tell application "System Events" to tell process "TextEdit"
	log my inspectElement(window 1)
	log "-----"
	-- 逐层看子元素
	repeat with e in (UI elements of window 1)
		log my inspectElement(e)
	end repeat
end tell
```
🔵

要点：

- 每个属性单独 `try`：不同控件支持的属性不同（§10.5.6）。
- `Attributes:` 那一行列出该元素**全部可用**的 AX 属性名，
  等价于 Inspector 开了 `Show Internal Attributes` 之后的效果。
- 配合 §10.5.9 第 6 步的 `dumpUI` 可以导出整棵树。

### 方案 B：第三方工具

| 工具 | 说明 |
| --- | --- |
| **UI Browser**（Prefab） | 老牌商业 UI 树浏览器，功能类似 Inspector |
| **Script Debugger**（Late Night Software） | AppleScript IDE，带 UI 元素浏览器，调试能力远超 Script Editor |
| **cliclick**（`brew install cliclick`） | 命令行鼠标键盘工具，补足 AppleScript 缺失的拖拽/滚轮（§10.5.11） |

### 方案 C：Python + pyobjc（能收到 AX 通知）

如果确实需要**事件驱动**而不是轮询（§10.5.2 的 Notification 限制），
用 Python：

```bash
pip3 install pyobjc-framework-ApplicationServices
```

`AXObserverCreate` + `AXObserverAddNotification` 可以注册
`kAXWindowCreatedNotification` 等回调。这超出了 AppleScript 的能力范围，
但在需要「秒级响应的界面监听」时是唯一选择。

---

## 11.14 常见坑

| 坑 | 现象 | 解法 |
| --- | --- | --- |
| **Inspector 没授权** | Point to Inspect 什么都不显示、`No target` | §11.2，授权后 ⌘Q 重开 |
| **脚本宿主没授权** | Inspector 能看到，脚本跑报 `-25211`/`-1719`/`-1728` | 给终端/Script Editor 单独授权（§10.1） |
| **抓的是 Inspector 自己** | 树顶显示 `AXApplication "Accessibility Inspector"` | 开 `Window → Always on Top` |
| **菜单一碰鼠标就关** | 抓不到菜单项 | 用 `Inspect on next action only`，或用 `⌃⌘→` 遍历 |
| **`Identifier` 是空的** | 找不到稳定锚点 | 退回 title/description + 本地化候选表（§10.5.8） |
| **Class 显示 `NSButton` 就照着写** | `NSButton` 在 AppleScript 里不存在 | 用 Role 查 §10.5.4 的表（§11.5） |
| **Role 没有对应类** | `AXCell` 写 `cell 1` 编译失败 | 用 `UI element whose role is "AXCell"`（§10.5.4） |
| **`whose` 语序错** | 编译报 `-1723 Access not allowed` | `whose` 必须放在 `of` 链最后（§10.5.4） |
| **开了 Display 设置后抓特征** | 脚本时灵时不灵 | 关掉 `Bold text`/`Button shapes` 等再抓（§11.10） |
| **树里出现 `<ignored>`** | 元素被 AX 忽略 | 菜单开 `Show Ignored Elements`；这类元素通常点不动 |
| **`click` 没反应也不报错** | 静默失败 | 开 Notifications 面板看有没有事件发出（§11.8），换 `AXPress` |
| **多显示器坐标错乱** | 坐标点击点到别的屏幕 | 全局坐标以主屏左上为原点；副屏可能是负值（§10.5.11） |
| **Inspector 卡在 `Connecting to target...`** | 目标 App 无响应或未暴露 AX | 换个进程；确认 App 真的在前台运行 |

---

## 11.15 一句话总结

**Inspector 负责告诉你「L1 层长什么样」，§10.5.4 / §11.5 的对照表负责翻译成
「L2 层怎么写」，剩下的可靠性靠 `exists` + 轮询 + 降级兜底。**

三者缺一不可：只看不写会卡在术语翻译，只写不看会一直在猜控件名。

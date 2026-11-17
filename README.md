# AppleScript 使用说明书

面向 macOS 自动化脚本编写的 AppleScript 参考手册。
所有代码示例均在 **macOS 26.6.2 / AppleScript 2.x / Xcode 26.6** 上验证，实测中发现的坑都单独标注了 ⚠️。

验证标记：**✅ 实测通过**（本机实际运行）／**🔵 语法校验通过**（`osacompile` 编译通过，
但因运行环境未授予辅助功能权限，UI Scripting 部分未做运行时验证）。

⚠️ 代码块围栏上还可能带标记：```` ```applescript ❌ ```` 是**故意的错误示范**（照抄一定编译不过），
```` ```applescript … ```` 是语法片段。含义详见「仓库工具与自检」一节。

---

## 这份说明书怎么用

- **完全没接触过 AppleScript** → 先读 `docs/01-环境与运行方式.md`，再按顺序读 02~06。
- **看不懂某个 App 的字典 / Library** → `docs/08-读懂脚本字典与Suite语法.md`，那里把
  Suite 的排版符号逐条拆开，并给出「字典条目 → 代码」的固定翻译公式。
- **要写具体自动化脚本** → 直接查 `docs/14-常用App自动化.md` 和 `examples/`。
- **目标 App 没有脚本字典，只能点界面** → 按顺序读
  `docs/10-SystemEvents与界面自动化.md`（分层模型 + 定位流程 + 弹窗）
  → `docs/11-用AccessibilityInspector定位UI元素.md`（怎么看清一个控件）。
- **脚本报错了** → 查 `docs/16-常见坑与排错.md`，那里汇总了实测踩到的全部陷阱。
- **想快速回忆语法** → 只看 `docs/速查表.md`。

---

## 目录

| 章节 | 内容 |
| --- | --- |
| [01 环境与运行方式](docs/01-环境与运行方式.md) | `osascript`、Script Editor、`.scpt`/`.applet`、命令行调用 |
| [02 语言核心](docs/02-语言核心.md) | 变量、数据类型、运算符、类型转换、作用域 |
| [03 列表、记录与文本处理](docs/03-列表-记录与文本处理.md) | list/record、引用语义、`text item delimiters`、字符串操作 |
| [04 日期、时间与数字](docs/04-日期时间与数字.md) | date 运算、格式化、Unix 时间戳、数值处理 |
| [05 控制流与函数](docs/05-控制流与函数.md) | `repeat`、`if`、handler、参数标签、script 对象 |
| [06 错误处理与调试](docs/06-错误处理与调试.md) | `try`/`on error`、错误码、`log`、调试技巧 |
| [07 应用控制模型](docs/07-应用控制模型.md) | `tell`、Apple Events、术语解析、查字典、`sdef` |
| [08 读懂脚本字典：Suite、术语与 sdef](docs/08-读懂脚本字典与Suite语法.md) | 字典/Library 怎么读、`v`/`n`/`r/o`/方括号、sdef XML、从字典反推句子 |
| [09 Finder 与文件读写](docs/09-Finder与文件读写.md) | 路径三态、文件 I/O、Finder 增删改查 |
| [10 System Events 与界面自动化](docs/10-SystemEvents与界面自动化.md) | 四层模型、AXRole↔类名对照、动态定位七步法、模态弹窗与系统通知定位 |
| [11 用 Accessibility Inspector 定位 UI 元素](docs/11-用AccessibilityInspector定位UI元素.md) | Inspector 界面分区、Point to Inspect、字段→AppleScript 对照表 |
| [12 Shell 互操作](docs/12-Shell互操作.md) | `do shell script`、引号转义、管理员权限、双向调用 |
| [13 对话框与通知](docs/13-对话框与通知.md) | `display dialog`、`choose file`、通知、非阻塞技巧 |
| [14 常用 App 自动化](docs/14-常用App自动化.md) | Safari、Mail、Calendar、Reminders、Notes、Music、Terminal |
| [15 打包、定时任务与权限](docs/15-打包-定时任务与权限.md) | `osacompile`、stay-open applet、`launchd`、TCC 权限 |
| [16 常见坑与排错](docs/16-常见坑与排错.md) | ⚠️ 实测陷阱汇总、错误码对照、排错流程 |
| [速查表](docs/速查表.md) | 一页纸语法速查 |

---

## 五分钟上手

### 1. 跑第一条脚本

打开「终端」，输入：

```bash
osascript -e 'return "Hello, AppleScript"'
```

输出 `Hello, AppleScript`。这就是最小的 AppleScript 运行环境。

### 2. 弹一个对话框

```bash
osascript -e 'display dialog "你好" buttons {"好"} default button 1 with title "测试"'
```

### 3. 用 Script Editor 写脚本

打开 `脚本编辑器`（Script Editor，位于 `/System/Applications/Utilities/`）：

- 按 **⌘K** 编译（检查语法）
- 按 **⌘R** 运行
- 菜单栏 **文件 → 打开字典**（⇧⌘O）可以查看任意 App 支持哪些命令

### 4. 理解 AppleScript 的心智模型

AppleScript 不是「命令行脚本语言」，而是**用英语句式给 App 发消息**的语言。

```applescript
tell application "Finder"
    set n to count of (every file of folder "Macintosh HD:Users:taylor:Desktop:")
end tell
```

读作：「告诉 Finder：数一数那个文件夹里的所有文件」。
每个 App 有自己的「词汇表」（术语字典），`tell` 块里用的是**那个 App 的词**，不是 AppleScript 自己的词。
这是初学者最大的困惑来源，`docs/07-应用控制模型.md` 会详细讲。

---

## 三条最重要的提醒

1. **⚠️ `use framework` 会顶掉标准命令。**
   一旦写了 `use framework "Foundation"`，`current date`、`do shell script`、`display dialog` 全部会编译失败。
   必须紧跟一行 `use scripting additions` 把它们找回来。详见 `docs/16-常见坑与排错.md`。

2. **⚠️ 权限是自动化的头号障碍。**
   控制别的 App 需要「自动化」权限，模拟点击需要「辅助功能」权限，读写某些目录需要「文件与文件夹」权限。
   脚本「莫名其妙报错 -1743 / -25211」几乎全是权限问题。详见 `docs/15-打包-定时任务与权限.md`。

3. **⚠️ AppleScript 索引从 1 开始，`set` 是共享引用不是拷贝。**
   `set b to a` 之后再改 `b`，`a` 也会变。要独立副本必须用 `copy a to b`。

---

## examples/ 目录

可直接运行的完整示例：

```bash
cd examples
./run-all.sh          # 逐个运行安全示例（只读 / dry-run / 临时目录，不改用户数据）
./run-all.sh --fast   # 跳过需要 Safari 自动化授权的 04
./run-all.sh 03 07    # 只跑指定编号
osascript 01-hello.applescript
```

| 文件 | 说明 |
| --- | --- |
| `01-hello.applescript` | 基础语法演示 + 命令行参数 |
| `02-text-utils.applescript` | 字符串/列表工具函数库（可复用） |
| `03-batch-rename.applescript` | 批量重命名 Finder 文件（带 dry-run） |
| `04-safari-tabs-export.applescript` | 导出 Safari 所有标签页为 Markdown |
| `05-daily-backup.applescript` | 定时备份文件夹 + 保留最近 N 份 |
| `06-clipboard-history.applescript` | 剪贴板文本清洗 + 通知 |
| `07-shell-bridge.applescript` | Shell 互操作封装（含转义与错误处理） |
| `08-calendar-batch.applescript` | 从文本批量创建日历事件 |
| `08-calendar-batch.sample.txt` | 08 的输入样例（`--dry-run` 可直接解析） |
| `lib/stdlib.applescript` | 通用工具库，用 `load script` 引入 |

验证状态：01–07 与 08 的 `--dry-run` 路径均为 ✅ 本机实测通过；
08 真正写入 Calendar 的分支只做了 🔵 语法校验——首次运行会弹「想要控制 Calendar」授权框，
无人值守时会一直卡住，需要先在系统设置里授权，详见 `docs/15-打包-定时任务与权限.md` §15.4。

⚠️ `lib/stdlib.applescript` 是纯文本，`load script` 直接加载它会报 -1752；
要先编译成 `.scpt` 再加载（仓库里已附带编译好的 `lib/stdlib.scpt`），
详见 `docs/16-常见坑与排错.md` §16.2⑱。

---

## 仓库工具与自检

| 工具 | 用途 |
| --- | --- |
| `tools/check-code-blocks.py` | 把 `docs/*.md` 里的 AppleScript 代码块全部抓出来，用 `osacompile` 逐个编译。**只做语法校验，不运行脚本**，因此不会弹窗、不会碰 System Events |
| `tools/sdef2txt.py` | 把 `sdef` 的 XML 转成 Script Editor 字典窗口那样的纯文本，方便 grep（见 `docs/08-读懂脚本字典与Suite语法.md` §8.7） |

```bash
python3 tools/check-code-blocks.py            # 全量复验，最后一行应为「✅ 全部符合预期」
python3 tools/check-code-blocks.py --list     # 顺便列出被跳过 / 预期失败的块
python3 tools/check-code-blocks.py docs/10-*.md   # 只查某一章
```

代码块围栏上的标记（Markdown 渲染时会被忽略，同时给人和脚本看）：

| 围栏写法 | 含义 |
| --- | --- |
| ```` ```applescript ```` | 完整示例，**必须**编译通过 |
| ```` ```applescript ❌ ```` | 错误示范，预期编译失败；哪天它居然能编译了，脚本会提示文档结论过时 |
| ```` ```applescript 🔵 ```` | 本机无法校验（例如目标 App 没装） |
| ```` ```applescript … ```` | 语法片段 / 速查列举，不是完整脚本 |

写作时的基线：**277 个块编译通过、11 个 ❌ 块按预期失败、45 个片段跳过**。
改动文档后跑一次，就能确认没有把示例改坏。

### 提交前自动校验（git 钩子）

`tools/hooks/pre-commit` 是版本化的钩子，提交前只校验**本次暂存**的 `.md` / `.applescript`，
所以通常一两秒就结束（不是每次都跑全量）。

```bash
git config core.hooksPath tools/hooks    # 每个 clone 执行一次（本仓库已配好）
git commit --no-verify                   # 确实需要跳过时
```

钩子会拦下两种情况：

- **❌ 意外编译失败** → 示例被改坏了。
- **标了 ❌ 却能编译** → 「这样写会报错」的结论已经过时，正文要跟着更新。

⚠️ 钩子读的是**工作区**内容而不是索引：如果你用 `git add -p` 只暂存了部分改动，
校验结果可能与真正提交的内容不完全一致。

---

## 参考资料

- 官方语言指南：AppleScript Language Guide（Apple Books / developer.apple.com）
- 标准附加命令：`sdef /System/Library/ScriptingAdditions/StandardAdditions.osax`
- 任意 App 的字典：`sdef /Applications/Safari.app`
- 本机已装的脚本语言：`osalang`

#!/usr/bin/env python3
"""校验手册里所有 AppleScript 代码块能否编译。

只调用 `osacompile` 做**语法编译**，不运行任何脚本，也不会碰 System Events /
Finder 之类的目标 App，因此可以放心反复执行。

用法：
    python3 tools/check-code-blocks.py                # 检查 docs/*.md + examples/*.applescript
    python3 tools/check-code-blocks.py docs/10-*.md   # 只检查指定文件
    python3 tools/check-code-blocks.py --list         # 额外列出被跳过 / 预期失败的块

代码块标记（写在围栏的语言名后面，Markdown 渲染时会忽略）：

    ```applescript ❌     错误示范，**预期编译失败**；若它能编译，说明文档结论过时了
    ```applescript 🔵     本机无法校验（例如目标 App 没安装），跳过
    ```applescript …      语法片段 / 速查列举，不是完整可编译脚本，跳过

没有标记的块一律**预期编译成功**；块内出现 `…` 省略号时也按片段跳过。

退出码：0 = 没有意外情况；1 = 出现「预期成功却编译失败」或「标了 ❌ 却能编译」。
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

BLOCK_RE = re.compile(r"^```applescript([^\n]*)\n(.*?)^```", re.M | re.S)


def find_targets(argv):
    targets = [a for a in argv if not a.startswith("--")]
    if targets:
        return targets
    return sorted(glob.glob("docs/*.md")) + example_files()


def example_files():
    found = sorted(glob.glob("examples/*.applescript"))
    found += sorted(glob.glob("examples/lib/*.applescript"))
    return found


def blocks_of(path):
    """返回 [(围栏所在行号, 标记, 代码文本)]。"""
    text = open(path, encoding="utf-8").read()
    found = []
    for match in BLOCK_RE.finditer(text):
        line_no = text.count("\n", 0, match.start()) + 1
        found.append((line_no, match.group(1).strip(), match.group(2)))
    return found


def compiles(source):
    """用 osacompile 试编译，返回 (是否通过, 首行错误信息)。"""
    with tempfile.NamedTemporaryFile("w", suffix=".applescript", delete=False,
                                     encoding="utf-8") as handle:
        handle.write(source)
        tmp_src = handle.name
    tmp_out = tmp_src + ".scpt"
    try:
        proc = subprocess.run(["osacompile", "-o", tmp_out, tmp_src],
                              capture_output=True, text=True)
        message = (proc.stderr or proc.stdout).strip().split("\n")[0]
        message = re.sub(r"^.*?\.applescript:\d+:\s*(error:\s*)?", "", message)
        return proc.returncode == 0, message
    finally:
        for stale in (tmp_src, tmp_out):
            if os.path.exists(stale):
                os.unlink(stale)


def main():
    argv = sys.argv[1:]
    show_list = "--list" in argv
    unexpected_fail, stale_pass, skipped = [], [], []
    ok = expected_fail = 0

    for path in find_targets(argv):
        if path.endswith(".applescript"):
            items = [(1, "", open(path, encoding="utf-8").read())]
        else:
            items = blocks_of(path)
        for line_no, marker, source in items:
            where = "%s:%d" % (path, line_no)
            first = source.strip().split("\n")[0][:58]
            if "🔵" in marker or "…" in marker or "…" in source:
                skipped.append((where, marker or "…", first))
                continue
            passed, message = compiles(source)
            if "❌" in marker:
                if passed:
                    stale_pass.append((where, first))
                else:
                    expected_fail += 1
                    if show_list:
                        skipped.append((where, "❌ 预期失败", first))
            elif passed:
                ok += 1
            else:
                unexpected_fail.append((where, message[:140], first))

    print("编译通过 %d｜预期失败(❌) %d｜跳过(片段/🔵) %d" % (ok, expected_fail, len(skipped)))
    if show_list:
        for where, why, first in skipped:
            print("   ⊘ %s [%s] %s" % (where, why, first))
    for where, message, first in unexpected_fail:
        print("❌ 意外编译失败 %s\n     %s\n     %s" % (where, first, message))
    for where, first in stale_pass:
        print("⚠️ 标了 ❌ 却能编译，结论可能已过时 %s\n     %s" % (where, first))
    if unexpected_fail or stale_pass:
        print("合计 %d 处需要人工确认" % (len(unexpected_fail) + len(stale_pass)))
        return 1
    print("✅ 全部符合预期")
    return 0


if __name__ == "__main__":
    sys.exit(main())

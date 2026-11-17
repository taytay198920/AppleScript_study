#!/usr/bin/env python3
"""sdef2txt.py —— 把 App 的 sdef 字典转成「一眼能看懂」的文本签名。

用法:
    python3 sdef2txt.py /System/Applications/Notes.app
    python3 sdef2txt.py /System/Applications/Mail.app --suite "Message Suite"
    python3 sdef2txt.py /System/Library/CoreServices/Finder.app --grep window
    python3 sdef2txt.py - < /tmp/some.sdef

输出的格式刻意贴近 Script Editor 字典窗口的排版:
    v   = command(动词)      n = class(名词)
    [ ] = 可选参数           → = 返回值
    r/o = 只读属性
"""
import argparse
import io
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

TYPE_HINT = {
    "text": "text",
    "integer": "int",
    "real": "real",
    "number": "number",
    "boolean": "bool",
    "date": "date",
    "file": "file",
    "alias": "alias",
    "record": "record",
    "list": "list",
    "specifier": "reference",
    "constant": "constant",
    "type class": "type",
    "any": "any",
    "point": "point",
    "rectangle": "rect",
    "location": "location",
}


INCLUDE_RE = re.compile(r'<xi:include[^>]*href="([^"]+)"[^>]*/>')


def resolve_includes(xml_text, depth=0):
    """⚠️ sdef 不会展开 xi:include，Standard Suite 因此常常「看不见」。
    这里手动把 include 的文件内容内联进来。"""
    if depth > 4:
        return xml_text

    def sub(m):
        href = m.group(1)
        href = href.replace("file://localhost", "")
        try:
            inner = io.open(href, encoding="utf-8").read()
        except OSError:
            return ""
        inner = resolve_includes(inner, depth + 1)
        body = re.sub(r"^<\?xml[^>]*\?>\s*", "", inner)
        body = re.sub(r"<!DOCTYPE[^>]*>\s*", "", body)
        body = re.sub(r"^\s*<dictionary[^>]*>", "", body)
        body = re.sub(r"</dictionary>\s*$", "", body)
        return body

    return INCLUDE_RE.sub(sub, xml_text)


def load(target):
    if target == "-":
        raw = sys.stdin.read()
    else:
        out = subprocess.run(["sdef", target], capture_output=True, text=True)
        if out.returncode != 0 or not out.stdout.strip():
            sys.exit("无法获取字典: %s\n%s" % (target, out.stderr.strip() or "(空输出，该 App 可能不可脚本化)"))
        raw = out.stdout
    return resolve_includes(raw)


def types_of(node):
    """一个 parameter/direct-parameter 可以有多个 <type>，表示多态。"""
    names = []
    for t in node.findall("type"):
        base = t.get("type") or "any"
        label = TYPE_HINT.get(base, base)
        if t.get("list") == "yes":
            label = "list of " + label
        names.append(label)
    if not names:
        names = [TYPE_HINT.get(node.get("type"), node.get("type") or "any")]
    return " | ".join(dict.fromkeys(names))


def access_label(prop):
    a = prop.get("access", "rw")
    if a == "r":
        return "r/o"
    if a == "w":
        return "w/o"
    return ""


def fmt_command(cmd, indent="  "):
    lines = []
    name = cmd.get("name")
    desc = (cmd.get("description") or "").strip()
    lines.append("%sv %s%s" % (indent, name, ("  — " + desc) if desc else ""))
    dp = cmd.find("direct-parameter")
    if dp is not None:
        opt = "optional" if dp.get("optional") == "yes" else ""
        lines.append("%s    <%s>  [%s]%s" % (indent, types_of(dp), opt or "direct object",
                                             ("  — " + dp.get("description")) if dp.get("description") else ""))
    for p in cmd.findall("parameter"):
        opt = p.get("optional") == "yes"
        head = "[%s %s]" % (p.get("name"), types_of(p)) if opt else "%s %s" % (p.get("name"), types_of(p))
        lines.append("%s    %s%s" % (indent, head, ("  — " + p.get("description")) if p.get("description") else ""))
    res = cmd.find("result")
    if res is not None:
        lines.append("%s    → %s%s" % (indent, types_of(res),
                                       ("  — " + res.get("description")) if res.get("description") else ""))
    return lines


def fmt_class(cls, indent="  "):
    lines = []
    if cls.tag == "class-extension":
        name = "%s (extension)" % (cls.get("extends") or "application")
    else:
        name = cls.get("name")
    extra = []
    if cls.get("inherits"):
        extra.append("inherits " + cls.get("inherits"))
    if cls.get("plural"):
        extra.append("plural " + cls.get("plural"))
    desc = (cls.get("description") or "").strip()
    lines.append("%sn %s%s%s" % (indent, name, ("  (" + ", ".join(extra) + ")") if extra else "",
                                 ("  — " + desc) if desc else ""))
    props = cls.findall("property")
    if props:
        lines.append("%s    Properties:" % indent)
        for p in props:
            acc = access_label(p)
            lines.append("%s      %s (%s%s)%s" % (indent, p.get("name"), types_of(p),
                                                  (", " + acc) if acc else "",
                                                  ("  — " + p.get("description")) if p.get("description") else ""))
    elems = cls.findall("element")
    if elems:
        lines.append("%s    Elements: %s" % (indent, ", ".join(e.get("type") for e in elems)))
    resp = cls.findall("responds-to")
    if resp:
        lines.append("%s    Responds to: %s" % (indent, ", ".join(r.get("command") for r in resp)))
    return lines


def fmt_enum(en, indent="  "):
    vals = [e.get("name") for e in en.findall("enumerator")]
    return ["%se %s: %s" % (indent, en.get("name"), " | ".join(vals))]


def main():
    ap = argparse.ArgumentParser(description="把 sdef 字典转成可读签名")
    ap.add_argument("target", help="App 路径 / .osax 路径，或 - 表示从 stdin 读")
    ap.add_argument("--suite", action="append", default=[], help="只看指定 Suite（可重复）")
    ap.add_argument("--grep", help="只输出 name 含该子串的条目")
    ap.add_argument("--commands-only", action="store_true")
    ap.add_argument("--classes-only", action="store_true")
    args = ap.parse_args()

    try:
        root = ET.fromstring(load(args.target))
    except ET.ParseError as e:
        sys.exit("sdef 解析失败: %s" % e)

    g = args.grep.lower() if args.grep else None
    for suite in root.iter("suite"):
        sname = suite.get("name") or ""
        if args.suite and sname not in args.suite:
            continue
        cmds = suite.findall("command")
        classes = suite.findall("class") + suite.findall("class-extension")
        enums = suite.findall("enumeration")
        if g:
            cmds = [c for c in cmds if g in (c.get("name") or "").lower()]
            classes = [c for c in classes if g in (c.get("name") or c.get("extends") or "").lower()]
            enums = [e for e in enums if g in (e.get("name") or "").lower()]
        if not (cmds or classes or enums):
            continue
        print("═" * 72)
        print("SUITE %s  [code=%s]" % (sname, suite.get("code")))
        if suite.get("description"):
            print("        %s" % suite.get("description").strip())
        print("═" * 72)
        if cmds and not args.classes_only:
            print("  Commands (%d)" % len(cmds))
            for c in cmds:
                for ln in fmt_command(c):
                    print(ln)
        if classes and not args.commands_only:
            print("  Classes (%d)" % len(classes))
            for c in classes:
                for ln in fmt_class(c):
                    print(ln)
        if enums and not args.commands_only:
            print("  Enumerations (%d)" % len(enums))
            for e in enums:
                for ln in fmt_enum(e):
                    print(ln)
        print()


if __name__ == "__main__":
    main()

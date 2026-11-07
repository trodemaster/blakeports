#!/usr/bin/env python3
"""Convert a forum-post Markdown draft to conservative phpBB BBCode.

Usage: md2bbcode.py draft.md > post.txt

Emaculation's phpBB caps [size] at 100 and the house style is plain, so the
output only uses [b], [i], [url], [list]/[*] and [code]:

- any heading becomes a bold line
- **bold** -> [b], *italic* / _italic_ -> [i]
- `inline code` -> plain text (phpBB has no inline code tag)
- [text](url) -> [url=url]text[/url]; bare URLs are left for phpBB to link
- "- " / "* " / "1. " lists -> [list] / [list=1] with [*] items
- fenced code blocks -> [code]...[/code], kept verbatim
- each paragraph or list item is joined onto one line, so pasting doesn't
  pick up hard line breaks
"""
import re
import sys


def inline(text):
    code = []

    def stash(m):
        code.append(m.group(1))
        return f"\0{len(code) - 1}\0"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r"[url=\2]\1[/url]", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"[b]\1[/b]", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"[i]\1[/i]", text)
    text = re.sub(r"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)", r"[i]\1[/i]", text)
    return re.sub(r"\0(\d+)\0", lambda m: code[int(m.group(1))], text)


LIST_ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s+(.*)")


def convert(lines):
    out, para, items, ordered = [], [], [], False
    in_code = False

    def flush_para():
        if para:
            out.append(inline(" ".join(s.strip() for s in para)))
            out.append("")
            para.clear()

    def flush_list():
        if items:
            out.append("[list=1]" if ordered else "[list]")
            out.extend("[*]" + inline(" ".join(i)) for i in items)
            out.append("[/list]")
            out.append("")
            items.clear()

    for line in lines:
        line = line.rstrip("\n")
        if line.strip().startswith("```"):
            if in_code:
                out.append("[/code]")
                out.append("")
            else:
                flush_para()
                flush_list()
                out.append("[code]")
            in_code = not in_code
            continue
        if in_code:
            out.append(line)
            continue
        if line.lstrip().startswith("|") or line.lstrip().startswith("!["):
            print(f"md2bbcode: table/image line left as text: {line[:60]}",
                  file=sys.stderr)
        if not line.strip():
            flush_para()
            flush_list()
            continue
        m = re.match(r"^#{1,6}\s+(.*)", line)
        if m:
            flush_para()
            flush_list()
            out.append(f"[b]{inline(m.group(1).strip())}[/b]")
            out.append("")
            continue
        m = LIST_ITEM.match(line)
        if m:
            flush_para()
            if not items:
                ordered = m.group(1)[0].isdigit()
            items.append([m.group(2).strip()])
            continue
        if items:  # continuation of the last list item
            items[-1].append(line.strip())
        else:
            para.append(line)
    flush_para()
    flush_list()
    while out and out[-1] == "":
        out.pop()
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    src = open(sys.argv[1], encoding="utf-8") if len(sys.argv) > 1 else sys.stdin
    sys.stdout.write(convert(src))

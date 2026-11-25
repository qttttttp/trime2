#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen-code-table.py —— 把旧「单字编码.text」转成新产物：

  1. 单字编码.text   named 字段格式（面板反查 / 手动生成 idx 的数据源）：
        ["花"]={笔画="HSSPSPZ",拆分="cao'hua",拼音="huā,hua",双拼小鹤="hx,hx",
                双拼自然码="hw,hw",全拼="hua",86五笔="awx",98五笔="awxb",U码="U+82B1"}
     修正：拆分结尾多余的逗号去掉；多拆分/多音均用半角逗号分隔。

  2. 单字编码.lua    结构化 Lua 表，可 require / dofile：
        local M={}
        M["花"]={["笔画"]="HSSPSPZ",...}
        return M

  3. 单字编码.idx    可选（加 --idx 才生成）。定宽二分索引（每行 23 字节）：
        HEX8 OFFSET7 LENGTH5\n
     面板第一次反查时会用 .text 在设备上自动生成 idx，所以不用随包提供；
     想离线生成好了直接部署的话加 --idx。

新增编码：
  · 双拼小鹤 / 双拼自然码 —— 由拼音逐读音推导（多音字用逗号对应，
    转不出的读音占位「无」）
  · 全拼 —— 无声调小写，ü 写作 v，多音逗号分隔、去重保序

用法： python3 gen-code-table.py 旧单字编码.text [输出目录] [--idx]
"""

import sys, os

# ---------------------------------------------------------------- 双拼

SM3 = {"zh": "v", "ch": "i", "sh": "u"}

# 韵母 → 键位（不含零声母特判）
XIAOHE = {
    "a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v",
    "ai": "d", "ei": "w", "ui": "v", "ao": "c", "ou": "z", "iu": "q",
    "ie": "p", "an": "j", "en": "f", "in": "b", "un": "y", "vn": "y",
    "ang": "h", "eng": "g", "ing": "k", "ong": "s",
    "ia": "x", "ua": "x", "iao": "n", "ian": "m", "iang": "l",
    "uang": "l", "uan": "r", "van": "r", "ue": "t", "ve": "t",
    "iong": "s", "uo": "o",
}
ZIRAN = {
    "a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v",
    "ai": "l", "ei": "z", "ui": "v", "ao": "k", "ou": "b", "iu": "q",
    "ie": "x", "an": "j", "en": "f", "in": "n", "un": "p", "vn": "p",
    "ang": "h", "eng": "g", "ing": "y", "ong": "s",
    "ia": "w", "ua": "w", "iao": "c", "ian": "m", "iang": "d",
    "uang": "d", "uan": "r", "van": "r", "ue": "t", "ve": "t",
    "iong": "s", "uo": "o",
}

TONE_MAP = {
    "ā": "a", "á": "a", "ǎ": "a", "à": "a",
    "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
    "ē": "e", "é": "e", "ě": "e", "è": "e",
    "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
    "ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
    "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v",
    "ê": "e", "ŋ": "n",
}


def detone(s):
    out = []
    for c in s:
        out.append(TONE_MAP.get(c, c))
    s = "".join(out)
    return s.replace("ü", "v").lower()


def split_syl(syl):
    """声母 + 韵母；零声母返回 (None, syl)"""
    for sm, key in SM3.items():
        if syl.startswith(sm):
            return key, syl[2:]
    if syl and syl[0] in "bpmfdtnlgkhjqxrzcsyw":
        return syl[0], syl[1:]
    return None, syl


def final_key(f, sm, table):
    """韵母字符串 → 键位；j/q/x/y 后的 u 是 ü"""
    if sm in ("j", "q", "x", "y") and f.startswith("u"):
        f = "v" + f[1:]
    if f in table:
        return table[f]
    return None


def to_shuangpin(syl, table):
    """单音节 → 双拼两码；失败返回 None"""
    syl = detone(syl.strip())
    if not syl:
        return None
    # 已是 v 形式（nǚ → nv）
    sm, f = split_syl(syl)
    if sm is None:                       # 零声母
        if len(syl) == 1:
            return syl + syl
        if len(syl) == 2:
            return syl if f in table or syl in ("ai", "ei", "an", "en", "ao",
                                                "ou", "er") else None
        if len(syl) >= 3:
            k = final_key(syl, None, table)
            return (syl[0] + k) if k else None
        return None
    # 特例：wai 的韵母是 uai
    if sm == "w" and f == "ai":
        f = "uai"
    k = final_key(f, sm, table)
    if k is None:
        return None
    return sm + k


def shuangpin_list(pinyin, table):
    out = []
    for syl in pinyin.split(","):
        syl = syl.strip()
        if not syl or syl == "无":
            out.append("无")
            continue
        code = to_shuangpin(syl, table)
        out.append(code if code else "无")
    return ",".join(out)


def to_quanpin(pinyin):
    out, seen = [], set()
    for syl in pinyin.split(","):
        syl = detone(syl.strip())
        if not syl or syl == "无":
            continue
        if syl not in seen:
            seen.add(syl)
            out.append(syl)
    return ",".join(out) if out else "无"


# ---------------------------------------------------------------- 解析旧表

def parse_line(v):
    """旧格式一行值 → dict；拆分/拼音之间按最后一个「, 」切"""
    t = v.split()
    uni = None
    if t and t[-1].startswith("U+") and len(t[-1]) > 2:
        uni = t.pop()
    wb98 = wb86 = None
    if len(t) >= 3:
        wb98 = t.pop()
        wb86 = t.pop()
    stroke = t.pop(0) if t else None
    mid = " ".join(t)
    cut = mid.rfind(", ")
    if cut >= 0:
        chai, pinyin = mid[:cut], mid[cut + 2:]
    else:
        parts = mid.split(None, 1)
        chai = parts[0] if parts else None
        pinyin = parts[1] if len(parts) > 1 else None
    return {
        "笔画": stroke or "无",
        "拆分": (chai or "无").rstrip(","),
        "拼音": pinyin or "无",
        "86五笔": wb86 or "无",
        "98五笔": wb98 or "无",
        "U码": uni or "无",
    }


def lua_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def fmt_record(rec):
    keys = ["笔画", "拆分", "拼音", "双拼小鹤", "双拼自然码", "全拼",
            "86五笔", "98五笔", "U码"]
    parts = []
    for k in keys:
        v = rec.get(k)
        if v is None or v == "":
            continue
        parts.append('["%s"]="%s"' % (k, lua_escape(v)))
    return "{" + ",".join(parts) + "}"


# ---------------------------------------------------------------- 主流程

def text_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def fmt_text_line(ch, rec):
    """named 字段一行：["花"]={笔画="...",拆分="...",...}"""
    keys = ["笔画", "拆分", "拼音", "双拼小鹤", "双拼自然码", "全拼",
            "86五笔", "98五笔", "U码"]
    parts = []
    for k in keys:
        v = rec.get(k)
        if v is None or v == "":
            v = "无"
        parts.append('%s="%s"' % (k, text_escape(v)))
    return '["%s"]={%s}\n' % (ch, ",".join(parts))


def main():
    args = [a for a in sys.argv[1:]]
    want_idx = "--idx" in args
    args = [a for a in args if a != "--idx"]
    src = args[0] if args else "单字编码.text"
    outdir = args[1] if len(args) > 1 else os.path.dirname(
        os.path.abspath(src))

    data = open(src, "rb").read()          # 字节级，为索引算 offset
    text = data.decode("utf-8")

    records = {}
    import re
    pat = re.compile(r'\["(.+?)"\]\s*=\s*"(.*?)"')
    n_total = 0
    for line in text.split("\n"):
        raw = line.strip()
        if not raw or raw.startswith("--") or "=" not in raw:
            continue
        m = pat.search(raw)
        if not m:
            continue
        ch, v = m.group(1), m.group(2)
        rec = parse_line(v)
        rec["双拼小鹤"] = shuangpin_list(rec["拼音"], XIAOHE)
        rec["双拼自然码"] = shuangpin_list(rec["拼音"], ZIRAN)
        rec["全拼"] = to_quanpin(rec["拼音"])
        records[ch] = rec
        n_total += 1

    # 注意：idx 的 offset 必须指向「新写出的 .text」的行区间，
    # 旧文件只是解析来源，行布局不同。这里延后到写出新 .text 之后再算。
    offsets = None

    # ---- 写 新 单字编码.text（named 字段格式）
    text_path = os.path.join(outdir, "单字编码.text")
    with open(text_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("--[==[ 单字编码.text —— named 字段格式，由 gen-code-table.py 生成\n")
        f.write('字段：["字"]={笔画=...,拆分=...,拼音=...,双拼小鹤=...,双拼自然码=...,\n')
        f.write("      全拼=...,86五笔=...,98五笔=...,U码=...}（多音/多拆分逗号分隔）\n")
        f.write("手写面板第一次反查会用本文件自动生成 单字编码.idx\n]==]\n")
        for ch in records:
            f.write(fmt_text_line(ch, records[ch]))

    # ---- 写 单字编码.lua
    lua_path = os.path.join(outdir, "单字编码.lua")
    with open(lua_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("--[==[ 单字编码.lua —— 由 gen-code-table.py 生成，勿手改\n")
        f.write("来源：单字编码.text（拼音及笔画和拆分来自万象拼音）\n")
        f.write("字段：笔画 / 拆分 / 拼音（多音逗号分隔）/ 双拼小鹤 / 双拼自然码 /\n")
        f.write("      全拼（无声调，ü 作 v）/ 86五笔 / 98五笔 / U码\n")
        f.write("用法：local M = dofile(\"单字编码.lua\")  或  require(\"单字编码\")\n")
        f.write("]==]\n")
        f.write("local M={}\n")
        for ch in records:
            f.write('M["%s"]=%s\n' % (lua_escape(ch), fmt_record(records[ch])))
        f.write("return M\n")

    # ---- 写 单字编码.idx（可选：面板也会在设备上自动生成）
    idx_path = None
    if want_idx:
        # 基于刚写出的新 .text 精确计算行字节区间
        new_text = open(text_path, "rb").read().decode("utf-8")
        offsets = []
        line_pat = re.compile(r'^\["(.+?)"\]\s*=\s*\{',   # named 行（行首锚定，跳过注释示例）
                              re.M)
        for m in line_pat.finditer(new_text):
            ch = m.group(1)
            line_start = new_text.rfind("\n", 0, m.start()) + 1
            nl = new_text.find("\n", m.end())
            line_end = len(new_text) if nl < 0 else nl
            b_start = len(new_text[:line_start].encode("utf-8"))
            b_line = len(new_text[line_start:line_end].encode("utf-8"))
            hex8 = ch.encode("utf-8").hex().upper().zfill(8)
            offsets.append((hex8, b_start, b_line))
        offsets.sort(key=lambda x: x[0])
        idx_path = os.path.join(outdir, "单字编码.idx")
        with open(idx_path, "w", encoding="ascii", newline="\n") as f:
            for hex8, off, ln in offsets:
                f.write("%-8s %07d %05d\n" % (hex8, off, ln))

    # ---- 报告
    print("解析 %d 字" % n_total)
    print("输出 %s (%.1f MB)" % (lua_path,
          os.path.getsize(lua_path) / 1048576))
    if idx_path:
        print("输出 %s (%.1f KB)" % (idx_path,
              os.path.getsize(idx_path) / 1024))
    for ch in ("花", "手", "长", "女", "爱", "恩", "悟", "中", "学", "月", "鱼"):
        r = records.get(ch)
        if r:
            print(ch, {k: r[k] for k in ("笔画", "拆分", "拼音", "双拼小鹤",
                                         "双拼自然码", "全拼", "86五笔",
                                         "98五笔", "U码") if k in r})


if __name__ == "__main__":
    main()

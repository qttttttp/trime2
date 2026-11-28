#!/usr/bin/env python3
"""编译后修正 ML Kit AAR 里的 https 校验分支。

背景
----
digital-ink-recognition AAR 的 MddFileDownloader 在下载前会做一次
url 是否以 "https" 开头的校验，失败就抛 INSECURE_URL_ERROR。
本地回环服务（http://127.0.0.1:18080）因此永远下载不了。

能用的那一版 APK 里，这个分支的字节码是 `goto`（无条件跳过抛错块），
而任何重新编译产出的都是 `if-nez`（条件成立才跳过）。
两者只差 3 个字节，位置在 zzwu.zzc 内、const-string
"%s: File url = %s is not secure" 之前。

本脚本按特征定位并改写这 3 个字节，然后重算 dex 头部的
checksum / signature，使产物与可用版本等价。

用法
----
  python3 patch-dex-https.py classes.dex [-o classes.patched.dex]
"""

import hashlib
import struct
import sys
import zlib

MARKER = b"is not secure"
# if-nez v1, <target>  ->  goto <target>
IF_NEZ_OP = 0x39
GOTO_OP = 0x28


def uleb128(data, pos):
    result = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, pos
        shift += 7


def string_at(data, off):
    """读取 string_data_item 的 UTF-16 长度前缀后的 MUTF-8 内容。"""
    _, p = uleb128(data, off)
    end = data.index(b"\x00", p)
    return data[p:end]


def find_string_indices(data):
    """返回匹配 MARKER 的 string 索引集合。"""
    n = struct.unpack_from("<I", data, 0x38)[0]
    off = struct.unpack_from("<I", data, 0x3C)[0]
    hits = set()
    for i in range(n):
        p = struct.unpack_from("<I", data, off + 4 * i)[0]
        try:
            s = string_at(data, p)
        except ValueError:
            continue
        if MARKER in s:
            hits.add(i)
    return hits


def patch(data):
    data = bytearray(data)
    idxs = find_string_indices(data)
    if not idxs:
        raise SystemExit("未找到 'is not secure' 字符串，dex 结构可能已变化")

    patched = 0
    for idx in idxs:
        # const-string vAA, string@BBBB  -> 1a AA BB BB
        needle = bytes([0x1A, 0x00, idx & 0xFF, (idx >> 8) & 0xFF])
        start = 0
        while True:
            p = data.find(needle, start)
            if p < 0:
                break
            start = p + 1
            q = p - 4
            if q < 0:
                continue
            if data[q] != IF_NEZ_OP or data[q + 1] != 0x01:
                continue
            target_lo, target_hi = data[q + 2], data[q + 3]
            data[q] = GOTO_OP
            data[q + 1] = target_lo
            data[q + 2] = target_hi
            data[q + 3] = 0x00
            patched += 1
            print("  修正 0x%06x: if-nez -> goto (+0x%x)" % (q, target_lo | (target_hi << 8)))
    if not patched:
        raise SystemExit("找到字符串但没有可修正的分支，dex 可能已被 patch 过")

    # dex 头部：signature(12..31) = sha1(data[32:])，checksum(8..11) = adler32(data[12:])
    data[12:32] = hashlib.sha1(bytes(data[32:])).digest()
    data[8:12] = (zlib.adler32(bytes(data[12:])) & 0xFFFFFFFF).to_bytes(4, "little")
    print("  已重算 dex checksum / signature")
    return bytes(data), patched


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not args:
        print(__doc__)
        return 1
    src = args[0]
    dst = src
    if "-o" in sys.argv:
        dst = sys.argv[sys.argv.index("-o") + 1]
    raw = open(src, "rb").read()
    print("处理 %s (%d 字节)" % (src, len(raw)))
    out, n = patch(raw)
    open(dst, "wb").write(out)
    print("完成：%d 处，输出 %s" % (n, dst))
    return 0


if __name__ == "__main__":
    sys.exit(main())

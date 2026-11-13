#!/usr/bin/env python3
"""
make-offline-aar.py —— 把 ML Kit 的模型下载地址改成本地文件

原理（反编译 digital-ink-recognition:19.0.0 得到）：
  DigitalInkRecognitionFileDependencyManager.initialize()
    → DigitalInkManifestParser.parseManifestFromAsset("manifest.json")
  地址写在 AAR 的 assets/manifest.json 里，不从服务器拉。
  下载器 zzaab 支持三种 scheme：
    http(s)://  网络下载
    file:       url.replace("file:/","") → new File(path) → FileInputStream
    data:       data URI
  Pack.isValid() 只校验 URL 非空 / compressedSize>0 / name 非空，不限制 scheme。

所以把 download_urls 改成 file: 指向本地离线包，ML Kit 会自己完成
校验（md5/sha1）、解包、写 Mobstore、登记 Icing —— 状态天然合法。

用法：
  ./make-offline-aar.py --aar digital-ink-recognition-19.0.0.aar \
                        --pkg com.osfans.trime \
                        --langs zh-Hani,zh-Hani-CN \
                        --out ./offline
"""
import argparse
import json
import shutil
import struct
import sys
import zipfile
from pathlib import Path


# ---------------------------------------------------------------- protobuf

def _varint(b, i):
    v = s = 0
    while True:
        c = b[i]
        i += 1
        v |= (c & 0x7F) << s
        if not c & 0x80:
            return v, i
        s += 7


def _pb_fields(b):
    i, n, out = 0, len(b), []
    while i < n:
        key, i = _varint(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _varint(b, i)
        elif wt == 2:
            ln, i = _varint(b, i)
            v = b[i:i + ln]
            i += ln
        elif wt == 5:
            v = struct.unpack("<f", b[i:i + 4])[0]
            i += 4
        elif wt == 1:
            v = struct.unpack("<d", b[i:i + 8])[0]
            i += 8
        else:
            raise ValueError("unsupported wire type %d" % wt)
        out.append((f, wt, v))
    return out


def parse_packmapping(data):
    """返回 {语言 tag: {字段号: pack 名}}，字段 5/6/7 分别是 recospec/model/fst。"""
    mapping = {}
    for _f, _wt, v in _pb_fields(data):
        if not isinstance(v, bytes):
            continue
        key, items = None, {}
        for sf, sw, sv in _pb_fields(v):
            if sf == 1 and isinstance(sv, bytes):
                key = sv.decode("utf-8", "replace")
            elif sw == 2 and isinstance(sv, bytes):
                items[sf] = sv.decode("utf-8", "replace")
        if key:
            mapping[key] = items
    return mapping


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aar", required=True, help="原始 AAR")
    ap.add_argument("--pkg", default="com.osfans.trime", help="应用包名")
    ap.add_argument("--langs", default="zh-Hani,zh-Hani-CN")
    ap.add_argument("--dir", default=None,
                    help="离线包目录（默认 /sdcard/Android/data/<pkg>/files/offline-models）")
    ap.add_argument("--url-prefix", default=None,
                    help="直接指定下载地址前缀（如 http://127.0.0.1:18080），"
                         "设置后 download_urls = <prefix>/<pack>.zip，忽略 --dir/file: 逻辑")
    ap.add_argument("--out", default="./offline")
    args = ap.parse_args()

    out_dir = Path(args.out)
    # 与 06 补丁里 MlkitModelInstaller.ASSET_DIR 对应：assets/mlkit-offline/
    models_dir = out_dir / "assets" / "mlkit-offline"
    models_dir.mkdir(parents=True, exist_ok=True)

    device_dir = args.dir or "/sdcard/Android/data/%s/files/offline-models" % args.pkg

    aar = Path(args.aar)
    with zipfile.ZipFile(aar) as z:
        names = z.namelist()
        manifest_raw = z.read("assets/manifest.json")
        packmap_raw = z.read("assets/packmapping.pb")

    manifest = json.loads(manifest_raw)
    mapping = parse_packmapping(packmap_raw)

    langs = [s.strip() for s in args.langs.split(",") if s.strip()]
    wanted = {}
    for lang in langs:
        if lang not in mapping:
            print("警告：packmapping 里没有 %s，跳过" % lang, file=sys.stderr)
            continue
        for _fid, pack in sorted(mapping[lang].items()):
            wanted.setdefault(pack, []).append(lang)

    if not wanted:
        sys.exit("没有匹配到任何 pack，检查 --langs")

    packs = {p["name"]: p for p in manifest["packs"]}
    missing = [p for p in wanted if p not in packs]
    if missing:
        sys.exit("manifest 里找不到这些 pack：%s" % ", ".join(missing))

    changed = 0
    for name in wanted:
        p = packs[name]
        if args.url_prefix:
            # http 模式：地址指回面板内置的本地模型服务（127.0.0.1:18080），
            # 服务根目录 = lua 脚本所在目录，zip 放脚本旁即可
            p["download_urls"] = ["%s/%s.zip" % (args.url_prefix.rstrip("/"), name)]
        else:
            # 只保留一个本地地址：留 https 备用会让 ML Kit 在 file: 失败时走网络
            # 注意前缀必须是 file://（双斜杠）：下载器内部 url.replace("file:/", "")，
            # 单斜杠 file:/sdcard/... 会被剥成相对路径 "sdcard/..." 导致读文件失败；
            # file:///sdcard/... 替换后剩 "//sdcard/..."，内核规范化为 "/sdcard/..."。
            p["download_urls"] = ["file://%s/%s.zip" % (device_dir, name)]
        changed += 1

    new_manifest = json.dumps(manifest, ensure_ascii=False, separators=(",", ":"))
    if args.url_prefix:
        print("改写 %d 个 pack 的下载地址 → %s/" % (changed, args.url_prefix.rstrip("/")))
    else:
        print("改写 %d 个 pack 的下载地址 → file://%s/" % (changed, device_dir))

    out_aar = out_dir / aar.name.replace(".aar", "-offline.aar")
    with zipfile.ZipFile(aar) as zin, zipfile.ZipFile(out_aar, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "assets/manifest.json":
                data = new_manifest.encode("utf-8")
            # 保留原时间戳与属性，避免 AGP 解析异常
            zi = zipfile.ZipInfo(item.filename, date_time=item.date_time)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = item.external_attr
            zout.writestr(zi, data)

    # 离线包放置清单
    rows = []
    for name in sorted(wanted):
        p = packs[name]
        rows.append((name, p["size"], p["compressed_size"], p["sha1_checksum"][:12],
                     ",".join(wanted[name])))

    with open(out_dir / "pack-map.tsv", "w", encoding="utf-8") as f:
        f.write("pack\tunpacked_bytes\tzip_bytes\tsha1\tlanguages\n")
        for r in rows:
            f.write("\t".join(str(x) for x in r) + "\n")

    with open(out_dir / "PLACE-MODELS.txt", "w", encoding="utf-8") as f:
        f.write("【方式 1 · 随包，推荐】\n")
        f.write("  cp -r assets/mlkit-offline  <仓库>/app/src/main/assets/\n\n")
        f.write("【方式 2 · 手动推】\n")
        f.write("  adb shell mkdir -p \"%s\"\n" % device_dir)
        f.write("  adb push assets/mlkit-offline/. \"%s/\"\n\n" % device_dir)
        f.write("文件名必须完全一致（就是 pack 名 + .zip）：\n\n")
        for name, size, csize, sha, lang in rows:
            f.write("  %-64s  %8.2f MB   %s\n" % (name + ".zip", size / 1048576, lang))

    print()
    print("输出 AAR : %s" % out_aar)
    print("放置清单 : %s" % (out_dir / "PLACE-MODELS.txt"))
    print("包映射   : %s" % (out_dir / "pack-map.tsv"))
    total = sum(packs[n]["size"] for n in wanted)
    print("离线包合计: %.1f MB（%d 个）" % (total / 1048576, len(wanted)))
    print()
    print("下一步：")
    print("  1. cp -r assets/mlkit-offline <仓库>/app/src/main/assets/")
    print("     （或 adb push 到 %s）" % device_dir)
    print("  2. 用 %s 替换 app/libs/ 下的同名 AAR" % out_aar.name)
    print("  3. 调 RemoteModelManager.download()，走的就是本地文件")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# 编译后处理：修正 ML Kit AAR 的 https 校验分支，然后重新对齐并签名。
#
# 为什么需要这一步：
#   digital-ink-recognition-19.0.0 的 MddFileDownloader 在下载前会校验地址
#   是否以 https 开头，不是就抛 INSECURE_URL_ERROR。手写面板用
#   http://127.0.0.1:18080 提供模型，因此任何"干净编译"的包都下载不了。
#   唯一能用的那一版 APK 里，这条分支在字节码上是无条件跳转（goto），
#   相当于该检查不生效。两者只差 3 个字节，见 tools/patch-dex-https.py。
#
# 用法：
#   postprocess-apk.sh <apk> <keystore> <storepass> <alias> <keypass>
set -euo pipefail

APK=${1:?用法: postprocess-apk.sh <apk> <keystore> <storepass> <alias> <keypass>}
KS=${2:?}
STORE_PASS=${3:?}
ALIAS=${4:?}
KEY_PASS=${5:?}

SDK=${ANDROID_HOME:-/opt/android-sdk}
APKSIGNER=$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
ZIPALIGN=$(ls -d "$SDK"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1)
[[ -x "$APKSIGNER" ]] || { echo "找不到 apksigner"; exit 1; }
[[ -x "$ZIPALIGN" ]] || { echo "找不到 zipalign"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "==> 提取 classes.dex"
unzip -p "$APK" classes.dex > "$W/classes.dex"

echo "==> 修正 https 校验分支"
python3 "$HERE/patch-dex-https.py" "$W/classes.dex"

echo "==> 回写 APK"
python3 - "$APK" "$W/out.apk" "$W/classes.dex" <<'PY'
import sys, zipfile
src, out, dex_path = sys.argv[1], sys.argv[2], sys.argv[3]
dex = open(dex_path, "rb").read()
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(out, "w")
for i in zin.infolist():
    data = dex if i.filename == "classes.dex" else zin.read(i.filename)
    zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
    zi.compress_type = i.compress_type
    zi.external_attr = i.external_attr
    zi.create_system = i.create_system
    zout.writestr(zi, data)
zout.close()
PY

echo "==> 对齐与重签"
"$ZIPALIGN" -f -p 4 "$W/out.apk" "$W/out_aligned.apk"
"$APKSIGNER" sign --ks "$KS" --ks-pass "pass:$STORE_PASS" \
  --ks-key-alias "$ALIAS" --key-pass "pass:$KEY_PASS" "$W/out_aligned.apk"
"$APKSIGNER" verify --print-certs "$W/out_aligned.apk" | head -3

cp -f "$W/out_aligned.apk" "$APK"
echo "OK: 已修正并重签 -> $APK"

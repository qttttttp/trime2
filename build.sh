#!/usr/bin/env bash
# 一键构建 trime2 release APK（4 个 ABI），产物复制到 $OUT
# 前提：已执行 setup_env.sh
#
# ML Kit 离线 AAR 完全自动生成：
#   1. 从 Google Maven 下载原版 digital-ink-recognition AAR（Apache-2.0 公开依赖，带 sha1 校验）
#   2. tools/make-offline-aar.py 改写 manifest 的 download_urls → http://127.0.0.1:18080
#      （手写面板内置本地模型服务，运行期自动起停）
#   3. 产物放入 app/libs/，并确保 assets/mlkit-offline 为空（模型不打包进 APK，
#      4 个模型 zip 由用户放到 lua 脚本所在目录）
#
# 跳过 AAR 生成（用 libs 里现成的）：SKIP_AAR=1 bash build.sh
set -euo pipefail

SRC=${SRC:-/root/work/trime2/trime2-0.8.5}   # Trime 源码根目录（已打好补丁），按需覆盖
SDK=${SDK:-/opt/android-sdk}
OUT=${OUT:-$(pwd)/out-apk}
CACHE=${CACHE:-$(pwd)/.build-cache}
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK"

# ------------------------------------------------------------- 0. 参数
# 与设备实际包名一致（file: 时代已验证此坑：不一致则运行期全部 404）
PKG=com.nirenr.trime
LANGS=zh-Hani,zh-Hani-CN
MLKIT_VER=19.0.0
# 模型 zip 的本地服务地址（http2 路线：面板脚本内置 127.0.0.1:18080 服务）
URL_PREFIX=http://127.0.0.1:18080
# 原版 AAR 的 sha1（Google Maven 公布值，供应链校验）
AAR_SHA1=${AAR_SHA1:-2f4ebc121902df17a0304a6d1ac576dc8a60d9b0}   # digital-ink-recognition-19.0.0.aar @ Google Maven
TOOLS=${TOOLS:-$REPO_ROOT/tools}

AAR_URL="https://dl.google.com/android/maven2/com/google/mlkit/digital-ink-recognition/${MLKIT_VER}/digital-ink-recognition-${MLKIT_VER}.aar"

mkdir -p "$CACHE" "$OUT"

# ------------------------------------------------------------- 1. 生成离线 AAR
if [[ "${SKIP_AAR:-0}" != "1" ]]; then
  echo "==> 下载原版 AAR（Google Maven 公开依赖）"
  ORIG="$CACHE/digital-ink-recognition-${MLKIT_VER}.aar"
  if [[ ! -f "$ORIG" ]]; then
    curl -fsSL -o "$ORIG" "$AAR_URL"
  fi
  echo "$AAR_SHA1  $ORIG" | sha1sum -c -

  echo "==> 改写 manifest（$URL_PREFIX / pkg=$PKG / langs=$LANGS）"
  OFFLINE_OUT="$CACHE/offline-aar"
  mkdir -p "$OFFLINE_OUT"
  python3 "$TOOLS/make-offline-aar.py" \
    --aar "$ORIG" \
    --pkg "$PKG" \
    --langs "$LANGS" \
    --url-prefix "$URL_PREFIX" \
    --out "$OFFLINE_OUT"

  GEN="$OFFLINE_OUT/digital-ink-recognition-${MLKIT_VER}-offline.aar"

  echo "==> 断言 manifest 已改写"
  python3 - "$GEN" "$PKG" <<'EOF'
import sys, zipfile, json
gen, pkg = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(gen) as z:
    m = json.loads(z.read("assets/manifest.json"))
urls = [u for p in m["packs"] for u in p.get("download_urls", [])]
mine = [u for u in urls if "127.0.0.1" in u or pkg in u]
assert mine, "没有任何 pack 指向本地地址：" + str(set(u[:40] for u in urls))
local = [u for u in mine if u.startswith("http://127.0.0.1:18080/")]
assert local, "地址前缀不是本地服务：" + str(mine[:2])
print("OK: %d 个 pack 指向本地服务" % len(local))
EOF

  echo "==> 放入 app/libs，清空 assets 内模型"
  mkdir -p "$SRC/app/libs"
  cp -f "$GEN" "$SRC/app/libs/digital-ink-recognition-${MLKIT_VER}-offline.aar"
  mkdir -p "$SRC/app/src/main/assets/mlkit-offline"
  rm -f "$SRC/app/src/main/assets/mlkit-offline/"*.zip
else
  echo "==> SKIP_AAR=1，使用 app/libs 里现成的 AAR"
fi

# ------------------------------------------------------------- 2. 编译
cd "$SRC"
./gradlew :app:assembleRelease --no-daemon 2>&1 | grep -viE "^\s+at " | tail -40

# ------------------------------------------------------------- 3. 产物与签名校验
cp -f app/build/outputs/apk/release/*.apk "$OUT"/
ls -lh "$OUT"/*.apk

for f in "$OUT"/*arm64-v8a*.apk; do
  "$SDK/build-tools/35.0.0/apksigner" verify --print-certs "$f" | head -2
done

# 最终断言：APK 内不得有随包模型
python3 - "$OUT" <<'EOF'
import sys, zipfile, glob
for apk in glob.glob(sys.argv[1] + "/*arm64-v8a*.apk"):
    zips = [n for n in zipfile.ZipFile(apk).namelist()
            if n.startswith("assets/mlkit-offline") and n.endswith(".zip")]
    assert not zips, apk + " 内出现随包模型：" + str(zips)
    print("OK: 无随包模型 ->", apk)
EOF

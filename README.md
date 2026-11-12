# trime2 补丁构建（个人 fork）

本仓库 fork 自 [nirenr/trime2](https://github.com/nirenr/trime2)，只做一件事：

> **每天自动拉取上游最新代码 → 应用 `patches/` 下的本地补丁 → 用 `trime2-100y` 密钥签名 → 发布 APK**

上游代码不做任何改动，所有个性化功能都以补丁形式叠加，因此可以长期跟随上游更新而不产生合并冲突。

---

## 一、下载

每次构建完成后，4 个 ABI 的 APK 会覆盖发布到同一个 Release：

```
https://github.com/<你的用户名>/trime2/releases/tag/patched-latest
```

| ABI | 适用设备 |
|---|---|
| `arm64-v8a` | 绝大多数现代手机（首选） |
| `armeabi-v7a` | 老款 32 位设备 |
| `x86_64` / `x86` | 模拟器 |

链接永久固定，每次构建自动更新资产，不需要每次找新的下载地址。

---

## 二、⚠️ 签名不同，不能覆盖安装

**这是最容易踩的坑。**

| | 上游官方包 | 本仓库构建的包 |
|---|---|---|
| 包名 | `com.nirenr.trime` | `com.nirenr.trime`（相同） |
| 签名 | 上游自己的密钥 | `trime2-100y` |

包名相同但签名不同，Android 会直接拒绝安装，报错：

```
INSTALL_FAILED_UPDATE_INCOMPATIBLE
签名不一致，安装失败
```

**所以必须卸载旧版再装**，无法直接覆盖。同样地，本仓库的包也不能覆盖安装到官方版之上，反之亦然。

### 卸载前务必备份

卸载会清空应用数据（**rime 用户目录、自定义方案、主题、词库、配置全部丢失**）。卸载前请：

1. 用输入法设置里的备份/导出功能（如果有）
2. 或手动把 rime 用户数据目录整体复制到电脑/其他位置 —— 通常在
   `/sdcard/Android/data/com.nirenr.trime/files/rime`
   或 `/sdcard/rime`，以你实际使用的部署方式为准
3. 主题目录（`themes/`）、自定义字体也一并保留

### 确认签名是否正确

安装前可用以下命令核对，输出的 SHA-256 应与下面一致：

```bash
apksigner verify --print-certs com.nirenr.trime-0.8.5-arm64-v8a-release.apk
```

```
SHA-256: 42:C0:18:B9:FD:B6:01:DC:73:7D:1D:C8:5E:2C:A7:40:E0:99:28:A1:E4:0C:7E:B7:E3:19:D7:40:46:E2:E1:4B
```

证书信息：`CN=Trime2, OU=Dev, O=Dev, L=Beijing, ST=Beijing, C=CN`，有效期至 2126 年。

CI 构建的最后一步也会打印这个指纹，两者一致即说明签名生效。

---

## 三、补丁清单

补丁按**文件名字典序**依次应用，两位数字前缀决定顺序。后应用的补丁基于「前面已应用」的文件状态生成，因此顺序不能随意打乱。

| 补丁 | 改动文件 | 作用 |
|---|---|---|
| `01-voice-asr.patch` | `Speech.java`<br>`AiClient.java`<br>`VoiceInputDialog.java`<br>`TrimeService.java`<br>`ThemeManager.java`<br>`AndroidManifest.xml`<br>`themes/default/main.lua` | **语音输入增强**。恢复「长按说话、松手上屏」的原生体验；新增 AI 转写链路（`AiClient.transcribeAudio()` 走 OpenAI 兼容的 `/v1/audio/transcriptions`，multipart 上传 WAV）；按模型名自动分流（含 `sensevoice`/`whisper`/`paraformer`/`asr` 的模型走转写接口，其余走 chat）；`asr_config` 支持可选 `api` 字段强制指定接口；含引擎切换即时生效、权限误报静默、OpenCC 后台转换、Lua 异常兜底等修复 |
| `02-font-system-first.patch` | `theme/Style.java` | **字体集合「系统字体优先」**。主题 `font` 表里写 `"system"` 占位符，构建 Android 10+ 的 `CustomFallbackBuilder` 原生逐字形回退链，把系统字体放到链中该位置，实现「常用字用系统字体、系统显示不了的生僻字/图标自动落到后面的字体」。`system` 可放在任意位置、可多次出现；解析 `/system/etc/fonts.xml` 时会去重（规避 MiSansVF 重复列出的 `already been added` 异常） |
| `03-clipboard-broadcast.patch` | `TrimeService.java` | **剪贴板变化广播**。剪贴板内容变化后发送本地广播 `com.trime2.CLIP_CHANGED`（`setPackage` 限定本应用，**不携带文本**，避免大文本跨 Binder 拷贝或超限），供 Lua 脚本侧监听 |
| `04-http-stream.patch` | `androlua/Http.java` | **HTTP 流式上传**。新增 `Http.putFile(url, path, header, callback)`，即 WebDAV PUT 直传本地文件：`setFixedLengthStreamingMode` + 64KB 缓冲边读边写，内存占用与文件大小无关；不走 `LuaString → Java String` 的 UTF-8 往返，二进制安全 |
| `05-file-offset-compat.patch` | `app/src/main/jni/CMakeLists.txt` | **native 编译兼容修复**。上游子模块里的 Lua 会在 `lprefix.h` 自动定义 `_FILE_OFFSET_BITS=64`，在 32 位 ABI + `minSdk 21` 下会导致 `fseeko`/`ftello` 的声明被 bionic 的 API 24 可用性守卫隐藏，`liolib.c` 编译报 `call to undeclared function 'fseeko'`。加一行 `add_compile_definitions(_FILE_OFFSET_BITS=0)` 使所有文件使用普通 `off_t`，32/64 位均可编译 |

### 不参与构建的补丁

`安卓9字体集合修复.patch`（如果存在）会被 workflow 的 `*android9*` / `*安卓9*` 规则自动跳过 —— 它是 Android 9 的单字体降级方案，与当前的原生回退链方案冲突。

---

## 四、如何新增补丁

### 1. 准备本地源码

```bash
git clone https://github.com/<你的用户名>/trime2.git
cd trime2
git remote add upstream https://github.com/nirenr/trime2.git
git fetch upstream develop
git reset --hard upstream/develop        # 与 CI 一致：以纯上游为基线
```

### 2. 改代码

直接编辑源码，不要先打旧补丁。若要基于某个已有补丁继续改，先 `git apply patches/0X-xxx.patch` 再动手，否则生成的 diff 会包含重复内容。

### 3. 生成补丁

```bash
git diff -- app/src/main/java/com/osfans/trime/Speech.java > patches/06-my-feature.patch
```

- **路径必须是相对仓库根目录**（`app/src/...`），CI 里用的是 `git apply -p1`
- 一次提交涉及多个文件时，可以一次性导出：
  ```bash
  git diff -- app/src/main/java/... app/src/main/res/... > patches/06-my-feature.patch
  ```
- 新增文件（`git add` 过的）需要先 `git add -N <file>`，否则不会出现在 `git diff` 里

### 4. 自测能否干净应用

```bash
git stash                                   # 收起改动
git checkout -- .                           # 确保干净
for p in patches/*.patch; do git apply --check "$p" || echo "FAIL: $p"; done
```

`--check` 只做试应用不落盘。全部通过再提交。

### 5. 命名规则

- 格式：`<两位序号>-<英文小写短横线描述>.patch`
- **用英文名**，中文名在部分解压/编码环境下会乱码，导致 `git apply` 找不到文件
- 序号决定应用顺序。若新补丁要依赖已有补丁的代码，序号必须**大于**被依赖的那个
- 想临时停用某个补丁：改名成 `xxx.patch.disabled` 或删掉即可，不用改 workflow

### 6. 提交并触发构建

```bash
git add patches/06-my-feature.patch
git commit -m "feat: 新增 xxx 补丁"
git push
```

workflow 监听 `patches/**` 的改动，push 后自动触发。也可手动：

```bash
gh workflow run build-patched.yml
```

### 7. 上游改动导致冲突怎么办

workflow 的应用逻辑分三级兜底：

1. `git apply -v`（严格应用）
2. 失败则 `git apply --3way`（三方合并，靠 blob 哈希匹配）
3. 再失败则 `patch -p1 --fuzz=3 --forward`（容忍行号偏移）

三级都失败 → 这一步变红，构建中断。此时说明上游改了同一段代码，需要人工解决：

```bash
git fetch upstream develop && git reset --hard upstream/develop
git apply --reject patches/06-my-feature.patch   # 生成 .rej 文件
# 手工合并 .rej 中的内容，改完重新生成补丁
git diff -- <改动的文件> > patches/06-my-feature.patch
```

---

## 五、workflow 说明

文件：`.github/workflows/build-patched.yml`

### 触发方式

| 方式 | 条件 |
|---|---|
| 定时 | 每天 UTC 18:00（北京时间 02:00）自动跟随上游 |
| push | 改动 `patches/**`、`signing/**` 或 workflow 自身 |
| 手动 | `workflow_dispatch`，可指定上游分支/标签（默认 `develop`） |

### 主要步骤

```
Checkout → 配置 git 身份 → 拉上游并 reset 为基线 → 恢复 patches/signing/workflow
→ 应用补丁 → Setup Java 17 → 安装 SDK 组件（cmake）
→ 配置签名与 gradle.properties → 拉子模块 → JNI 缓存
→ assembleRelease → 校验签名 → 上传 artifact → 发布到 patched-latest
```

### 关键设计

- **以纯上游为基线**：`git reset --hard FETCH_HEAD` 丢弃 fork 里的所有源码差异，然后回到 `$GITHUB_SHA` 取回 `patches/`、`signing/`、workflow 三个路径。所以在 fork 里直接改源码**不会**影响构建结果 —— 想改行为只能通过补丁。
- **串行化**：`concurrency: group: build-patched`，避免两次构建同时向 `patched-latest` 上传资产。
- **JNI 缓存**：`app/prebuilt` 按 `calculateNativeCacheHash` 的结果缓存。首次构建 30–40 分钟，之后命中缓存只需几分钟。
- **不依赖 `android-actions/setup-android`**：该 action 内部会执行 `sdkmanager tools`，而新镜像的 cmdline-tools 16.0 已移除 `tools` 包，会直接失败。改为自动定位 `$ANDROID_HOME/cmdline-tools/*/bin/sdkmanager`。
- **NDK 由 Gradle 自动下载**，不需要手动安装。

### Secrets

| Secret | 说明 |
|---|---|
| `SIGNING_KEY` | keystore 的 base64（`base64 -w0 trime2-100y.keystore`） |
| `KEY_STORE_PASSWORD` | keystore 密码 |
| `ALIAS` | 签名别名（本仓库为 `trime2`） |
| `KEY_PASSWORD` | key 密码 |

workflow 优先使用仓库内的 `signing/trime2-100y.keystore`；不存在时才从 `SIGNING_KEY` 解码。两者选一即可，**推荐只用 secret**，私钥不进 git。

若 Secrets 配了但仍报权限错误，检查：Settings → Actions → General → Workflow permissions 是否为 **Read and write**（发布 Release 需要）。

---

## 六、本地编译（可选）

```bash
export ANDROID_HOME=<你的 SDK 路径>
./gradlew :app:assembleRelease
```

产物：`app/build/outputs/apk/release/*.apk`

签名依赖 `gradle.properties` 中的四个字段：

```properties
signKeyFile=/绝对路径/trime2-100y.keystore
signKeyStorePwd=***
signKeyAlias=trime2
signKeyPwd=***
```

本地编译若要复现 CI 的状态，需要先按「第四节」把补丁全部应用，并确保 `git submodule update --init --recursive` 已完成。

---

## 七、常见问题

| 现象 | 原因 / 解决 |
|---|---|
| 安装报「签名不一致」 | 与上游/旧版签名不同，必须卸载重装，先备份数据 |
| `call to undeclared function 'fseeko'` | 缺 `05-file-offset-compat.patch` |
| `Failed to find package 'tools'` | 误用了 `setup-android` action，本 workflow 已移除 |
| `sdkmanager: command not found` | 未用绝对路径定位，见 workflow 中 `SDKMANAGER=$(ls ...)` |
| `Font ... has already been added` | fonts.xml 中同一字体重复列出，`02` 补丁已做去重 |
| Release 链接 404 | tag 名是 `patched-latest`（注意拼写）；私有仓库未登录也 404 |
| artifact 下载要登录 | artifacts 需登录且有仓库权限，Release 资产在公开仓库可直接下载 |
| 补丁应用失败红叉 | 上游改了同一段代码，按「第四节第 7 点」重新生成补丁 |
| schedule 任务没跑 | GitHub 定时任务高峰期会延迟或跳过，手动触发一次即可 |

---

## 八、目录结构

```
.github/workflows/build-patched.yml   # CI 流程
patches/                              # 补丁集合（按文件名顺序应用）
  01-voice-asr.patch
  02-font-system-first.patch
  03-clipboard-broadcast.patch
  04-http-stream.patch
  05-file-offset-compat.patch
signing/trime2-100y.keystore          # 可选，已用 secret 时可删
README.md
```

---

## 许可

上游代码遵循 GPL-3.0-or-later，本仓库的补丁同样适用。构建产物仅供个人使用。

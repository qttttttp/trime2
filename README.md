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

## 二、⚠️ 签名不同，必须卸载重装

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

处理方式很简单：**卸载旧版，直接安装新包**。反过来，本仓库的包也不能覆盖安装到官方版之上。

### 确认签名是否正确

安装前可核对指纹，输出应与下面一致：

```bash
apksigner verify --print-certs com.nirenr.trime-0.8.5-arm64-v8a-release.apk
```

```
SHA-256: 42:C0:18:B9:FD:B6:01:DC:73:7D:1D:C8:5E:2C:A7:40:E0:99:28:A1:E4:0C:7E:B7:E3:19:D7:40:46:E2:E1:4B
```

证书信息：`CN=Trime2, OU=Dev, O=Dev, L=Beijing, ST=Beijing, C=CN`，有效期至 2126 年。CI 构建的最后一步也会打印这个指纹，两者一致即说明签名生效。

---

## 三、补丁清单

每个补丁只描述**相对上游源码**做了什么。补丁按**文件名字典序**依次应用，两位数字前缀决定顺序；后应用的补丁基于「前面已应用」的文件状态生成，顺序不能随意打乱。

| 补丁 | 改动文件 | 相对源码的改动 |
|---|---|---|
| `01-voice-asr.patch` | `Speech.java`<br>`AiClient.java`<br>`VoiceInputDialog.java`<br>`TrimeService.java`<br>`ThemeManager.java`<br>`AndroidManifest.xml`<br>`themes/default/main.lua` | 源码只有系统 `SpeechRecognizer` 一条识别链路。此补丁：① 新增 `AiClient.transcribeAudio()`，以 multipart 上传 WAV 到 OpenAI 兼容的 `/v1/audio/transcriptions`；② 新增 `looksLikeAsr()`，按模型名（`sensevoice`/`whisper`/`paraformer`/`asr`）自动分流到转写接口，其余仍走 chat；③ `asr_config` 新增可选 `api` 字段，可强制指定接口；④ 语音输入采用「长按说话、松手上屏」；⑤ `ThemeManager` 读取新配置项，`main.lua` 增加对应默认值 |
| `02-font-system-first.patch` | `theme/Style.java` | 源码的 `getFont()` 只支持单个字体文件或 Android 10+ 的多字体集合（自定义字体在前、系统兜底在后）。此补丁：`font` 表支持 `"system"` 占位符，构建 `CustomFallbackBuilder` 原生逐字形回退链时，把从 `/system/etc/fonts.xml` 解析出的系统字体放到该位置——即「系统字体优先，系统缺字再落到后面的字体」。占位符可在任意位置、可多次出现；解析时按文件名去重（同一字体被列多次会触发 `already been added` 异常）；解析失败时退回 `setSystemFallback("sans-serif")` |
| `03-clipboard-broadcast.patch` | `TrimeService.java` | 源码在剪贴板内容变化后仅写入内部记录，不对外通知。此补丁在写入后额外发送本地广播 `com.trime2.CLIP_CHANGED`（`setPackage` 限定本应用，**不携带文本**，避免大文本跨 Binder 拷贝或超限），供 Lua 脚本监听 |
| `04-http-stream.patch` | `androlua/Http.java` | 源码的 `Http` 只支持把请求体作为字符串发送，上传文件必须整份读入内存。此补丁新增 `Http.putFile(url, path, header, callback)`（WebDAV PUT），`HttpTask` 增加 streaming 分支：`setFixedLengthStreamingMode` + 64KB 缓冲边读边写，内存占用与文件大小无关，且不经过 `LuaString → Java String` 的 UTF-8 往返，二进制安全 |
| `05-file-offset-compat.patch` | `app/src/main/jni/CMakeLists.txt` | 源码未定义 `_FILE_OFFSET_BITS`，Lua 子模块的 `lprefix.h` 会自动定义为 64；在 32 位 ABI + `minSdk 21` 下，`fseeko`/`ftello` 的声明被 bionic 的 API 24 可用性守卫隐藏，`liolib.c` 报 `call to undeclared function 'fseeko'`。此补丁加一行 `add_compile_definitions(_FILE_OFFSET_BITS=0)`，使所有文件使用普通 `off_t`，32/64 位均可编译 |

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

直接编辑源码，不要先打旧补丁。若要基于某个已有补丁继续改，先 `git apply patches/0X-xxx.patch` 再动手，否则生成的 diff 会重复包含旧内容。

### 3. 生成补丁

```bash
git diff -- app/src/main/java/com/osfans/trime/Speech.java > patches/06-my-feature.patch
```

- **路径必须相对仓库根目录**（`app/src/...`），CI 里用的是 `git apply -p1`
- 一次提交涉及多个文件时可一次性导出：
  ```bash
  git diff -- app/src/main/java/... app/src/main/res/... > patches/06-my-feature.patch
  ```
- 新增文件需先 `git add -N <file>`，否则不会出现在 `git diff` 里

### 4. 自测能否干净应用

```bash
git stash
git checkout -- .
for p in patches/*.patch; do git apply --check "$p" || echo "FAIL: $p"; done
```

`--check` 只试应用不落盘，全部通过再提交。

### 5. 命名规则

- 格式：`<两位序号>-<英文小写短横线描述>.patch`
- **用英文名**，中文名在部分 zip 解压/编码环境下会乱码，导致 `git apply` 找不到文件
- 序号决定顺序；新补丁若依赖已有补丁的代码，序号必须**大于**被依赖的那个
- 临时停用某个补丁：改名成 `xxx.patch.disabled` 或删掉即可，不用改 workflow

### 6. 提交并触发构建

```bash
git add patches/06-my-feature.patch
git commit -m "feat: 新增 xxx 补丁"
git push
```

workflow 监听 `patches/**`，push 后自动触发；也可手动 `gh workflow run build-patched.yml`。

### 7. 上游改动导致冲突

workflow 的应用逻辑三级兜底：`git apply -v` → `git apply --3way` → `patch -p1 --fuzz=3 --forward`。三级都失败则构建中断，说明上游改了同一段代码，需人工处理：

```bash
git fetch upstream develop && git reset --hard upstream/develop
git apply --reject patches/06-my-feature.patch   # 生成 .rej 文件
# 手工合并 .rej 内容后重新生成补丁
git diff -- <改动的文件> > patches/06-my-feature.patch
```

---

## 五、本次构建遇到的问题

首次从零搭建这套 CI 时踩到的坑，按出现顺序记录。如果你从别处 fork 复现，大概率会撞上同样的几个。

| 序号 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 1 | `Failed to find package 'tools'`，`android-actions/setup-android@v3` 以退出码 1 失败 | 该 action 内部会执行 `sdkmanager tools`，而新 runner 镜像的 cmdline-tools 16.0 已移除遗留的 `tools` 包 | 删掉整个 action。runner 镜像本身已预装 Android SDK，`ANDROID_HOME` 默认可用 |
| 2 | 删掉 action 后 `sdkmanager: command not found`，重试 3 次全失败 | 该 action 的另一项工作是把 sdkmanager 加入 PATH，删掉后 PATH 里没有；且镜像目录名是版本号 `16.0` 而非 `latest`，不能写死 | 不依赖 PATH，用 `ls "$ANDROID_HOME"/cmdline-tools/*/bin/sdkmanager \| sort -V \| tail -1` 自动定位绝对路径 |
| 3 | Gradle 配置阶段失败，报 git 相关错误 | 构建脚本会读取 `git config user.name` / remote，CI 环境默认未配置 | checkout 后显式 `git config --global user.name/user.email`，并 `--add safe.directory` |
| 4 | `git submodule update` 卡住或要求公钥 | 子模块声明的是 SSH URL（`git@github.com:`） | `git config --global url."https://github.com/".insteadOf "git@github.com:"` 强制走 HTTPS |
| 5 | native 编译失败：`liolib.c:706: error: call to undeclared function 'fseeko'` | Lua 的 `lprefix.h` 自动定义 `_FILE_OFFSET_BITS=64`，32 位 ABI + `minSdk 21` 下 64 位偏移版 `fseeko` 的声明被 bionic 的 API 24 守卫隐藏 | 新增 `05-file-offset-compat.patch`，全局 `add_compile_definitions(_FILE_OFFSET_BITS=0)` |
| 6 | `原生回退链构建失败: IllegalArgumentException: Font {...} has already been added` | 测试机 ROM 的 `fonts.xml` 把 `MiSansVF_Overlay.ttf` 按多个字重重复列出，`FontFamily.Builder` 拒绝重复添加 | 解析时用 `LinkedHashSet` 去重，`addFont` 逐个 try-catch 跳过重复项（已并入 `02` 补丁） |
| 7 | 主题 font 表首位加了 `"system"` 但完全没效果 | 链构建在异常处中断，静默退回了原逻辑，没有日志难以定位 | 临时加 `Log.d("TrimeFont", ...)` 逐环节打印，确认是第 6 条的重名异常；问题定位后日志已移除 |
| 8 | Release 链接 404 | ① 当时跑的是旧 workflow 快照，没有发布步骤；② tag 名拼写错误（`patched-last` ≠ `patched-latest`） | 确认提交新 workflow 后手动触发；核对 tag 拼写 |
| 9 | artifact 下载链接 404 | GitHub 的 artifact 端点是带权限校验的私有地址，未登录或换账号访问一律 404 | artifact 只能登录后从 Actions 页面下载；因此新增 rolling Release（公开仓库资产无需登录） |

---

## 六、其他 GitHub 用户如何复现这套构建

### 1. Fork 本仓库

在 GitHub 页面点 **Fork**，或者用命令行 clone 后再关联：

```bash
git clone https://github.com/<你>/trime2.git
cd trime2
```

### 2. 启用 Actions

fork 出来的仓库 **Actions 默认是禁用的**。进入 `Actions` 标签页，点「I understand my workflows, go ahead and enable them」。

顺便把上游自带的 `commit-ci.yml` / `pull-request-ci.yml` 禁用掉（列表里选中 → `···` → Disable workflow），否则每次 push 会额外跑三平台矩阵，浪费额度。

### 3. 换成自己的签名

**不要用本仓库的密钥**。自己生成一个：

```bash
keytool -genkeypair -v -keystore my.keystore -alias mykey \
  -keyalg RSA -keysize 2048 -validity 36500 \
  -storepass <密码> -keypass <密码> \
  -dname "CN=Trime, OU=Dev, O=Dev, L=City, ST=Province, C=CN"
```

导出 base64 供 Secrets 使用：

```bash
base64 -w0 my.keystore
```

### 4. 配置 Secrets

仓库 → Settings → Secrets and variables → Actions → New repository secret，逐个添加：

| Secret | 值 |
|---|---|
| `SIGNING_KEY` | 上一步输出的 base64 字符串（一整行） |
| `KEY_STORE_PASSWORD` | keystore 密码 |
| `ALIAS` | 别名（如 `mykey`） |
| `KEY_PASSWORD` | key 密码 |

然后把仓库里的 `signing/` 删掉（私钥不进 git）：

```bash
git rm -r signing/ && git commit -m "chore: 签名改用 secret" && git push
```

### 5. 修改上游地址（如需跟随别处）

`.github/workflows/build-patched.yml` 顶部：

```yaml
env:
  UPSTREAM_REPO: nirenr/trime2      # 改成你要跟随的仓库
  UPSTREAM_REF: develop             # 或 master / main / 某个 tag
```

### 6. 确认写权限

Settings → Actions → General → Workflow permissions 选 **Read and write**，否则发布 Release 会 403。

### 7. 触发首次构建

```bash
gh workflow run build-patched.yml
```

或网页 Actions → Build Patched → Run workflow。首次没有 JNI 缓存，native 全量编译约 30–40 分钟。

### 8. 验证产物

构建结束后访问 `https://github.com/<你>/trime2/releases/tag/patched-latest`。这个 tag 名是 workflow 里写死的固定值，**每个 fork 往自己仓库发同名 tag**，互不干扰。

### 9. 自定义调整

| 想改什么 | 改哪里 |
|---|---|
| 构建哪些 ABI | `app/build.gradle.kts` 的 `abiFilters`（建议写成补丁，否则下次同步上游会丢） |
| Release 说明文字 | workflow 中 `发布到 patched-latest` 步骤的 `body:` 字段 |
| 定时频率 | workflow 顶部 `cron`（默认每天 UTC 18:00） |
| 用哪个密钥 | 第 3、4 步 |

---

## 七、workflow 说明

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

- **以纯上游为基线**：`git reset --hard FETCH_HEAD` 丢弃 fork 里的所有源码差异，再从 `$GITHUB_SHA` 取回 `patches/`、`signing/`、workflow 三个路径。所以在 fork 里直接改源码**不会**影响构建结果，想改行为只能通过补丁。
- **串行化**：`concurrency: group: build-patched`，避免两次构建同时向 `patched-latest` 上传资产。
- **JNI 缓存**：`app/prebuilt` 按 `calculateNativeCacheHash` 的结果缓存。首次 30–40 分钟，之后命中缓存只需几分钟。
- **NDK 由 Gradle 自动下载**，无需手动安装。

### Secrets

| Secret | 说明 |
|---|---|
| `SIGNING_KEY` | keystore 的 base64（`base64 -w0 trime2-100y.keystore`） |
| `KEY_STORE_PASSWORD` | keystore 密码 |
| `ALIAS` | 签名别名（本仓库为 `trime2`） |
| `KEY_PASSWORD` | key 密码 |

workflow 优先使用仓库内的 `signing/trime2-100y.keystore`；不存在时才从 `SIGNING_KEY` 解码。两者选一，**推荐只用 secret**。

---

## 八、本地编译（可选）

```bash
export ANDROID_HOME=<你的 SDK 路径>
./gradlew :app:assembleRelease
```

产物：`app/build/outputs/apk/release/*.apk`

签名依赖 `gradle.properties` 中四个字段：

```properties
signKeyFile=/绝对路径/trime2-100y.keystore
signKeyStorePwd=***
signKeyAlias=trime2
signKeyPwd=***
```

要复现 CI 的状态，需先按第四节把补丁全部应用，并完成 `git submodule update --init --recursive`。

---

## 九、常见问题

| 现象 | 原因 / 解决 |
|---|---|
| 安装报「签名不一致」 | 与上游/旧版签名不同，卸载重装即可 |
| `call to undeclared function 'fseeko'` | 缺 `05-file-offset-compat.patch` |
| `Failed to find package 'tools'` | 误用 `setup-android` action，本 workflow 已移除 |
| `sdkmanager: command not found` | 未用绝对路径定位，见第五节第 2 条 |
| `Font ... has already been added` | `fonts.xml` 中同一字体重复列出，`02` 补丁已去重 |
| Release 链接 404 | tag 名是 `patched-latest`；私有仓库未登录也 404 |
| artifact 下载要登录 | artifacts 需登录且有仓库权限，Release 资产在公开仓库可直接下载 |
| 补丁应用失败红叉 | 上游改了同一段代码，按第四节第 7 点重新生成补丁 |
| schedule 任务没跑 | GitHub 定时任务高峰期会延迟或跳过，手动触发一次即可 |

---

## 十、目录结构

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

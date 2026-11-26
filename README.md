# trime2 补丁构建（个人 fork）

本仓库 fork 自 [nirenr/trime2](https://github.com/nirenr/trime2)，只做一件事：

> **每天自动拉取上游最新代码 → 应用 `patches/` 下的本地补丁 → 用 `trime2-100y` 密钥签名 → 发布 APK**
>
> 上游没有新提交时自动跳过，不浪费构建次数。

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

补丁按**文件名字典序**依次应用，两位数字前缀决定顺序；后应用的补丁基于「前面已应用」的文件状态生成，顺序不能随意打乱。

| 补丁 | 一句话说明 |
|---|---|
| `01-voice-asr.patch` | 语音识别接入 OpenAI 兼容 API，支持专用转写模型与多模态模型 |
| `02-font-system-first.patch` | 主题 `font` 表支持 `"system"` 占位符，构建系统字体优先的原生回退链 |
| `03-clipboard-broadcast.patch` | 剪贴板内容变化后发送本地广播 `com.trime2.CLIP_CHANGED` |
| `04-http-stream.patch` | 新增 `Http.putFile()`，WebDAV 流式上传任意大小/二进制文件 |
| `05-file-offset-compat.patch` | 编译修复：32 位 ABI 下 native 编不过（见下），无使用示例 |

### 01-voice-asr.patch

改动要点：新增 `AiClient.transcribeAudio()`（multipart 上传 WAV 到 `/v1/audio/transcriptions`）与 `looksLikeAsr()`（按模型名 `sensevoice`/`whisper`/`paraformer`/`asr` 自动分流）；`asr_config` 新增可选 `api` 字段强制指定接口；语音输入改为「长按说话、松手上屏」。

主题 `main.lua` 的写法（以硅基流动为例）：

```lua
-- 1) 专用识别模型(推荐，免费且无时长限制)：自动走 /v1/audio/transcriptions
asr_config = {
    base_url = "https://api.siliconflow.cn/v1",
    model    = "FunAudioLLM/SenseVoiceSmall",  -- 或 Qwen/Qwen3-ASR-1.7B
    key      = "sk-xxxxxxxx",
    api      = "",       -- 留空按模型名自动判断
    prompt   = "",
    system_prompt = "",
    extra_params  = "",
}

-- 2) 多模态理解模型：模型名不含 asr 关键词，自动走 /v1/chat/completions
asr_config = {
    base_url = "https://api.siliconflow.cn/v1",
    model    = "Qwen/Qwen3-Omni-30B-A3B-Instruct",
    key      = "sk-xxxxxxxx",
    api      = "",       -- prompt/system_prompt/extra_params 仅此模式生效
}
```

`api` 字段：留空按模型名自动判断；填 `transcriptions` 强制走专用转写接口；填 `chat` 强制走多模态。

### 02-font-system-first.patch

`theme/Style.java` 的 `getFont()` 原本只支持单字体或多字体集合（自定义在前、系统兜底在后）。此补丁让 `font` 表支持 `"system"` 占位符：构建 `CustomFallbackBuilder` 原生逐字形回退链时，从 `/system/etc/fonts.xml` 解析出的系统字体被放到该位置，即「系统字体优先，系统缺字再落到后面的字体」。占位符可在任意位置、可多次出现；同一字体文件去重，解析失败退回 `setSystemFallback("sans-serif")`。

主题写法：

```lua
font = {
    "system",          -- 系统当前字体，最优先
    "明月HanaMinB.ttf", -- 生僻字兜底
}
```

### 03-clipboard-broadcast.patch

`TrimeService` 在剪贴板内容变化并写入内部记录后，额外发送本地广播 `com.trime2.CLIP_CHANGED`（`setPackage` 限定本应用）。广播**不携带文本**（避免大文本跨 Binder 拷贝或超限），收到后需要内容时自行从系统剪贴板读取。

Lua 侧接收示例（放在键盘脚本顶层，如 `scripts/` 下被按键绑定的 `.lua`）：

```lua
import "android.content.IntentFilter"
import "android.content.Context"

local ACTION = "com.trime2.CLIP_CHANGED"
-- BroadcastReceiver 是抽象类,必须用 luajava.override 继承,不能 newInstance
local Cls = luajava.override(
    luajava.bindClass("android.content.BroadcastReceiver"),
    {
        onReceive = function(super, context, intent)
            if intent.getAction() == ACTION then
                -- 广播不带文本,从系统剪贴板取
                local text = service.getSystemService(Context.CLIPBOARD_SERVICE).getText()
                print("剪贴板已变化: " .. tostring(text))
            end
        end,
    })
local receiver = Cls()
this.registerReceiver(receiver, IntentFilter(ACTION))

-- 键盘关闭/切换走时注销,避免重复注册:
-- this.unregisterReceiver(receiver)
```

> 本工程 `LUA_JAVA_OO = true`：Java 对象方法一律用**点号**调用（`intent.getAction()`），冒号仅用于 Lua 自身对象（如 `io` 句柄）。

### 04-http-stream.patch

`Http.putFile(url, path, header, callback)`：把本地文件以 WebDAV PUT 流式上传。`setFixedLengthStreamingMode` + 64KB 缓冲边读边写，内存占用与文件大小无关；不经过 `LuaString → Java String` 的 UTF-8 往返，二进制安全。

最小示例：

```lua
import "com.androlua.Http"
import "java.util.HashMap"

local header = HashMap()
header.put("Authorization", "Basic " .. base64(user .. ":" .. pass)) -- Base64 自行实现或用库
header.put("Content-Type", "application/octet-stream")

Http.putFile(
    "https://dav.example.com/dav/backup.zip",  -- 目标 URL
    "/sdcard/Documents/rime/backup.zip",       -- 本地文件路径(只传路径,不读入内存)
    header,
    function(code, body, cookie, hs)           -- UI 线程回调,与 Http.put 一致
        if code == 200 or code == 201 or code == 204 then
            print("上传成功")
        else
            print("上传失败 HTTP " .. tostring(code))
        end
    end)
```

完整可用的 WebDAV 上传脚本见本仓库外置脚本 `webdav_upload_stream.lua`（含 Base64 认证、URL 编码、错误码提示）。

### 05-file-offset-compat.patch

纯编译修复，无运行时用法：`add_compile_definitions(_FILE_OFFSET_BITS=0)`，绕开 bionic 在 32 位 + `minSdk 21` 下对 `fseeko`/`ftello` 声明的 API 24 守卫。

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
| 10 | CMake 大量 `Deprecation Warning` / `nested namespace is a C++17 extension` | snappy、leveldb、OpenCC、marisa-trie 等第三方依赖写法老旧，属警告非错误 | 不处理。不要修改子模块代码，否则 `submodule update` 时丢失 |
| 11 | Release 资产下载计数比预期多 | GitHub 的 `download_count` 按请求计数，Range 分段请求、断点续传、镜像预取都会各记一次，且不提供明细日志 | 无解也无影响，该数字仅作展示 |

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
| 关闭上游变化检测 | 删除 `check` job，并去掉 `build` 的 `needs` 与 `if` 两行，即可恢复每次必构建 |
| 用哪个密钥 | 第 3、4 步 |

---

## 七、workflow 说明

文件：`.github/workflows/build-patched.yml`

### 触发方式

| 方式 | 条件 |
|---|---|
| 定时 | 每天 UTC 18:00（北京时间 02:00）自动跟随上游；上游提交与上次构建一致则跳过 |
| push | 改动 `patches/**`、`signing/**` 或 workflow 自身 |
| 手动 | `workflow_dispatch`，可指定上游分支/标签（默认 `develop`），**总是构建** |

### 主要步骤

```
check（比对上游 HEAD 与 patched-latest 记录的上游 SHA，仅定时触发时可能跳过）
→ Checkout → 配置 git 身份 → 拉上游并 reset 为基线 → 恢复 patches/signing/workflow
→ 应用补丁 → Setup Java 17 → 安装 SDK 组件（cmake）
→ 配置签名与 gradle.properties → 拉子模块 → JNI 缓存
→ assembleRelease → 校验签名 → 上传 artifact → 发布到 patched-latest
```

### 关键设计

- **以纯上游为基线**：`git reset --hard FETCH_HEAD` 丢弃 fork 里的所有源码差异，再从 `$GITHUB_SHA` 取回 `patches/`、`signing/`、workflow 三个路径。所以在 fork 里直接改源码**不会**影响构建结果，想改行为只能通过补丁。
- **上游变化检测**：定时触发时 `check` job 先用 `git ls-remote` 取上游 HEAD，再读取 `patched-latest` Release 说明里的 `upstream-sha:` 字段比对。相同则 `build` job 直接跳过，本次运行显示为成功但不产生构建；不同或首次运行则正常构建。手动触发与 push 不参与比对，永远构建。
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
| 定时任务显示成功但没出包 | 上游提交与 `patched-latest` 记录一致，被自动跳过；需要强制构建用 `workflow_dispatch` |
| 定时任务连续两个月不触发 | 仓库 60 天无活动时 GitHub 会自动禁用 schedule，到 Actions 页面点 Enable 恢复 |

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

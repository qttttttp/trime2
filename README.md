<!--
SPDX-FileCopyrightText: 2015 - 2024 Rime community
SPDX-FileCopyrightText: 2026 trime2 patch contributors
SPDX-License-Identifier: GPL-3.0-or-later

本仓库全部内容，包括补丁、Lua 工具脚本和内置工具，均按 GPL-3.0-or-later 提供。
上游许可证全文见仓库根目录 LICENSE。
-->

# trime2 补丁版

补丁都在 `patches/`，按编号顺序打；内置工具单独放 `builtin-tools/`，由 16 号补丁接入。GitHub Actions 负责构建和发布。

## 补丁清单

| 编号 | 文件 | 改动 |
|---|---|---|
| 01 | `01-voice-asr.patch` | 语音/ASR：Manifest、主题 main.lua、AiClient、Speech、VoiceInputDialog、TrimeService；mlkit 调用、异常保护 |
| 02 | `02-font-system-first.patch` | 字体优先取系统字体：`theme/Style.java` |
| 03 | `03-clipboard-broadcast.patch` | 剪贴板变化后发本地广播 `com.trime2.CLIP_CHANGED`（不携带文本） |
| 04 | `04-http-stream.patch` | `androlua/Http.java` 流式读取 |
| 05 | `05-file-offset-compat.patch` | `jni/CMakeLists.txt` 的 `off_t` 兼容 |
| 06 | `06-mlkit-offline.patch` | MLKit 离线识别：`build.gradle.kts`、`proguard-rules.pro`、新增 `MlkitModelInstaller.java` |
| 07 | `07-boost-vmd.patch` | `jni/cmake/Boost.cmake` 关闭 VMD |
| 08 | `08-opencc-missing-dict.patch` | `OpenCCDataPlugin.kt` 缺词典时跳过 |
| 09 | `09-runtime-property.patch` | 字符串属性通道：`Rime.java`、`RimeApi.java`、`rime_jni.cc` |
| 10 | `10-ThemeDataBridge-newfile.patch` | 新增 `theme/ThemeDataBridge.java`，只读导出键盘与主题结构 |
| 11 | `11-ThemeManager.patch` | `ThemeManager.getColor()`，供主题工作室读配色表 |
| 12 | `12-InputView.patch` | `InputView` 保存当前键盘 Globals 快照 |
| 13 | `13-TrimeService.patch` | `TrimeService` 保存当前 RootView 快照 |
| 14 | `14-KeyboardDefaultFix.patch` | 键盘修复：`Config` 只读偏好、`KeyboardDialog` 不执行键盘脚本、`InputView` 解析失败保持原键盘、`ThemeManager` 按 id 读偏好 |
| 15 | `15-SnapshotSync.patch` | 键位快照与当前实际显示的键盘同步 |
| 16 | `16-builtin-tools.patch` | 内置工具接入：Manifest 加 `REQUEST_INSTALL_PACKAGES`，`ToolActivity` 调 `ensureInstalled` |
| 17 | `17-KeyClinitGuard.patch` | `ThemeManager.getPresetKeys()` 空表兜底，防止 Key 静态初始化崩溃 |
| 18 | `18-RecentToolsBar.patch` | 设置页加「最近使用工具」快捷栏 |
| 19 | `19-KeyClinitNoLua.patch` | Key 静态初始化去掉 Lua 依赖，防止启动崩溃 |
| 20 | `20-RimeStartupStatusGuard.patch` | Rime 启动时状态发布保护 |

应用顺序：

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11 → 12 → 13 → 14 → 15 → 16 → 17 → 18 → 19 → 20
```

`gradle/wrapper/gradle-wrapper.properties`、`app/data/`、`app/libs/*.aar`、`jni/` 下的子模块源码都不在补丁里，自己按环境配。

## 功能

### 内置工具

随 APK 打包，打开「工具」时装到 `Documents/rime/tools/`：

| 工具 | 资源目录 | 安装名称 | 功能 |
|---|---|---|---|
| 主题工作室 | `theme-studio` | 主题工作室 | 改主题配色、样式、键盘布局并实时预览，可桥接真机键盘结构复刻预览 |
| 一键更新 | `yijian-update` | 一键更新 | 检查并下载安装最新 APK |

工具放在 `builtin-tools/app/src/main/assets/tools/`，根级有 `main.lua` 就算一个工具。`manifest.txt` 写「资源目录|安装名称」的对应关系。首次打开全量写入并生成 `.builtin` 指纹，升级时只覆盖用户没动过的文件，改过的另存为 `<文件名>.new`。安装器 `BuiltinTools.java` 会自动发现 `assets/tools/*` 下的新目录，加工具不用改补丁和 workflow。安装权限走 `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 引导，安装用 `DownloadManager` 的 `content://` URI，回退 `FileProvider`。

### 构建

`.github/workflows/build-patched.yml` 一条链跑完：拉上游 → 应用 `patches/*.patch` → 复制 `builtin-tools` → 自检 → 签名编译 → 发布 `patched-latest`，同时归档源码快照。`patches/`、`builtin-tools/`、workflow、`README.md` 任一变更都会触发。

## 复刻要点

- `patches/`、`builtin-tools/`、`.github/workflows/build-patched.yml`、`README.md` 要一起覆盖，少一个自检就可能失败。
- 打补丁用 `patch -p1 --fuzz=3 --no-backup-if-mismatch --forward`。别用 `git apply --3way`，浅克隆缺 blob 会直接失败；fuzz 命中会生成 `.orig`，不关备份会被干净检查拦下来。已应用过的补丁靠 `--forward` 跳过。
- 06、10 带新文件，重复应用靠 `--forward` 跳过。16 只保留接入改动，工具文件只能放 `builtin-tools/app/src/main/assets/tools/`，塞回补丁会被自检挡掉。
- workflow 里每个补丁都有标志物检查。改动补丁名或内容时，把对应标志物一起更新，否则旧标签会误杀构建。
- 新加工具只要往 `assets/tools/` 放目录、在 `manifest.txt` 加一行，不用动补丁和 workflow。
- `gradle-wrapper.properties` 里的本地路径不进补丁，换台机器自己改回官方地址或本地缓存。
- 上游大版本升级后，先查 18（设置页改版时动过）、01、12、14 这几个，再整链跑一遍看有没有 `.rej/.orig`。

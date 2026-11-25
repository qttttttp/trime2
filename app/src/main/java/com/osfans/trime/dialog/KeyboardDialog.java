/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.dialog;

import android.app.AlertDialog;
import android.content.Context;
import android.os.IBinder;
import android.text.TextUtils;
import android.view.Window;
import android.view.WindowManager;

import com.osfans.trime.BuildConfig;
import com.osfans.trime.Config;
import com.osfans.trime.TrimeService;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.lib.ResourceFinder;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class KeyboardDialog implements ResourceFinder {
    private final AlertDialog mDialog;
    private IBinder mWindowToken;

    @Override
    public InputStream findResource(String name) {
        if (TextUtils.isEmpty(name))
            return null;
        try {
            if (new File(name).exists())
                return new FileInputStream(name);
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        try {
            return new FileInputStream(new File(Config.getKeyboardDir(), name));
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        return null;
    }

    @Override
    public String findFile(String filename) {
        if (TextUtils.isEmpty(filename))
            return null;
        if (filename.startsWith("/"))
            return filename;
        return new File(Config.getKeyboardDir(), filename).getAbsolutePath();
    }

    /**
     * 内部辅助类：用于绑定样式ID和解析出的显示名称
     */
    private static class KeyboardItem {
        String id;
        String displayName;

        KeyboardItem(String id, String displayName) {
            this.id = id;
            this.displayName = displayName;
        }
    }

    public KeyboardDialog(Context context) {
        AlertDialog.Builder builder =
                new AlertDialog.Builder(context, ThemeManager.getDialogTheme())
                        .setTitle("选择默认键盘")
                        //setPositiveButton(
                        //       "主题",
                        //       (dialog, id) -> new ThemeDialog(context).show(mWindowToken))
                        .setNegativeButton(android.R.string.cancel, null);

        if (Config.currentSchema().isEmpty()) {
            builder.setMessage("请先正确配置");
        } else {
            // 1. 获取当前选中的 ID 和所有样式文件夹名
            //    这里必须用「纯读」版本：无参 Config.getKeyboard() 旧实现会回写偏好，
            //    只打开对话框、什么都不选，也会改掉共享数据。
            //    偏好里存的就是当前实际键盘（手选值或 auto 解析后的值），直接回显。
            String dialogSchema = Config.currentSchema();
            String currentKeyboardId = Config.getKeyboard(dialogSchema);
            String[] rawKeyboardIds = Config.getKeyboards();

            // 2. 只读文本取名称，绝不执行键盘脚本。
            //    旧实现为了拿 name 会把 keyboards/ 下每个 .lua 执行一遍
            //    (loadfilex + call)，脚本里「初始化完成后挂上去」的运行时行为
            //    （部分按键的滑动接管等）会落到正在使用的输入法上：
            //    打开一次默认键盘，按键就只剩点击、滑动全部失效。
            List<KeyboardItem> KeyboardItems = new ArrayList<>();
            for (String id : rawKeyboardIds) {
                id = id.replace(".lua", "");
                String displayName = readKeyboardName(id, false);
                if (TextUtils.isEmpty(displayName))
                    continue;
                KeyboardItems.add(new KeyboardItem(id, displayName));
            }
            if (KeyboardItems.isEmpty()) {
                // 没有 lock = true 的键盘时退化为全部列出，别让列表只剩「自动匹配」
                for (String id : rawKeyboardIds) {
                    id = id.replace(".lua", "");
                    KeyboardItems.add(new KeyboardItem(id, readKeyboardName(id, true)));
                }
            }

            // 4. 【核心】按显示名称进行本地化排序
            Collections.sort(KeyboardItems, new Comparator<KeyboardItem>() {
                private final OptionsDialog.LocaleComparator localeComp = new OptionsDialog.LocaleComparator();

                @Override
                public int compare(KeyboardItem s1, KeyboardItem s2) {
                    // 1. 首先比较显示名称
                    int nameComparison = localeComp.compare(s1.displayName, s2.displayName);
                    // 2. 如果显示名称相同，则按 ID 字符串排序
                    if (nameComparison == 0) {
                        // ID 通常是英文/数字文件夹名，直接用 String 的 compareTo 即可
                        return localeComp.compare(s1.id, s2.id);
                    }

                    return nameComparison;
                }
            });
            KeyboardItems.add(0,new KeyboardItem("","自动匹配"));
            // 5. 拆分排序后的数据供 Dialog 使用
            int size = KeyboardItems.size();
            String[] sortedNames = new String[size];
            String[] sortedIds = new String[size];
            int currentSelectedIndex = 0;

            for (int i = 0; i < size; i++) {
                KeyboardItem item = KeyboardItems.get(i);
                sortedNames[i] = item.displayName;
                sortedIds[i] = item.id;
                // 重新匹配当前选中的索引位置
                if (item.id.equals(currentKeyboardId)) {
                    currentSelectedIndex = i;
                }
            }

            builder.setSingleChoiceItems(
                    sortedNames,
                    currentSelectedIndex,
                    (dialog, index) -> {
                        dialog.dismiss();
                        String selectedId = sortedIds[index];
                        TrimeService trime = TrimeService.getInstance();
                        if (TextUtils.isEmpty(selectedId)) {
                            // 自动匹配：先清空偏好，再让输入法按「方案同名 → 主题」重算并写回
                            Config.clearKeyboard(dialogSchema);
                            if (trime != null)
                                trime.setKeyboard(".reload");
                        } else {
                            // 手选：写偏好
                            Config.setKeyboard(selectedId);
                            if (trime != null)
                                trime.setKeyboard(selectedId);
                        }
                    });
        }
        mDialog = builder.create();
    }

    /** 键盘脚本里能读到的元信息（文本解析，不执行脚本） */
    private static final class LuaMeta {
        String name;
        boolean lock;
        boolean hasLock;
    }

    /**
     * 从键盘脚本里读 name / lock，只做文本解析，不执行脚本。
     *
     * @param ignoreLock true 时不看 lock，直接给名字（列表为空时的兜底）
     * @return 显示名（带 id），不该出现在列表里时返回 null
     */
    private String readKeyboardName(String keyboardId, boolean ignoreLock) {
        String dir = Config.getKeyboardDir();
        LuaMeta meta = readMeta(new File(Config.getKeyboardPath(keyboardId)), new File(dir),
                new HashSet<String>(), 0);
        if (meta == null) return keyboardId;
        if (!ignoreLock && !(meta.hasLock && meta.lock)) return null;
        String name = TextUtils.isEmpty(meta.name) ? keyboardId : meta.name;
        return name + " (" + keyboardId + ")";
    }

    /**
     * 读一个键盘脚本的 name / lock，并跟着 require 一路往下找。
     *
     * 键盘之间常常是复用的：某个键盘在自己的文件里只写「在 qwerty36 的基础上改几个键」，
     * name / lock（尤其是 lock = true）留在被 require 的文件里。只读自己这一份，
     * 这类键盘就会被当成「没有 lock」而整个从列表里消失。
     * 这里按文本跟进 require 链，缺什么补什么；自己显式写了的以自己为准。
     */
    private static LuaMeta readMeta(File file, File dir, Set<String> seen, int depth) {
        if (file == null || depth > 6) return null;
        String key;
        try {
            key = file.getCanonicalPath();
        } catch (Exception e) {
            key = file.getAbsolutePath();
        }
        if (!seen.add(key)) return null; // require 成环

        LuaMeta meta = new LuaMeta();
        List<String> requires = new ArrayList<>();
        StringBuilder src = new StringBuilder();
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            String line;
            while ((line = reader.readLine()) != null) src.append(line).append('\n');
        } catch (Exception e) {
            return depth == 0 ? null : meta;
        } finally {
            if (reader != null) {
                try {
                    reader.close();
                } catch (Exception ignored) {
                }
            }
        }

        // 【兼容上游编辑器 5025587b】编辑器把改动写进同名 .custom.lua sidecar
        // （LuaPatchManager.file()）。上游原本在执行脚本后 applyFile 让补丁里的 name/lock
        // 生效；这里不执行脚本，改为把 sidecar 当文本读进来，用同一套解析覆盖 name/lock。
        // 这样「编辑器改过显示名的键盘」在选择列表里仍显示新名字，同时不触发脚本执行的
        // 副作用（那正是本补丁要修的滑动失效问题）。sidecar 里的复杂 Lua 只当文本看，
        // 解析不到就忽略，绝不影响主文件。
        File side = sidecarOf(file);
        if (side != null && side.isFile()) {
            BufferedReader sr = null;
            try {
                sr = new BufferedReader(new InputStreamReader(new FileInputStream(side), "UTF-8"));
                String line;
                while ((line = sr.readLine()) != null) src.append(line).append('\n');
            } catch (Exception ignored) {
            } finally {
                if (sr != null) {
                    try { sr.close(); } catch (Exception ignored) {}
                }
            }
        }

        // 先整份去掉注释（含 --[[ ... ]] / --[==[ ... ]==] 块注释），再逐行看字段。
        // 块注释按行处理不了，里面出现的 name = "示例" / lock = true 会被当成真字段，
        // 让不该进列表的键盘混进来，或让真字段被注释里的值覆盖。
        for (String line : stripLuaComments(src.toString()).split("\n", -1)) {
            String text = stripComment(line).trim();
            if (text.isEmpty()) continue;
            if (meta.name == null) {
                String v = luaValue(text, "name");
                if (v != null) meta.name = v;
            }
            if (!meta.hasLock) {
                Boolean v = luaBool(text, "lock");
                if (v != null) {
                    meta.hasLock = true;
                    meta.lock = v;
                }
            }
            collectRequires(text, requires);
        }

        for (String r : requires) {
            if (meta.name != null && meta.hasLock) break;
            LuaMeta parent = readMeta(resolveKeyboardFile(dir, r), dir, seen, depth + 1);
            if (parent == null) continue;
            if (meta.name == null) meta.name = parent.name;
            if (!meta.hasLock && parent.hasLock) {
                meta.hasLock = true;
                meta.lock = parent.lock;
            }
        }
        return meta;
    }

    /** 主键盘脚本对应的编辑器 sidecar: qwerty36.lua -> qwerty36.custom.lua */
    private static File sidecarOf(File base) {
        if (base == null) return null;
        String n = base.getName();
        if (!n.endsWith(".lua") || n.endsWith(".custom.lua")) return null;
        return new File(base.getParentFile(), n.substring(0, n.length() - 4) + ".custom.lua");
    }

    /** require 里的名字 -> 实际文件；兼容 "x"、"x.lua"、"keyboards/x" 三种写法 */
    private static File resolveKeyboardFile(File dir, String name) {
        if (TextUtils.isEmpty(name)) return null;
        String[] candidates = name.endsWith(".lua")
                ? new String[]{name}
                : new String[]{name, name + ".lua"};
        for (String c : candidates) {
            File f = new File(c);
            if (f.isAbsolute()) {
                if (f.isFile()) return f;
                continue;
            }
            f = new File(dir, c);
            if (f.isFile()) return f;
            if (c.startsWith("keyboards/")) {
                f = new File(dir, c.substring("keyboards/".length()));
                if (f.isFile()) return f;
            }
        }
        return null;
    }

    /** 收集一行的 require 目标：require("x") / require 'x' / require [[x]] */
    private static void collectRequires(String text, List<String> out) {
        int from = 0;
        while (true) {
            int i = text.indexOf("require", from);
            if (i < 0) return;
            from = i + "require".length();
            if (i > 0 && isIdentChar(text.charAt(i - 1))) continue;
            int p = from;
            while (p < text.length() && Character.isWhitespace(text.charAt(p))) p++;
            if (p < text.length() && text.charAt(p) == '(') {
                p++;
                while (p < text.length() && Character.isWhitespace(text.charAt(p))) p++;
            }
            if (p >= text.length()) return;
            char q = text.charAt(p);
            String arg = null;
            if (q == '"' || q == '\'') {
                int end = text.indexOf(q, p + 1);
                if (end > 0) arg = text.substring(p + 1, end);
            } else if (text.startsWith("[[", p)) {
                int end = text.indexOf("]]", p + 2);
                if (end > 0) arg = text.substring(p + 2, end);
            }
            if (arg != null && !arg.isEmpty()) out.add(arg);
        }
    }

    /**
     * 去掉整份脚本里的注释（行注释 + 块注释），字符串与长字符串原样保留。
     * Lua 的块注释是 --[[ ... ]] 或 --[==[ ... ]==]，可以跨行；只按行切是切不掉的。
     */
    private static String stripLuaComments(String src) {
        StringBuilder out = new StringBuilder(src.length());
        int i = 0, n = src.length();
        while (i < n) {
            char c = src.charAt(i);
            if (c == '-' && i + 1 < n && src.charAt(i + 1) == '-') {
                int level = longBracketLevel(src, i + 2);
                if (level >= 0) {                       // --[[ 块注释
                    int end = longBracketEnd(src, level, i + 2);
                    int lines = 0;
                    for (int j = i; j < end && j < n; j++) if (src.charAt(j) == '\n') lines++;
                    i = end;
                    for (int j = 0; j < lines; j++) out.append('\n'); // 保留行号结构
                    continue;
                }
                int e = src.indexOf('\n', i);           // -- 行注释
                i = e < 0 ? n : e;
                continue;
            }
            if (c == '"' || c == '\'') {               // 普通字符串
                int j = i + 1;
                while (j < n) {
                    char d = src.charAt(j);
                    if (d == '\\') {
                        j += 2;
                        continue;
                    }
                    if (d == c || d == '\n') {
                        j++;
                        break;
                    }
                    j++;
                }
                if (j > n) j = n;
                out.append(src, i, j);
                i = j;
                continue;
            }
            if (c == '[') {                             // 长字符串 [[...]] 不参与注释判断
                int level = longBracketLevel(src, i);
                if (level >= 0) {
                    int end = longBracketEnd(src, level, i);
                    out.append(src, i, end);
                    i = end;
                    continue;
                }
            }
            out.append(c);
            i++;
        }
        return out.toString();
    }

    /** `[` + n 个 `=` + `[` 的层级；不是长括号开头返回 -1 */
    private static int longBracketLevel(String src, int from) {
        if (from >= src.length() || src.charAt(from) != '[') return -1;
        int j = from + 1, level = 0;
        while (j < src.length() && src.charAt(j) == '=') {
            level++;
            j++;
        }
        if (j < src.length() && src.charAt(j) == '[') return level;
        return -1;
    }

    /** 长括号结束位置（`]` + n 个 `=` + `]` 之后）；没有结束符就吃到文件尾 */
    private static int longBracketEnd(String src, int level, int from) {
        StringBuilder close = new StringBuilder("]");
        for (int i = 0; i < level; i++) close.append('=');
        close.append(']');
        int idx = src.indexOf(close.toString(), from + level + 2);
        return idx < 0 ? src.length() : idx + close.length();
    }

    /** 去掉行尾注释，注意跳过字符串里的 `--` */
    private static String stripComment(String line) {
        boolean inSingle = false, inDouble = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (inSingle) {
                if (c == '\\') i++;
                else if (c == '\'') inSingle = false;
            } else if (inDouble) {
                if (c == '\\') i++;
                else if (c == '"') inDouble = false;
            } else if (c == '\'') {
                inSingle = true;
            } else if (c == '"') {
                inDouble = true;
            } else if (c == '-' && i + 1 < line.length() && line.charAt(i + 1) == '-') {
                return line.substring(0, i);
            }
        }
        return line;
    }

    /** 取 `key = "..."` / `key = '...'` / `key = [[...]]` / `["key"] = "..."` 的字面量 */
    private static String luaValue(String text, String key) {
        int eq = valueStart(text, key);
        if (eq < 0) return null;
        String rest = text.substring(eq + 1).trim();
        if (rest.startsWith("[[")) {
            int end = rest.indexOf("]]", 2);
            return end < 0 ? null : rest.substring(2, end);
        }
        if (rest.isEmpty()) return null;
        char quote = rest.charAt(0);
        if (quote != '"' && quote != '\'') return null;
        int end = rest.indexOf(quote, 1);
        while (end > 0 && rest.charAt(end - 1) == '\\') {
            end = rest.indexOf(quote, end + 1);
        }
        if (end < 0) return null;
        String value = rest.substring(1, end);
        return value.replace("\\\"", "\"").replace("\\\\", "\\");
    }

    /** 取 `key = true` / `key = false`；没写返回 null（以便由 require 的父键盘补齐） */
    private static Boolean luaBool(String text, String key) {
        int eq = valueStart(text, key);
        if (eq < 0) return null;
        String rest = text.substring(eq + 1).trim().toLowerCase();
        if (rest.startsWith("true")) return Boolean.TRUE;
        if (rest.startsWith("false")) return Boolean.FALSE;
        return null;
    }

    /** 找到 `key =` 里等号的位置；支持 `["key"] =`，避免 `name2`、`base_name` 之类误匹配 */
    private static int valueStart(String text, String key) {
        int from = 0;
        while (true) {
            int i = text.indexOf(key, from);
            if (i < 0) return -1;
            from = i + key.length();
            if (i > 0 && isIdentChar(text.charAt(i - 1))) continue;
            int p = from;
            while (p < text.length()) {
                char c = text.charAt(p);
                if (c == ']' || c == '"' || c == '\'' || Character.isWhitespace(c)) p++;
                else break;
            }
            if (p < text.length() && text.charAt(p) == '='
                    && (p + 1 >= text.length() || text.charAt(p + 1) != '=')) {
                return p;
            }
        }
    }

    private static boolean isIdentChar(char c) {
        return Character.isLetterOrDigit(c) || c == '_';
    }

    public void show() {
        if (mDialog == null) return;
        mDialog.show();
    }

    public void show(IBinder token) {
        if (mDialog == null) return;
        mWindowToken = token;
        if (mWindowToken == null) {
            show();
            return;
        }
        Window win = mDialog.getWindow();
        if (win != null) {
            WindowManager.LayoutParams attr = win.getAttributes();
            attr.type = WindowManager.LayoutParams.TYPE_APPLICATION_ATTACHED_DIALOG;
            win.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
            attr.token = token;
            win.setAttributes(attr);
        }
        mDialog.show();
    }
}


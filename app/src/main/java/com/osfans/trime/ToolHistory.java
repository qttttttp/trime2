/*
 * r27.45：最近使用工具的历史（独立文件，不触碰上游代码）。
 * 历史存在 rime/tools/.recent_tools，每行一个工具目录名（UTF-8）。
 * 只做纯文件读写 + 过滤，不执行任何工具脚本。
 */
package com.osfans.trime;

import android.util.Log;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public final class ToolHistory {

    private static final String TAG = "ToolHistory";
    /** 历史文件名，放在 tools 目录下（隐藏文件，不出现在工具列表里）。 */
    public static final String HISTORY_FILE = ".recent_tools";
    /** 最多保留的历史条数；显示只取前 N 个，多留一些以便过滤后仍有候选。 */
    private static final int MAX_HISTORY = 12;

    private ToolHistory() {
    }

    /**
     * 记录一次工具使用：去重置顶，超过上限截断。
     * name 必须是 tools 下的目录名；含路径分隔符或空串一律忽略（安全）。
     */
    public static void record(String toolsDir, String name) {
        if (toolsDir == null || name == null) return;
        name = name.trim();
        if (name.isEmpty() || name.contains("/") || name.contains("\\")
                || name.equals(".") || name.equals("..")) return;
        File file = new File(toolsDir, HISTORY_FILE);
        List<String> list = readRaw(file);
        list.remove(name);
        list.add(0, name);
        if (list.size() > MAX_HISTORY) {
            list = new ArrayList<>(list.subList(0, MAX_HISTORY));
        }
        try {
            File parent = file.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) return;
            BufferedWriter w = new BufferedWriter(
                    new OutputStreamWriter(new FileOutputStream(file), StandardCharsets.UTF_8));
            try {
                for (String s : list) {
                    w.write(s);
                    w.newLine();
                }
            } finally {
                w.close();
            }
        } catch (Exception e) {
            Log.w(TAG, "记录工具历史失败: " + e.getMessage());
        }
    }

    /** 读取历史，过滤掉已经不存在（没有 main.lua）的工具，保持顺序。 */
    public static List<String> load(String toolsDir) {
        List<String> out = new ArrayList<>();
        if (toolsDir == null) return out;
        for (String s : readRaw(new File(toolsDir, HISTORY_FILE))) {
            if (isTool(toolsDir, s)) out.add(s);
        }
        return out;
    }

    /** 扫描 tools 目录，返回所有带 main.lua 的工具目录名（排序）。 */
    public static List<String> listTools(String toolsDir) {
        List<String> out = new ArrayList<>();
        if (toolsDir == null) return out;
        String[] names = new File(toolsDir).list();
        if (names == null) return out;
        Arrays.sort(names);
        for (String n : names) {
            if (isTool(toolsDir, n)) out.add(n);
        }
        return out;
    }

    /**
     * 决定工具条最终显示的 N 个按钮：
     * 历史（已过滤）优先 → 默认内置工具补足 → 其余工具补足。
     */
    public static List<String> resolve(String toolsDir, String[] defaults, int n) {
        List<String> picked = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (String s : load(toolsDir)) {
            if (seen.add(s)) picked.add(s);
            if (picked.size() >= n) return picked;
        }
        if (defaults != null) {
            for (String d : defaults) {
                if (!isTool(toolsDir, d)) continue;
                if (seen.add(d)) picked.add(d);
                if (picked.size() >= n) return picked;
            }
        }
        for (String t : listTools(toolsDir)) {
            if (seen.add(t)) picked.add(t);
            if (picked.size() >= n) break;
        }
        return picked;
    }

    //========== r27.68：show 字段 / 显示名 / 2×2 按钮取值 ==========

    /**
     * 纯文本读取工具目录下 init.lua 的 show 字段（绝不执行 Lua）。
     * 识别 show=true / show = true / show="true" / show = "true"（大小写不敏感），
     * 并跳过以 -- 开头的注释行与行尾 -- 注释。值为 true 表示「固定显示在工具条」。
     */
    public static boolean isShown(String toolsDir, String name) {
        if (toolsDir == null || name == null) return false;
        File init = new File(new File(toolsDir, name), "init.lua");
        if (!init.isFile()) return false;
        BufferedReader r = null;
        try {
            r = new BufferedReader(
                    new InputStreamReader(new FileInputStream(init), StandardCharsets.UTF_8));
            String line;
            while ((line = r.readLine()) != null) {
                String s = line;
                // 去掉行尾 Lua 注释（只认 --，init.lua 里字符串不含长注释）
                int dash = s.indexOf("--");
                if (dash >= 0) s = s.substring(0, dash);
                s = s.trim();
                if (!s.startsWith("show")) continue;
                // 必须是 show 这个标识符，后面跟 =（容忍 show=true 与 show = true）
                String rest = s.substring(4).trim();
                if (!rest.startsWith("=")) continue;
                String val = rest.substring(1).trim();
                val = val.replace("\"", "").replace("'", "");
                if ("true".equalsIgnoreCase(val)) return true;
            }
        } catch (Exception e) {
            Log.w(TAG, "读取 show 字段失败: " + name + " " + e.getMessage());
        } finally {
            if (r != null) {
                try { r.close(); } catch (Exception ignored) {}
            }
        }
        return false;
    }

    /**
     * 读取工具显示名：优先 init.lua 的 appname（纯文本，不执行 Lua），否则用目录名。
     * 只识别形如 appname="xxx" / appname = 'xxx' 的单行赋值。
     */
    public static String displayName(String toolsDir, String name) {
        if (name == null) return "";
        if (toolsDir != null) {
            File init = new File(new File(toolsDir, name), "init.lua");
            BufferedReader r = null;
            try {
                if (init.isFile()) {
                    r = new BufferedReader(
                            new InputStreamReader(new FileInputStream(init), StandardCharsets.UTF_8));
                    String line;
                    while ((line = r.readLine()) != null) {
                        String s = line;
                        int dash = s.indexOf("--");
                        if (dash >= 0) s = s.substring(0, dash);
                        s = s.trim();
                        if (!s.startsWith("appname")) continue;
                        String rest = s.substring(7).trim();
                        if (!rest.startsWith("=")) continue;
                        String val = rest.substring(1).trim();
                        // 去掉成对引号
                        if (val.length() >= 2 &&
                                ((val.charAt(0) == '"' && val.charAt(val.length() - 1) == '"')
                                        || (val.charAt(0) == '\'' && val.charAt(val.length() - 1) == '\''))) {
                            val = val.substring(1, val.length() - 1);
                        }
                        val = val.trim();
                        if (!val.isEmpty()) return val;
                    }
                }
            } catch (Exception e) {
                Log.w(TAG, "读取 appname 失败: " + name + " " + e.getMessage());
            } finally {
                if (r != null) {
                    try { r.close(); } catch (Exception ignored) {}
                }
            }
        }
        return name;
    }

    /**
     * r27.68：决定工具条 2×2 共 n 个按钮的取值：
     * 1) 有 show=true 的工具 → 固定显示；有最近使用时最多 n-1 个（留最后 1 位给最近使用），
     *    没有最近使用时可占满 n 个；
     * 2) 没有 show → 用最近使用补足；
     * 3) 最近使用也不足 → 按目录顺序补足；
     * 4) 完全没有工具 → 返回空（整栏隐藏）。
     * 全程去重且保持 show / 最近 / 顺序的相对优先级。
     */
    public static List<String> resolveGrid(String toolsDir, int n) {
        List<String> picked = new ArrayList<>();
        if (toolsDir == null) return picked;
        List<String> all = listTools(toolsDir);
        if (all.isEmpty()) return picked;
        List<String> recent = load(toolsDir);

        Set<String> seen = new LinkedHashSet<>();
        // 1) show=true 的工具，按目录顺序
        int showLimit = recent.isEmpty() ? n : (n - 1); // 有最近使用时留 1 位
        for (String t : all) {
            if (picked.size() >= showLimit) break;
            if (isShown(toolsDir, t) && seen.add(t)) picked.add(t);
        }
        // 2) 最近使用补足
        for (String r : recent) {
            if (picked.size() >= n) break;
            if (seen.add(r)) picked.add(r);
        }
        // 3) 顺序补足
        for (String t : all) {
            if (picked.size() >= n) break;
            if (seen.add(t)) picked.add(t);
        }
        return picked;
    }

    private static boolean isTool(String toolsDir, String name) {
        if (name == null || name.isEmpty()) return false;
        return new File(new File(toolsDir, name), "main.lua").isFile();
    }

    private static List<String> readRaw(File file) {
        List<String> out = new ArrayList<>();
        if (file == null || !file.isFile()) return out;
        BufferedReader r = null;
        try {
            r = new BufferedReader(
                    new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8));
            String line;
            while ((line = r.readLine()) != null) {
                String s = line.trim();
                if (!s.isEmpty() && !s.startsWith("#")) out.add(s);
            }
        } catch (Exception e) {
            Log.w(TAG, "读取工具历史失败: " + e.getMessage());
        } finally {
            if (r != null) {
                try {
                    r.close();
                } catch (Exception ignored) {
                }
            }
        }
        return out;
    }
}

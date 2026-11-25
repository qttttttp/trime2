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

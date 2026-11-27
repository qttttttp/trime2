package com.osfans.trime;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 把 APK 里内置的 tools 脚本铺到 rime/tools/ 下，装完输入法就能在「工具」里直接用，
 * 不用再手工拷目录。
 *
 * 工具来源有两处：
 * - tools/manifest.txt 里列出的「资源目录|安装名称」；
 * - assets/tools 下没列进清单、但根级带 main.lua 的目录，直接用目录名安装。
 *   所以新增工具只要放一个目录，清单只用来指定中文显示名。
 *
 * 更新策略（避免把用户改过的脚本冲掉）：
 * - 目录不存在 → 全部写入，并记录每个文件的 sha1；
 * - bundle 指纹（整包内容哈希）没变 → 什么都不做；
 * - bundle 变了 → 只覆盖「用户没改过」的文件（当前 sha1 == 上次写入的 sha1）；
 *   用户改过的保留原样，新版另存为 &lt;文件名&gt;.new 供对比。
 */
public final class BuiltinTools {

    private static final String TAG = "BuiltinTools";
    private static final String MARKER = ".builtin";
    private static final String BUNDLE_KEY = "@bundle";
    private static final String ASSET_ROOT = "tools";

    private BuiltinTools() {
    }

    /** 读取「随包资源」的抽象，便于脱离 Android 环境做单测。 */
    interface Source {
        /** 列出目录下的直接子项；对方是文件时返回空数组。 */
        String[] list(String dir) throws IOException;

        InputStream open(String path) throws IOException;
    }

    /**
     * 确保 assets/tools/&lt;资源目录&gt; 下的脚本都已铺到 toolsDir/&lt;安装名称&gt;。
     * 可以重复调用，代价只有一次内容哈希。
     */
    public static void ensureInstalled(Context ctx, String toolsDir) {
        if (ctx == null || toolsDir == null) return;
        try {
            Source src = new AssetSource(ctx.getAssets());
            File base = new File(toolsDir);
            if (!base.isDirectory() && !base.mkdirs()) {
                Log.w(TAG, "无法创建工具目录: " + toolsDir);
                return;
            }
            for (String[] t : collectTargets(src)) {
                try {
                    installOne(src, base, t[0], t[1]);
                } catch (Exception e) {
                    // 单个工具失败不影响其它工具
                    Log.w(TAG, "安装内置工具失败: " + t[1], e);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "读取内置工具清单失败", e);
        }
    }

    /**
     * tools/manifest.txt：每行「资源目录|安装名称」，资源目录保持 ASCII，
     * 中文名在这里映射，中文路径不参与打包。
     */
    static List<String[]> readManifest(Source src) {
        List<String[]> out = new ArrayList<>();
        InputStream in = null;
        try {
            in = src.open(ASSET_ROOT + "/manifest.txt");
            for (String line : readText(in).split("\n")) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                int i = line.indexOf('|');
                if (i <= 0 || i >= line.length() - 1) continue;
                String assetDir = line.substring(0, i).trim();
                String target = line.substring(i + 1).trim();
                if (assetDir.isEmpty() || target.isEmpty()) continue;
                out.add(new String[]{assetDir, target});
            }
        } catch (Exception e) {
            Log.w(TAG, "缺少 assets/tools/manifest.txt", e);
        } finally {
            closeQuietly(in);
        }
        return out;
    }

    /**
     * 要安装的全部工具：清单条目 + assets/tools 下未列入清单的工具目录。
     * 自动发现的目录以目录名作为安装名，清单只负责把名字换成中文。
     */
    static List<String[]> collectTargets(Source src) {
        List<String[]> out = readManifest(src);
        Set<String> known = new HashSet<>();
        for (String[] t : out) known.add(t[0]);
        String[] children;
        try {
            children = src.list(ASSET_ROOT);
        } catch (IOException e) {
            return out;
        }
        if (children == null) return out;
        Arrays.sort(children);
        for (String name : children) {
            if (name.isEmpty() || known.contains(name)) continue;
            List<String> rels = new ArrayList<>();
            collect(src, ASSET_ROOT + "/" + name, "", rels);
            // 根级必须有 main.lua，和 installOne 的判定保持一致；
            // manifest.txt / readme.txt 这类散文件自然被排除。
            if (rels.contains("main.lua")) out.add(new String[]{name, name});
        }
        return out;
    }

    static void installOne(Source src, File base, String assetDir, String name) throws IOException {
        String root = ASSET_ROOT + "/" + assetDir;
        List<String> rels = new ArrayList<>();
        collect(src, root, "", rels);
        if (rels.isEmpty()) return;

        // 只有带 main.lua 的目录才算工具（和 ToolActivity 的判定一致）
        boolean hasMain = false;
        for (String r : rels) {
            if ("main.lua".equals(r)) {
                hasMain = true;
                break;
            }
        }
        if (!hasMain) return;

        Collections.sort(rels);

        File dir = new File(base, name);
        File marker = new File(dir, MARKER);
        Map<String, String> old = readMarker(marker);
        String bundle = hashAssets(src, root, rels);
        if (!dir.isDirectory() && !dir.mkdirs()) return;

        Map<String, String> now = new HashMap<>();
        for (String rel : rels) {
            File f = new File(dir, rel);
            File parent = f.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) continue;

            String shipped = hashAsset(src, root + "/" + rel);
            String prevShipped = old.get(rel);
            String disk = f.isFile() ? hashFile(f) : null;

            boolean userOwned = false;
            if (disk == null) {
                copy(src, root + "/" + rel, f);
            } else if (shipped.equals(disk)) {
                // 已经是最新内容，不动
            } else if (disk.equals(prevShipped)) {
                // 用户没改过，直接升级
                copy(src, root + "/" + rel, f);
            } else {
                // 用户改过：保留自己的，新版另存 .new
                userOwned = true;
                File alt = new File(dir, rel + ".new");
                if (!alt.isFile() || !shipped.equals(hashFile(alt))) {
                    copy(src, root + "/" + rel, alt);
                }
            }
            // 记录「上次分发的版本」而不是磁盘现状：用户改过的文件必须继续被认作
            // 用户所有，否则下一次升级会把它当成没改过直接覆盖。
            if (userOwned) {
                now.put(rel, prevShipped == null ? "" : prevShipped);
            } else {
                now.put(rel, shipped);
            }
        }
        // 只有真的变了才落盘，避免每次打开工具列表都写一遍
        Map<String, String> oldFiles = new HashMap<>(old);
        oldFiles.remove(BUNDLE_KEY);
        if (!bundle.equals(old.get(BUNDLE_KEY)) || !now.equals(oldFiles)) {
            writeMarker(marker, bundle, now);
        }
    }

    /** 递归列出相对路径（目录本身不记录）。 */
    private static void collect(Source src, String root, String rel, List<String> out) {
        String path = rel.isEmpty() ? root : root + "/" + rel;
        String[] children;
        try {
            children = src.list(path);
        } catch (IOException e) {
            return;
        }
        if (children == null || children.length == 0) {
            if (!rel.isEmpty()) out.add(rel);
            return;
        }
        for (String c : children) {
            collect(src, root, rel.isEmpty() ? c : rel + "/" + c, out);
        }
    }

    private static void copy(Source src, String asset, File dst) throws IOException {
        InputStream in = null;
        FileOutputStream out = null;
        try {
            in = src.open(asset);
            out = new FileOutputStream(dst);
            byte[] buf = new byte[16 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            out.flush();
        } finally {
            closeQuietly(in);
            closeQuietly(out);
        }
    }

    private static String hashAsset(Source src, String asset) {
        InputStream in = null;
        try {
            in = src.open(asset);
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] buf = new byte[16 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
            return hex(md.digest());
        } catch (Exception e) {
            return "";
        } finally {
            closeQuietly(in);
        }
    }

    private static String hashFile(File f) {
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] buf = new byte[16 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
            return hex(md.digest());
        } catch (Exception e) {
            return "";
        } finally {
            closeQuietly(in);
        }
    }

    /** 整包指纹：文件相对路径 + 内容一起哈希，任何文件变了都会变。 */
    private static String hashAssets(Source src, String root, List<String> rels) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            for (String rel : rels) {
                md.update((rel + "\u0000").getBytes("UTF-8"));
                InputStream in = null;
                try {
                    in = src.open(root + "/" + rel);
                    byte[] buf = new byte[16 * 1024];
                    int n;
                    while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
                } finally {
                    closeQuietly(in);
                }
            }
            return hex(md.digest());
        } catch (Exception e) {
            return "";
        }
    }

    private static Map<String, String> readMarker(File f) {
        Map<String, String> map = new HashMap<>();
        if (!f.isFile()) return map;
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            for (String line : readText(in).split("\n")) {
                int i = line.indexOf('=');
                if (i <= 0) continue;
                map.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
            }
        } catch (Exception ignored) {
        } finally {
            closeQuietly(in);
        }
        return map;
    }

    private static void writeMarker(File f, String bundle, Map<String, String> files) {
        StringBuilder sb = new StringBuilder();
        sb.append(BUNDLE_KEY).append('=').append(bundle).append('\n');
        for (Map.Entry<String, String> e : files.entrySet()) {
            sb.append(e.getKey()).append('=').append(e.getValue()).append('\n');
        }
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(f);
            out.write(sb.toString().getBytes("UTF-8"));
            out.flush();
        } catch (Exception ignored) {
        } finally {
            closeQuietly(out);
        }
    }

    private static String readText(InputStream in) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
        return bos.toString("UTF-8");
    }

    private static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(Character.forDigit((b >> 4) & 0xF, 16));
            sb.append(Character.forDigit(b & 0xF, 16));
        }
        return sb.toString();
    }

    private static void closeQuietly(java.io.Closeable c) {
        if (c != null) {
            try {
                c.close();
            } catch (IOException ignored) {
            }
        }
    }

    /** Android assets 实现。 */
    private static final class AssetSource implements Source {
        private final AssetManager am;

        AssetSource(AssetManager am) {
            this.am = am;
        }

        @Override
        public String[] list(String dir) throws IOException {
            return am.list(dir);
        }

        @Override
        public InputStream open(String path) throws IOException {
            return am.open(path);
        }
    }
}

package com.osfans.trime.mlkit;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * 把 APK 内置的手写模型包复制到 ML Kit 能直接读到的位置。
 *
 * <p>ML Kit 的 digital-ink 依赖包自带一份 {@code assets/manifest.json}，里面每个模型包都有一个
 * 下载地址；本项目用的是改写过的版本，地址为 {@code file:/sdcard/Android/data/<包名>/files/
 * offline-models/<pack>.zip}。该路径由 AAR 编译期固定，运行时改不了，所以这里把随包的 zip
 * 复制到同一个位置，剩下的校验、解包、写 Mobstore、登记 Icing 全部交给 ML Kit 自己完成，
 * 不需要伪造任何“已下载”状态。
 *
 * <p>调用 {@link #installAsync(Context)} 是幂等的：已经就绪时立即返回，未就绪时在后台线程复制，
 * 重复调用不会起第二个线程。整个过程只比对文件长度，不做哈希（zip 本身的 sha1 由 ML Kit 校验）。
 */
public final class MlkitModelInstaller {

    private static final String TAG = "TrimeMlkit";

    /** assets 下的目录名 */
    public static final String ASSET_DIR = "mlkit-offline";
    /** 外部私有目录下的子目录名，必须与 AAR 内 manifest.json 的 file: 路径一致 */
    public static final String TARGET_DIR = "offline-models";
    /** 清单文件名，记录上次复制了哪些文件、多大，用于快速跳过 */
    private static final String STAMP = ".installed";

    public static final int STATE_IDLE = 0;
    public static final int STATE_RUNNING = 1;
    public static final int STATE_READY = 2;
    public static final int STATE_FAILED = 3;

    private static volatile int sState = STATE_IDLE;
    private static volatile String sMessage = "";

    private MlkitModelInstaller() {
    }

    /* ---------------------------------------------------------------- 对外接口 */

    /**
     * 确保模型包已复制到目标目录，必要时在后台线程执行。可重复调用。
     */
    public static void installAsync(Context context) {
        if (sState == STATE_READY || sState == STATE_RUNNING) return;
        synchronized (MlkitModelInstaller.class) {
            if (sState == STATE_READY || sState == STATE_RUNNING) return;
            sState = STATE_RUNNING;
        }
        final Context app = context.getApplicationContext();
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    File dst = targetDir(app);
                    if (dst == null) {
                        throw new IOException("外部私有目录不可用（存储未挂载？）");
                    }
                    install(dst, new ContextSource(app), false);
                    sState = STATE_READY;
                    sMessage = "ok";
                    Log.i(TAG, "手写模型已就绪: " + dst.getAbsolutePath());
                } catch (Throwable e) {
                    sState = STATE_FAILED;
                    sMessage = e.toString();
                    Log.w(TAG, "手写模型准备失败", e);
                }
            }
        }, "trime-mlkit-install");
        t.setDaemon(true);
        t.start();
    }

    /** 是否已经可以调用 ML Kit 下载（即 zip 都在位）。 */
    public static boolean isReady(Context context) {
        if (sState == STATE_READY) return true;
        // 状态丢了（进程重建但文件还在）时直接查文件，避免重复复制
        try {
            File dst = targetDir(context);
            return dst != null && install(dst, new ContextSource(context), true);
        } catch (Throwable e) {
            return false;
        }
    }

    /** STATE_IDLE / RUNNING / READY / FAILED */
    public static int getState() {
        return sState;
    }

    /** 运行状态的可读描述，出错时是异常信息。 */
    public static String getMessage() {
        return sMessage;
    }

    /** 目标目录的绝对路径，与 AAR 内 manifest 的 file: 地址对应。 */
    public static String getTargetDir(Context context) {
        File dir = targetDir(context);
        return dir == null ? "" : dir.getAbsolutePath();
    }

    /* ---------------------------------------------------------------- 实现 */

    private static File targetDir(Context context) {
        File base = context.getExternalFilesDir(null);
        if (base == null) return null;
        return new File(base, TARGET_DIR);
    }

    /** 模型包的 IO 来源，便于在非 Android 环境（PC 上的目录）验证同一套逻辑。 */
    interface Source {
        String[] list() throws IOException;

        long length(String name);

        InputStream open(String name) throws IOException;
    }

    private static final class ContextSource implements Source {
        private final Context ctx;

        ContextSource(Context ctx) {
            this.ctx = ctx;
        }

        @Override
        public String[] list() throws IOException {
            return ctx.getAssets().list(ASSET_DIR);
        }

        @Override
        public long length(String name) {
            InputStream in = null;
            try {
                in = ctx.getAssets().open(ASSET_DIR + "/" + name);
                // AssetInputStream.available() 返回剩余字节数，未读过时即文件长度
                return in.available();
            } catch (Throwable e) {
                return -1;
            } finally {
                closeQuietly(in);
            }
        }

        @Override
        public InputStream open(String name) throws IOException {
            return ctx.getAssets().open(ASSET_DIR + "/" + name);
        }
    }

    /**
     * 同步安装。
     *
     * @param dryRun 只检查不复制，用于 {@link #isReady}
     * @return 本次是否（已）就绪
     */
    static boolean install(File dst, Source src, boolean dryRun) throws IOException {
        String[] names = src.list();
        if (names == null || names.length == 0) {
            throw new IOException("assets/" + ASSET_DIR + " 为空，APK 里没有模型包");
        }
        if (!dryRun && !dst.isDirectory() && !dst.mkdirs()) {
            throw new IOException("无法创建目录: " + dst);
        }
        if (dryRun && !dst.isDirectory()) return false;

        // 上次的记录：文件齐全且长度一致就直接返回，省掉一次 16MB 的 IO
        List<String> old = readStamp(dst);
        if (matchesStamp(dst, names, old, src)) return true;
        if (dryRun) return false;

        // 上次装过、这次 assets 里没有的包，顺手删掉，避免旧版本残留占空间
        for (String line : old) {
            int sp = line.lastIndexOf(' ');
            String name = sp > 0 ? line.substring(0, sp) : line;
            if (!contains(names, name)) {
                new File(dst, name).delete();
            }
        }

        List<String> now = new ArrayList<>(names.length);
        for (String name : names) {
            File target = new File(dst, name);
            long size = src.length(name);
            if (size < 0) {
                // 拿不到长度就老实复制
                copy(src, name, target);
                now.add(name + " " + target.length());
            } else if (target.isFile() && target.length() == size) {
                now.add(name + " " + size);
            } else {
                copy(src, name, target);
                now.add(name + " " + target.length());
            }
        }
        writeStamp(dst, now);
        return true;
    }

    /**
     * 清单、目标文件、当前 assets 三方都要对得上才算就绪：
     * 目标被删/被截断、assets 里换了同名但不同大小的包，任意一项不符都重做。
     */
    private static boolean matchesStamp(File dst, String[] names, List<String> stamp, Source src) {
        if (stamp.size() != names.length) return false;
        for (String line : stamp) {
            int sp = line.lastIndexOf(' ');
            if (sp <= 0) return false;
            String name = line.substring(0, sp);
            long size;
            try {
                size = Long.parseLong(line.substring(sp + 1));
            } catch (NumberFormatException e) {
                return false;
            }
            if (!contains(names, name)) return false;   // 旧文件已被移除
            File f = new File(dst, name);
            if (!f.isFile() || f.length() != size) return false;
            long cur = src.length(name);
            if (cur >= 0 && cur != size) return false;  // 随包资源换了内容
        }
        return true;
    }

    private static boolean contains(String[] arr, String v) {
        for (String s : arr) {
            if (s.equals(v)) return true;
        }
        return false;
    }

    /** 先写 .part 再改名，避免复制一半被当成完整文件。 */
    private static void copy(Source src, String name, File target) throws IOException {
        File tmp = new File(target.getParentFile(), name + ".part");
        InputStream in = null;
        OutputStream out = null;
        try {
            in = src.open(name);
            FileOutputStream fos = new FileOutputStream(tmp);
            out = fos;
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            out.flush();
            fos.getFD().sync();
        } finally {
            closeQuietly(out);
            closeQuietly(in);
        }
        if (target.exists() && !target.delete()) {
            throw new IOException("无法覆盖旧文件: " + target);
        }
        if (!tmp.renameTo(target)) {
            throw new IOException("无法重命名: " + tmp);
        }
    }

    private static List<String> readStamp(File dst) {
        List<String> out = new ArrayList<>();
        File f = new File(dst, STAMP);
        if (!f.isFile()) return out;
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            byte[] buf = new byte[(int) Math.min(f.length(), 8192)];
            int n = in.read(buf);
            if (n <= 0) return out;
            for (String line : new String(buf, 0, n, "UTF-8").split("\n")) {
                if (line.trim().length() > 0) out.add(line.trim());
            }
        } catch (Throwable e) {
            out.clear();
        } finally {
            closeQuietly(in);
        }
        return out;
    }

    private static void writeStamp(File dst, List<String> lines) {
        File tmp = new File(dst, STAMP + ".part");
        OutputStream out = null;
        try {
            out = new FileOutputStream(tmp);
            StringBuilder sb = new StringBuilder();
            for (String line : lines) {
                sb.append(line).append('\n');
            }
            out.write(sb.toString().getBytes("UTF-8"));
            out.flush();
        } catch (Throwable e) {
            Log.w(TAG, "写模型清单失败（不影响使用）", e);
            tmp.delete();
            return;
        } finally {
            closeQuietly(out);
        }
        File f = new File(dst, STAMP);
        if (f.exists()) f.delete();
        if (!tmp.renameTo(f)) tmp.delete();
    }

    private static void closeQuietly(java.io.Closeable c) {
        if (c != null) {
            try {
                c.close();
            } catch (Throwable ignored) {
            }
        }
    }
}

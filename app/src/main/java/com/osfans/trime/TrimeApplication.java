/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime;

import android.Manifest;
import android.app.Application;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Environment;
import android.util.Log;

import com.androlua.LuaUtil;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class TrimeApplication extends Application {
    private static TrimeApplication sInstance;

    public static TrimeApplication getInstance() {
        return sInstance;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        sInstance=this;
    }

    public boolean isStorageAvailable() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager();
        }else {
            return checkCallingOrSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    == PackageManager.PERMISSION_GRANTED;
        }
    }

    public void unApk(String dir, String extDir) throws IOException {
        int i = dir.length() + 1;
        ZipFile zip = new ZipFile(getApplicationInfo().publicSourceDir);
        Enumeration<? extends ZipEntry> entries = zip.entries();
        //Log.w("lua", "unApk:0 "+dir );
        while (entries.hasMoreElements()) {
            ZipEntry entry = entries.nextElement();
            String name = entry.getName();
            //Log.w("lua", "unApk:1 "+name );
            if (name.indexOf(dir) != 0)
                continue;
            String path = name.substring(i);
            if (entry.isDirectory()) {
                File f = new File(extDir + File.separator + path);
                if (!f.exists()) {
                    //noinspection ResultOfMethodCallIgnored
                    f.mkdirs();
                }
            } else {
                String fname = extDir + File.separator + path;
                //Log.w("lua", "unApk:2 "+fname );
                File ff = new File(fname);
                File temp = new File(fname).getParentFile();
                if (!temp.exists()) {
                    if (!temp.mkdirs()) {
                        continue;
                        //throw new RuntimeException("create file " + temp.getName() + " fail");
                    }
                }
                try {
                    if (ff.exists() && entry.getSize() == ff.length() && LuaUtil.getFileMD5(zip.getInputStream(entry)).equals(LuaUtil.getFileMD5(ff)))
                        continue;
                } catch (NullPointerException ignored) {
                }
                FileOutputStream out = new FileOutputStream(extDir + File.separator + path);
                InputStream in = zip.getInputStream(entry);
                byte[] buf = new byte[40960];
                int count = 0;
                while ((count = in.read(buf)) != -1) {
                    out.write(buf, 0, count);
                }
                out.close();
                in.close();
            }
        }
        zip.close();
    }

}

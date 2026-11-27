// SPDX-FileCopyrightText: 2015 - 2024 Rime community
//
// SPDX-License-Identifier: GPL-3.0-or-later

package com.osfans.trime.data.opencc.dict;

import com.osfans.trime.data.opencc.OpenCCDictManager;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

public class OpenCCDictionary extends Dictionary {

    public static final String NEW_FORMAT = "ocd2";
    public static final String OLD_FORMAT = "ocd";

    private final File file;
    private final Type type;

    public OpenCCDictionary(File file) {
        this.file = file;

        // 初始化 type
        if (NEW_FORMAT.equals(getFileExtension(file))) {
            this.type = Type.OCD2;
        } else {
            this.type = Type.OCD;
        }

        // 对应 Kotlin 的 init 块
        ensureFileExists();
        if (!getFileExtension(file).equals(this.type.getExt())) {
            throw new IllegalArgumentException("Not a OpenCC dict " + file.getName());
        }
    }

    @Override
    public File getFile() {
        return this.file;
    }

    @Override
    public Type getType() {
        return this.type;
    }

    @Override
    public TextDictionary toTextDictionary(File dest) {
        ensureTxt(dest);
        OpenCCDictManager.openCCDictConv(
                this.file.getAbsolutePath(),
                dest.getAbsolutePath(),
                OpenCCDictManager.MODE_BIN_TO_TXT
        );
        return new TextDictionary(dest);
    }

    @Override
    public OpenCCDictionary toOpenCCDictionary(File dest) {
        ensureBin(dest);

        // 使用 FileChannel 进行高效文件复制，完全兼容 Android 7 及以下
        try (FileInputStream is = new FileInputStream(this.file);
             FileOutputStream os = new FileOutputStream(dest);
             FileChannel inChannel = is.getChannel();
             FileChannel outChannel = os.getChannel()) {

            // transferTo 比传统的 byte[] 循环更快，它会利用操作系统的零拷贝（Zero-Copy）特性
            long size = inChannel.size();
            long transferred = 0;
            while (transferred < size) {
                transferred += inChannel.transferTo(transferred, size - transferred, outChannel);
            }

        } catch (IOException e) {
            throw new RuntimeException("Failed to copy file from " + this.file.getPath() + " to " + dest.getPath(), e);
        }

        return new OpenCCDictionary(dest);
    }

    // 辅助方法：获取文件后缀名（不带点）
    private String getFileExtension(File file) {
        String name = file.getName();
        int dotIndex = name.lastIndexOf('.');
        return (dotIndex > 0) ? name.substring(dotIndex + 1) : "";
    }
}

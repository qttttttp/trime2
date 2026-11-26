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

public class TextDictionary extends Dictionary {

    private final File file;
    private final Type type = Type.Text;

    public TextDictionary(File file) {
        this.file = file;

        // 对应 Kotlin 的 init 块
        ensureFileExists();
        if (!getFileExtension(file).equals(this.type.getExt())) {
            throw new IllegalArgumentException("Not a text dict " + file.getName());
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

        // 兼容 Android 7 及以下的高效文件复制 (FileChannel)
        try (FileInputStream is = new FileInputStream(this.file);
             FileOutputStream os = new FileOutputStream(dest);
             FileChannel inChannel = is.getChannel();
             FileChannel outChannel = os.getChannel()) {

            long size = inChannel.size();
            long transferred = 0;
            while (transferred < size) {
                transferred += inChannel.transferTo(transferred, size - transferred, outChannel);
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to copy file from " + this.file.getPath() + " to " + dest.getPath(), e);
        }

        return new TextDictionary(dest);
    }

    @Override
    public OpenCCDictionary toOpenCCDictionary(File dest) {
        ensureBin(dest);
        OpenCCDictManager.openCCDictConv(
                this.file.getAbsolutePath(),
                dest.getAbsolutePath(),
                OpenCCDictManager.MODE_TXT_TO_BIN
        );
        return new OpenCCDictionary(dest);
    }

    // 辅助方法：获取文件后缀名（不带点）
    private String getFileExtension(File file) {
        String name = file.getName();
        int dotIndex = name.lastIndexOf('.');
        return (dotIndex > 0) ? name.substring(dotIndex + 1) : "";
    }
}

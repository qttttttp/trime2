// SPDX-FileCopyrightText: 2015 - 2024 Rime community
//
// SPDX-License-Identifier: GPL-3.0-or-later

package com.osfans.trime.data.opencc.dict;

import java.io.File;

public abstract class Dictionary {

    public enum Type {
        OCD("ocd"),
        OCD2("ocd2"),
        Text("txt");

        private final String ext;

        Type(String ext) {
            this.ext = ext;
        }

        public String getExt() {
            return ext;
        }

        public static Type fromFileName(String name) {
            if (name == null) return null;
            if (name.endsWith(".ocd2")) return OCD2;
            if (name.endsWith(".ocd")) return OCD;
            if (name.endsWith(".txt")) return Text;
            return null;
        }
    }

    // Kotlin 的 abstract val 转换为 Java 的抽象 getter 方法
    public abstract File getFile();

    public abstract Type getType();

    public abstract TextDictionary toTextDictionary(File dest);

    public abstract OpenCCDictionary toOpenCCDictionary(File dest);

    public String getName() {
        String name = getFile().getName();
        int dotIndex = name.lastIndexOf('.');
        return (dotIndex > 0) ? name.substring(0, dotIndex) : name;
    }

    public TextDictionary toTextDictionary() {
        File dest = new File(getFile().getParentFile(), getName() + "." + Type.Text.getExt());
        return toTextDictionary(dest);
    }

    public OpenCCDictionary toOpenCCDictionary() {
        File dest = new File(getFile().getParentFile(), getName() + "." + Type.OCD2.getExt());
        return toOpenCCDictionary(dest);
    }

    protected void ensureFileExists() {
        if (!getFile().exists()) {
            throw new IllegalStateException("File " + getFile().getAbsolutePath() + " does not exist");
        }
    }

    protected void ensureTxt(File dest) {
        if (!getFileExtension(dest).equals(Type.Text.getExt())) {
            throw new IllegalArgumentException("Dest file name must end with ." + Type.Text.getExt());
        }
        dest.delete();
    }

    protected void ensureBin(File dest) {
        String ext = getFileExtension(dest);
        if (!ext.equals(Type.OCD.getExt()) && !ext.equals(Type.OCD2.getExt())) {
            throw new IllegalArgumentException("Dest file name must end with ." + Type.OCD.getExt() + " or ." + Type.OCD2.getExt());
        }
        dest.delete();
    }

    @Override
    public String toString() {
        return getClass().getSimpleName() + "[" + getName() + " -> " + getFile().getPath() + "]";
    }

    public static Dictionary newDictionary(File it) {
        if (it == null) return null;
        Type type = Type.fromFileName(it.getName());
        if (type == null) return null;

        switch (type) {
            case OCD:
            case OCD2:
                return new OpenCCDictionary(it);
            case Text:
                return new TextDictionary(it);
            default:
                return null;
        }
    }

    // 辅助方法：获取文件后缀名（不带点）
    private String getFileExtension(File file) {
        String name = file.getName();
        int dotIndex = name.lastIndexOf('.');
        return (dotIndex > 0) ? name.substring(dotIndex + 1) : "";
    }
}

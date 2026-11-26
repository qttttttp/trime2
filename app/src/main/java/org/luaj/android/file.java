package org.luaj.android;

import com.androlua.LuaUtil;
import com.osfans.trime.BuildConfig;

import org.luaj.*;
import org.luaj.lib.OneArgFunction;
import org.luaj.lib.TwoArgFunction;
import org.luaj.lib.jse.LuajavaLib;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.BasicFileAttributes;

/**
 * Created by nirenr on 2020/1/16.
 */
public class file extends TwoArgFunction {
    private Globals globals;

    public static String readAll(String path) {
        try {
            return new String(LuaUtil.readAll(path));
        } catch (IOException e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        return "";
    }

    public static String[] list(String path) {
        return new File(path).list();
    }

    public static boolean exists(String path) {
        return new File(path).exists();
    }

    public static boolean save(String path, LuaString text) {
        try {
            //BufferedWriter buf = new BufferedWriter(new FileWriter(path));
            FileOutputStream buf = new FileOutputStream(path);
            buf.write(text.m_bytes, text.m_offset, text.m_length);
            buf.close();
            return true;
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        return false;
    }


    public LuaValue call(LuaValue modname, LuaValue env) {
        globals = env.checkglobals();
        LuaTable file = new LuaTable();
        file.set("readall", new readall());
        file.set("list", new list());
        file.set("exists", new exists());
        file.set("save", new save());
        file.set("type", new type());
        file.set("info", new info());
        file.set("mkdir", new mkdir());
        env.set("file", file);
        if (!env.get("package").isnil()) env.get("package").get("loaded").set("file", file);
        return NIL;
    }

    private class readall extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            try {
                return LuaString.valueOf(LuaUtil.readAll(globals.finder.findFile(arg.tojstring())));
            } catch (Exception e) {
                return NIL;
            }
        }
    }

    private class list extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            return LuajavaLib.asTable(list(globals.finder.findFile(arg.tojstring())));
        }
    }

    private class type extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            File f = new File(globals.finder.findFile(arg.tojstring()));
            return LuaValue.valueOf(f.exists()?(f.isDirectory() ? "dir" : "file"):"");
        }
    }

    private class info extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            LuaTable ret = new LuaTable();
            File f = new File(globals.finder.findFile(arg.tojstring()));
            if (!f.exists()) {
                ret.jset("type", "");
                String nm = f.getName();
                ret.jset("name", nm);
                int idx = nm.lastIndexOf(".");
                if(idx>0)
                    ret.jset("ext",nm.substring(idx+1));
                ret.jset("parent", f.getParent());
                ret.jset("read", f.canRead());
                ret.jset("write", f.canWrite());
                return ret;
            }
            ret.jset("type", f.isDirectory() ? "dir" : "file");
            ret.jset("path", f.getAbsolutePath());
            ret.jset("size", f.length());
            String nm = f.getName();
            ret.jset("name", nm);
            int idx = nm.lastIndexOf(".");
            if(idx>0)
                ret.jset("ext",nm.substring(idx+1));
            ret.jset("parent", f.getParent());
            ret.jset("read", f.canRead());
            ret.jset("write", f.canWrite());
            ret.jset("execute", f.canExecute());
            ret.jset("last", f.lastModified());
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                try {
                    Path path = Paths.get(f.getAbsolutePath());
                    BasicFileAttributes attr = Files.readAttributes(path, BasicFileAttributes.class);
                    ret.jset("create", attr.creationTime().toMillis());
                    ret.jset("access", attr.lastAccessTime().toMillis());
                } catch (Exception e) {
                    e.printStackTrace();
                }
           }
            return ret;
        }
    }

    private class mkdir extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            return LuaValue.valueOf(new File(arg.tojstring()).mkdirs());
        }
    }

    private class exists extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            try {
                return LuaValue.valueOf(exists(globals.finder.findFile(arg.tojstring())));
            } catch (Exception e) {
                return NIL;
            }
        }
    }

    private class save extends TwoArgFunction {
        @Override
        public LuaValue call(LuaValue arg1, LuaValue arg2) {
            return LuaValue.valueOf(save(globals.finder.findFile(arg1.tojstring()), arg2.checkstring()));
        }
    }
}

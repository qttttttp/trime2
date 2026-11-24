package org.luaj.android;

import com.androlua.LuaBitmap;
import com.androlua.LuaBitmapDrawable;
import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.json.JSONException;
import org.json.JSONObject;
import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaUserdata;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.OneArgFunction;
import org.luaj.lib.TwoArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;
import org.luaj.lib.jse.LuajavaLib;

import java.io.File;
import java.util.Locale;

public class res extends TwoArgFunction {


    private String mLanguage;
    private Globals glabals;
    private LuaTable stringTable;
    private LuaContext activity;

    public res(LuaContext activity) {
        this.activity = activity;
        mLanguage = Locale.getDefault().getLanguage();
    }

    public LuaValue call(LuaValue modname, LuaValue env) {
        glabals = env.checkglobals();
        LuaTable res = new LuaTable();
        res.set("string", new string());
        res.set("drawable", new drawable());
        res.set("bitmap", new bitmap());
        res.set("layout", new layout());
        res.set("view", new view());
        env.set("res", res);
        if (!env.get("package").isnil()) env.get("package").get("loaded").set("res", res);
        return NIL;
    }

    private class string extends LuaValue {

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaTable checktable() {
            String language = Locale.getDefault().getLanguage();
            if (!language.equals(mLanguage)) {
                mLanguage = language;
                stringTable = null;
            }
            if (stringTable == null) {
                LuaTable defTable = new LuaTable();
                String p = activity.getLuaPath("res/string", "init.lua");
                if (new File(p).exists())
                    glabals.loadfile(p, defTable).call();
                stringTable = defTable.clone();

                p = activity.getLuaPath("res/string", mLanguage + ".lua");
                if (new File(p).exists())
                    glabals.loadfile(p, stringTable).call();
            }
            return stringTable;
        }

        @Override
        public LuaValue get(String key) {
            String language = Locale.getDefault().getLanguage();
            if (!language.equals(mLanguage)) {
                mLanguage = language;
                stringTable = null;
            }
            if (stringTable == null) {
                LuaTable defTable = new LuaTable();
                String p = activity.getLuaPath("res/string", "init.lua");
                if (new File(p).exists())
                    glabals.loadfile(p, defTable).call();
                stringTable = defTable.clone();

                p = activity.getLuaPath("res/string", mLanguage + ".lua");
                if (new File(p).exists())
                    glabals.loadfile(p, stringTable).call();
            }
            return stringTable.get(key);
        }

    }

    private class drawable extends LuaValue {
        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/drawable")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            String p = activity.getLuaPath("res/drawable", arg);
            if (new File(p + ".png").exists())
                return CoerceJavaToLua.coerce(new LuaBitmapDrawable(activity, p + ".png"));
            if (new File(p + ".jpg").exists())
                return CoerceJavaToLua.coerce(new LuaBitmapDrawable(activity, p + ".jpg"));
            if (new File(p + ".gif").exists())
                return CoerceJavaToLua.coerce(new LuaBitmapDrawable(activity, p + ".gif"));
            if (new File(p + ".lua").exists())
                return glabals.loadfile(p + ".lua", glabals).call();
            return LuaValue.NIL;
        }
    }

    private class bitmap extends LuaValue {
        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/drawable")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            try {
                String p = activity.getLuaPath("res/drawable", arg);
                if (new File(p + ".png").exists())
                    return CoerceJavaToLua.coerce(LuaBitmap.getBitmap(activity, p + ".png"));
                if (new File(p + ".jpg").exists())
                    return CoerceJavaToLua.coerce(LuaBitmap.getBitmap(activity, p + ".jpg"));
                if (new File(p + ".gif").exists())
                    return CoerceJavaToLua.coerce(LuaBitmap.getBitmap(activity, p + ".gif"));
                if (new File(p + ".lua").exists())
                    return glabals.loadfile(p + ".lua", glabals).call();
                return LuaValue.NIL;
            } catch (Exception e){
                throw new LuaError(e);
            }
        }
    }

    private class layout extends LuaValue {
        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/layout")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            String p = activity.getLuaPath("res/layout", arg + ".lua");
            return glabals.loadfile(p, glabals).call();
        }
    }

    private class view extends LuaValue {
        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/layout")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            String p = activity.getLuaPath("res/layout", arg + ".lua");
            return new LuaLayout(activity.getContext()).load(glabals.loadfile(p, glabals).call(), glabals);
        }
    }
}

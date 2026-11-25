package org.luaj.android;

import com.osfans.trime.BuildConfig;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.LibFunction;
import org.luaj.lib.OneArgFunction;
import org.luaj.lib.TwoArgFunction;
import org.luaj.lib.jse.CoerceLuaToJava;
import org.luaj.lib.jse.LuajavaLib;

/**
 * Created by nirenr on 2020/1/16.
 */
public class json extends TwoArgFunction {




    public static String encode(LuaValue value) {
        Object map = toJson(value);
        return map.toString();
    }
    private static Object toJson(LuaValue value) {
        LuaTable t = value.checktable();
        if(t.length()==t.size()){
            JSONArray arr = new JSONArray();
            for (int i = 0; i < t.length(); i++) {
                LuaValue v = t.get(i + 1);
                if(v.istable())
                    arr.put(toJson(v));
                else
                    arr.put(CoerceLuaToJava.coerce(v, Object.class));
            }
            return arr;
        }
        JSONObject map = new JSONObject();
        Varargs ret = value.next(LuaValue.NIL);
        while (ret != LuaValue.NIL) {
            LuaValue k = ret.arg1();
            LuaValue v = ret.arg(2);
            try {
                if (v.istable())
                    map.put(k.tojstring(), toJson(v));
                else
                    map.put(k.tojstring(), CoerceLuaToJava.coerce(v, Object.class));
            } catch (JSONException e) {
                if(BuildConfig.DEBUG)
			    e.printStackTrace();
            }
            ret = value.next(k);
        }
        return map;
    }

    public static LuaValue decode(String text){
        try {
            if(text.startsWith("["))
                return LuajavaLib.asTable(new JSONArray(text));
            return LuajavaLib.asTable(new JSONObject(text));
        } catch (Exception e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
            throw new LuaError(e.getMessage());
        }
        //return NIL;
    }

    public LuaValue call(LuaValue modname, LuaValue env) {
        LuaTable json = new LuaTable();
        json.set("decode", new decode());
        json.set("encode", new encode());
        env.set("json", json);
        if (!env.get("package").isnil()) env.get("package").get("loaded").set("json", json);
        return NIL;
    }

    private class decode extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            return decode(arg.tojstring());
        }
    }

    private class encode extends OneArgFunction {
        @Override
        public LuaValue call(LuaValue arg) {
            return LuaValue.valueOf(encode(arg));
        }
    }

}

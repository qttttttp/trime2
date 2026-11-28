/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.theme;

import static com.osfans.trime.theme.ThemeManager.dp2px;

import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.fonts.Font;
import android.graphics.fonts.FontFamily;
import android.text.TextUtils;
import android.util.Log;
import android.view.Gravity;

import com.androlua.LuaBitmapDrawable;
import com.osfans.trime.Config;
import com.osfans.trime.util.Function;

import org.luaj.LuaTable;
import org.luaj.LuaValue;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

public class Style {

    private final LuaValue mTable;
    private final HashMap<String, Style> mStyleCache = new HashMap<>();
    private final HashMap<String, KeyStyle> mKeyStyleCache = new HashMap<>();

    // ---- 字体集合"系统字体优先"模式 ----
    // 集合第一项为此占位符时,首选系统字体(跟随系统/ROM 正在使用的字体),
    // 系统字体显示不了的字符按顺序落到集合后面的字体(API 29+ 原生逐字形回退)
    private static final String[] SYSTEM_FONT_TOKENS = {"system", "@system", "default", "系统字体", "默认字体"};
    private Typeface mNativeChain;          // 原生回退链(系统字体在最前), null = 未启用或构建失败
    private boolean mNativeChainChecked;

    public Style(LuaValue t) {
        mTable = t.isnil() ? new LuaTable() : t;
    }

    public Style(LuaValue t, Style def) {
        this(t);
        setStyle(def);
    }

    public void setMeta(LuaValue t) {
        LuaTable mt = new LuaTable();
        mt.set("__index", t);
        mTable.setmetatable(mt);
    }

    public void setStyle(Style t) {
        LuaTable mt = new LuaTable();
        mt.set("__index", t.getTable());
        mTable.setmetatable(mt);
    }

    public LuaValue getTable() {
        return mTable;
    }

    public int getColor(String key) {
        return mTable.get(key).toint();
    }

    public int getColor(String key, int def) {
        return mTable.get(key).optint(def);
    }

    public Drawable getDrawable(String key) {
        LuaValue v = mTable.get(key);
        // 预先计算好通用的圆角
        float radiusPx = dp2px((float) mTable.get("corner_radius").optdouble(0f));
        if (v.isint()) {
            return createGradientDrawable(v.toint(),radiusPx,dp2px((float) mTable.get("stroke_width").optdouble(0)), mTable.get("stroke_color").optint(0));
        } else if (v.isstring()) {
            File f=new File(Config.getStylePath(v.tojstring()));
            if(f.exists())
                return new LuaBitmapDrawable(f.getAbsolutePath());
            f=new File(Config.getImagePath(v.tojstring()));
            if(f.exists())
                return new LuaBitmapDrawable(f.getAbsolutePath());
        }
        return null;
    }

    public Drawable getDrawable(String key, int def) {
        LuaValue v = mTable.get(key);
        // 预先计算好通用的圆角
        float radiusPx = dp2px((float) mTable.get("corner_radius").optdouble(0f));
        if (v.isint()) {
            return createGradientDrawable(v.toint(),radiusPx,dp2px((float) mTable.get("stroke_width").optdouble(0)), mTable.get("stroke_color").optint(0));
        } else if (v.isstring()) {
            File f=new File(Config.getStylePath(v.tojstring()));
            if(f.exists())
                return new LuaBitmapDrawable(f.getAbsolutePath());
            f=new File(Config.getImagePath(v.tojstring()));
            if(f.exists())
                return new LuaBitmapDrawable(f.getAbsolutePath());
        }
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.RECTANGLE);
        drawable.setColor(v.optint(def));
        drawable.setCornerRadius(radiusPx);
        return drawable;
    }

    // 提取公共方法
    private Drawable createGradientDrawable(int color, float radius, int strokeWidth, int strokeColor) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.RECTANGLE);
        drawable.setColor(color);
        drawable.setCornerRadius(radius);

        // 添加边框逻辑
        if (strokeWidth > 0) {
            drawable.setStroke(strokeWidth, strokeColor);
        }

        return drawable;
    }

    public Style getStyle(String key) {
        Style style = mStyleCache.get(key);
        if (style == null) {
            style = new Style(mTable.get(key));
            mStyleCache.put(key, style);
        }
        return style;
    }
    public Style getStyle(int key) {
        Style style = mStyleCache.get(Integer.toString(key));
        if (style == null) {
            style = new Style(mTable.get(key+1));
            mStyleCache.put(Integer.toString(key), style);
        }
        return style;
    }
    public Style getStyle(String key, Style def) {
        if(TextUtils.isEmpty(key))
            return def;
        Style style = mStyleCache.get(key);
        if (style == null) {
            LuaValue v = mTable.get(key);
            if (!v.istable())
                return def;
            style = new Style(v, def);
            mStyleCache.put(key, style);
        }
        return style;
    }

    public KeyStyle getKeyStyle(String key){
        KeyStyle style = mKeyStyleCache.get(key);
        if (style == null) {
            LuaValue v = mTable.get(key);
            style = new KeyStyle(v);
            mKeyStyleCache.put(key, style);
        }
        return style;
    }

    public KeyStyle getKeyStyle(){
        String key="key";
        KeyStyle style = mKeyStyleCache.get(key);
        if (style == null) {
            LuaValue v = mTable.get(key);
            style = new KeyStyle(v);
            mKeyStyleCache.put(key, style);
        }
        return style;
    }

    public KeyStyle getKeyStyle(String key, KeyStyle def) {
        if(TextUtils.isEmpty(key))
            return def;
        KeyStyle style = mKeyStyleCache.get(key);
        if (style == null) {
            LuaValue v = mTable.get(key);
            if (!v.istable())
                return def;
            style = new KeyStyle(v, def);
            mKeyStyleCache.put(key, style);
        }
        return style;
    }


    public float getTextSize(int def) {
        return mTable.get("text_size").optint(def);
    }

    public int getTextColor(int def) {
        return mTable.get("text_color").optint(def);
    }

    public int getSize(String key, int def) {
        LuaValue o = mTable.get(key);
        if(!o.isint())
            return def;
        return dp2px(o.toint());
    }

    public Drawable getBackground(int def) {
        return getDrawable("background", def);
    }

    public int getBackgroundColor(int def) {
        return getColor("background", def);
    }

    public float getFloat(String key, float def) {
        return (float) mTable.get(key).optdouble(def);
    }

    public int getHeight(int def) {
        return getSize("height", def);
    }

    public int getWidth(int def) {
        return getSize("width", def);
    }

    public boolean hasKey(String key) {
        return !mTable.rawget(key).isnil();
    }

    public int getGravity(int def) {
        return parse(getString("gravity", ""), def);
    }
    public String getString(String key) {
        return mTable.get(key).optjstring("");
    }
    public String getString(String key, String def) {
        return mTable.get(key).optjstring(def);
    }

    // 建立字符串到常量值的映射表
    private static final Map<String, Integer> GRAVITY_MAP = new HashMap<>();

    static {
        GRAVITY_MAP.put("top", Gravity.TOP);
        GRAVITY_MAP.put("bottom", Gravity.BOTTOM);
        GRAVITY_MAP.put("left", Gravity.LEFT);
        GRAVITY_MAP.put("right", Gravity.RIGHT);
        GRAVITY_MAP.put("center", Gravity.CENTER);
        GRAVITY_MAP.put("center_vertical", Gravity.CENTER_VERTICAL);
        GRAVITY_MAP.put("center_horizontal", Gravity.CENTER_HORIZONTAL);
        GRAVITY_MAP.put("start", Gravity.START);
        GRAVITY_MAP.put("end", Gravity.END);
        // 可以根据需要继续添加 fill, clip_vertical 等
    }

    public static int parse(String gravityStr, int defaultGravity) {
        if (TextUtils.isEmpty(gravityStr)) return defaultGravity;

        int result = 0;
        // 支持类似 "center|bottom" 的写法
        String[] parts = gravityStr.toLowerCase().split("\\|");

        for (String part : parts) {
            String key = part.trim();
            if (GRAVITY_MAP.containsKey(key)) {
                result |= GRAVITY_MAP.get(key); // 按位或运算
            }
        }

        return result == 0 ? defaultGravity : result;
    }

    public LuaValue get(String key) {
        return mTable.get(key);
    }

    /** 是否为"系统字体"占位符 */
    private static boolean isSystemFontToken(String s) {
        if (TextUtils.isEmpty(s)) return false;
        s = s.trim().toLowerCase();
        for (String t : SYSTEM_FONT_TOKENS)
            if (t.equals(s)) return true;
        return false;
    }

    /** 解析 /system/etc/fonts.xml,取得系统默认字体(sans-serif)实际使用的字体文件 */
    private static File[] getSystemFontFiles() {
        java.io.FileInputStream in = null;
        try {
            in = new java.io.FileInputStream("/system/etc/fonts.xml");
            org.xmlpull.v1.XmlPullParser p = android.util.Xml.newPullParser();
            p.setInput(in, null);
            String aliasTo = null, collectFamily = null;
            java.util.LinkedHashSet<String> files = new java.util.LinkedHashSet<>();
            boolean inFont = false;
            int ev;
            while ((ev = p.next()) != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
                if (ev == org.xmlpull.v1.XmlPullParser.START_TAG) {
                    String tag = p.getName();
                    if ("family".equals(tag)) {
                        String name = p.getAttributeValue(null, "name");
                        if (name != null && (name.equals("sans-serif") || name.equals(aliasTo)))
                            collectFamily = name;
                    } else if ("alias".equals(tag)) {
                        if ("sans-serif".equals(p.getAttributeValue(null, "name")))
                            aliasTo = p.getAttributeValue(null, "to");
                    } else if ("font".equals(tag) && collectFamily != null) {
                        inFont = true;
                    }
                } else if (ev == org.xmlpull.v1.XmlPullParser.TEXT) {
                    if (inFont) {
                        String t = p.getText().trim();
                        if (!t.isEmpty()) files.add(t);
                        inFont = false;
                    }
                } else if (ev == org.xmlpull.v1.XmlPullParser.END_TAG) {
                    String tag = p.getName();
                    if ("font".equals(tag)) inFont = false;
                    else if ("family".equals(tag)) collectFamily = null;
                }
            }
            ArrayList<File> out = new ArrayList<>();
            for (String f : files) {
                File file = new File("/system/fonts", f);
                if (file.exists() && !out.contains(file)) out.add(file);
            }
            if (!out.isEmpty()) return out.toArray(new File[0]);
        } catch (Throwable t) {
            t.printStackTrace();
        } finally {
            try { if (in != null) in.close(); } catch (Exception ignored) {}
        }
        return null;
    }

    /** 构建系统字体家族(fonts.xml 解析出的当前系统字体文件) */
    private FontFamily buildSystemFamily() {
        File[] sys = getSystemFontFiles();
        if (sys == null) return null;
        try {
            FontFamily.Builder fb = new FontFamily.Builder(new Font.Builder(sys[0]).build());
            for (int i = 1; i < sys.length; i++) {
                try {
                    fb.addFont(new Font.Builder(sys[i]).build());
                } catch (Exception ignored) {}
            }
            return fb.build();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    /**
     * 原生逐字形回退链:font 表按顺序逐项入链,system 占位符出现在哪个位置,
     * 系统字体就排在哪个位置(可多次出现,重复的自动忽略)。
     * 渲染时由系统按字符自动回退。失败返回 null。
     */
    private Typeface getNativeChain() {
        if (mNativeChainChecked) return mNativeChain;
        mNativeChainChecked = true;
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q) return null;
        LuaValue n = get("font");
        if (n.isnil()) {
            n = ThemeManager.getStyle().getStyle("keyboard").get("font");
        }
        if (!n.istable() || n.length() < 1) return null;
        FontFamily sysFamily = buildSystemFamily();
        ArrayList<FontFamily> families = new ArrayList<>();
        for (int i = 1; i <= n.length(); i++) {
            String name = n.get(i).optjstring("").trim();
            if (isSystemFontToken(name)) {
                if (sysFamily != null && !families.contains(sysFamily))
                    families.add(sysFamily);
                continue;
            }
            if (TextUtils.isEmpty(name)) continue;
            try {
                File f = new File(Config.getFontPath(name));
                if (f.exists())
                    families.add(new FontFamily.Builder(new Font.Builder(f).build()).build());
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        if (families.isEmpty()) return null;
        try {
            Typeface.CustomFallbackBuilder b = new Typeface.CustomFallbackBuilder(families.get(0));
            for (int i = 1; i < families.size(); i++) {
                try {
                    b.addCustomFallback(families.get(i));
                } catch (Exception ignored) {}
            }
            // 系统字体文件解析失败时,兜底保证缺字总能用系统字体显示
            if (sysFamily == null) b.setSystemFallback("sans-serif");
            mNativeChain = b.build();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
        return mNativeChain;
    }

    public Typeface getFont(String key) {
        LuaValue n = get(key);
        if (n.isnil()) {
            n=ThemeManager.getStyle().getStyle("keyboard").get(key);
            if(n.isnil())
                return Typeface.DEFAULT;
        }
        if (n.istable()) {
            // "系统字体优先"模式:系统字体文件在链首,缺字由原生回退落到集合后面的字体
            if ("font".equals(key)) {
                Typeface nativeChain = getNativeChain();
                if (nativeChain != null) return nativeChain;
            }
            try {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    ArrayList<FontFamily> lt = new ArrayList<>();
                    for (int i = 1; i <= n.length(); i++) {
                        try {
                            File f = new File(Config.getFontPath(n.get(i).optjstring("")));
                            if(f.exists())
                                lt.add(new FontFamily.Builder(new Font.Builder(f).build()).build());
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }
                    if (lt.isEmpty())
                        return Typeface.DEFAULT;
                    Typeface.CustomFallbackBuilder tf = new Typeface.CustomFallbackBuilder(lt.get(0));
                    for (int i = 1; i < lt.size(); i++) {
                        tf.addCustomFallback(lt.get(i));
                    }
                    return tf.build();
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        String name = n.optjstring("");
        if (name != null) {
            try {
                File f = new File(Config.getFontPath(name));
                if (f.exists()) return Typeface.createFromFile(f);
            } catch (Exception e) {
                  e.printStackTrace();
            }
        }
        return Typeface.DEFAULT;
    }

    public int getInt(String s) {
        LuaValue i = get(s);
        if(i.isint())
            return i.toint();
        return 0;
    }
    public int getInt(String s,int def) {
        LuaValue i = get(s);
        if(i.isint())
            return i.toint();
        return def;
    }


    public boolean getBoolean(String s) {
        return get(s).optboolean(false);
    }
    public boolean getBoolean(String s,boolean def) {
        return get(s).optboolean(def);
    }

    public int getLength() {
        return mTable.length();
    }
}

/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime;

import android.content.Context;
import android.text.TextUtils;
import android.util.Log;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.androlua.LuaUtil;
import com.osfans.trime.core.Rime;
import com.osfans.trime.keyboard.AbsKeyboardView;
import com.osfans.trime.keyboard.FlexboxKeyboardView;
import com.osfans.trime.keyboard.KeyboardView;
import com.osfans.trime.keyboard.ModifierState;
import com.osfans.trime.keyboard.RowKeyboardView;
import com.osfans.trime.keyboard.SymbolsKeyboardView;
import com.osfans.trime.theme.ThemeManager;
import com.osfans.trime.util.Function;

import androidx.annotation.NonNull;

import org.luaj.Globals;
import org.luaj.LuaValue;
import org.luaj.lib.ResourceFinder;
import org.luaj.lib.jse.JsePlatform;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

public class InputView extends FrameLayout implements ResourceFinder {

    private View mKeyboardView;
    private Globals globals;
    private View oldView;

    // ===== 主题工作室数据桥接：当前键盘脚本执行后的 Globals 静态快照 =====
    // 同进程的 tools Lua（主题工作室）通过 ThemeDataBridge 读取它，拿到真实键盘布局，
    // 避免在工具沙箱里重跑键盘脚本。每次 setKeyboard 成功后更新。
    private static Globals sCurrentKeyboardGlobals;

    /** 主题工作室数据桥接：返回当前键盘 Globals（可能为空） */
    public static Globals getCurrentKeyboardGlobals() {
        return sCurrentKeyboardGlobals;
    }

    public InputView(@NonNull Context context) {
        super(context);
        setClipChildren(false);
        setClipToPadding(false);
        setKeyboard(Config.currentSchema());
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        try {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void setKeyboardView(KeyboardView keyboardView) {
        if (keyboardView.equals(mKeyboardView))
            return;
        if (keyboardView.isLock()) {
            mViewCache.put(".default", keyboardView);
        }
        oldView = mKeyboardView;
        mKeyboardView = keyboardView;
        ViewParent parent = keyboardView.getParent();
        if (parent != null && parent instanceof ViewGroup) {
            ((ViewGroup) parent).removeView(keyboardView);
        }
        Rime.setRimeOption("ascii_mode", keyboardView.isAsciiMode());
        setShifted(false);
        ModifierState.setShifted(false);
        ModifierState.setShiftLock(false);
        addView(keyboardView, 0, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        if (oldView != null) {
            // 旧键盘淡出
            oldView.animate()
                    .alpha(0f)
                    .setDuration(100)
                    .withLayer() // 动画期间使用硬件层加速
                    .withEndAction(() -> {
                        removeView(oldView);
                        oldView.setAlpha(1.0f); // 恢复状态以备下次复用
                    })
                    .start();
        }
    }

    private void setKeyboardView(View keyboardView) {
        oldView = mKeyboardView;
        mKeyboardView = keyboardView;
        ViewParent parent = keyboardView.getParent();
        if (parent != null && parent instanceof ViewGroup) {
            ((ViewGroup) parent).removeView(keyboardView);
        }
        addView(keyboardView, 0, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        if (oldView != null) {
            // 旧键盘淡出
            oldView.animate()
                    .alpha(0f)
                    .setDuration(100)
                    .withLayer() // 动画期间使用硬件层加速
                    .withEndAction(() -> {
                        removeView(oldView);
                        oldView.setAlpha(1.0f); // 恢复状态以备下次复用
                    })
                    .start();
        }
    }

    private String mCurrentSchemaId;

    /**
     * 进程内最近一次真正加载成功的键盘名（解析后的文件名，不含 .lua）。
     * RootInputView.setTheme/setSchema 会重建 InputView，新实例的 mViewCache 是空的；
     * 若此时 schema id 还没就绪（从设置页返回的瞬间很常见），解析链会拿空 id 去问主题，
     * 主题 get_keyboard("") 返回的往往是 keyboard 字段（如 qwerty36），键盘就被静默换掉。
     * 用静态字段跨实例保存，schema 拿不到时保持原键盘不动。
     */
    private static String sLoadedKeyboard;

    // 2. 视图缓存：SchemaId -> KeyboardView 实例
    private final Map<String, KeyboardView> mViewCache = new HashMap<>();
    private final Map<String, SymbolsKeyboardView> mSymbolsViewCache = new HashMap<>();

    public void setKeyboard(String id) {
        if (".last".equals(id)) {
            if (oldView != null)
                setKeyboardView(oldView);
            return;
        }
        boolean forceReload = false;
        if (".reload".equals(id)) {
            // 「重新应用键盘」：连视图缓存一起丢掉，让键盘脚本重跑一遍。
            // 用于设置里点「自动匹配」（偏好已清空，必须重算），
            // 以及任何要求把当前键盘完整重建的场合。
            mCurrentSchemaId = null;
            id = Config.currentSchema();
            // 从设置页返回的瞬间 schema 可能还没就绪，退到上一次真正加载的键盘名，
            // 至少把它重建一次，别让滑动接管一直丢着。
            if (TextUtils.isEmpty(id)) id = sLoadedKeyboard;
            if (TextUtils.isEmpty(id)) return;
            forceReload = true;
        }
        if (id == null || id.equals(mCurrentSchemaId)) return;
        // 只在真的要换/重建键盘时打一行，避免每次候选刷新刷屏
        Log.w("TAG", "setKeyboard:s " + id + (forceReload ? " (reload)" : ""));
        mCurrentSchemaId = id;
        id = getKeyboardId(id);
        if (forceReload) {
            // 解析后才是真正的键盘名（如 wanxiang），缓存键用的也是它
            mViewCache.remove(id);
            mSymbolsViewCache.remove(id);
        }
        sLoadedKeyboard = id;
        Log.w("TAG", "setKeyboard:e " + id + " (schema=" + mCurrentSchemaId + ")");
        // 获取或创建 KeyboardView
        KeyboardView targetView = mViewCache.get(id);
        if (targetView == null) {
            // 初始化 Lua 环境
            Globals globals = JsePlatform.standardGlobals();
            globals.finder = this;
            LuaValue func = globals.loadfilex(id + ".lua");
            try {
                if (func.isfunction()) {
                    LuaValue ret = func.call();
                    if (ret.isuserdata(View.class)) {
                        sCurrentKeyboardGlobals = globals;  // 主题工作室数据桥接
                        setKeyboardView(ret.touserdata(View.class));
                        return;
                    }
                } else {
                    ThemeManager.sendMsg("setKeyboard " + func.tojstring());
                }
            } catch (Exception e) {
                ThemeManager.sendMsg("setKeyboard " + e);
            }
            //Log.w("TAG", "setKeyboard: "+globals.checktable().dump().tojstring() );
            // 主题工作室数据桥接：保存当前键盘 Globals 静态快照
            sCurrentKeyboardGlobals = globals;
            // 创建并存入缓存
            if (globals.get("rows").istable()) {
                targetView = new RowKeyboardView(getContext(), globals);
            } else if (globals.get("flex_box").istable()) {
                targetView = new FlexboxKeyboardView(getContext(), globals);
            } else if (globals.get("keys").istable()) {
                targetView = new AbsKeyboardView(getContext(), globals);
            } else if (globals.get("key_maps").istable()) {
                SymbolsKeyboardView symbolsView = mSymbolsViewCache.get(id);
                if (symbolsView == null) {
                    symbolsView = new SymbolsKeyboardView(getContext(), globals);
                    mSymbolsViewCache.put(id, symbolsView);
                }
                TrimeService.getInstance().showCustomView(symbolsView);
                mCurrentSchemaId = null;
                return;
            } else {
                func = globals.loadfilex("themes/default/keyboards/qwerty36.lua");
                if (func.isfunction())
                    func.call();
                targetView = new RowKeyboardView(getContext(), globals);
            }
            mViewCache.put(id, targetView);
        }
        setKeyboardView(targetView);
    }

    private String getKeyboardId(String id) {
        String schemaId = Config.currentSchema();

        // 调用方直接指定了具体键盘名（主题脚本 setKeyboard、上次的视图 id 等）：
        // 这是运行时的显式切换，不是「默认键盘解析」，不改偏好。
        if (!TextUtils.isEmpty(id) && !id.equals(schemaId) && kbdFileExists(id)) {
            Log.w("TAG", "setKeyboard: 指定键盘 " + id);
            return id;
        }

        // schema 拿不到时（从设置页返回、Rime 尚未就绪、setTheme 重建的瞬间），
        // 绝不能拿空 id 去问主题：主题 get_keyboard("") 走的是 `id == ""` 分支，
        // 返回 keyboard 字段，和「按方案 id 求值」是两条不同的路径，结果常常就是 qwerty36。
        // 这正是「只打开默认键盘对话框、什么都不选，键盘却变了」的来源。
        if (TextUtils.isEmpty(schemaId)) {
            if (!TextUtils.isEmpty(id) && kbdFileExists(id)) {
                Log.w("TAG", "setKeyboard: schema 为空，沿用参数 " + id);
                return id;
            }
            if (!TextUtils.isEmpty(sLoadedKeyboard) && kbdFileExists(sLoadedKeyboard)) {
                Log.w("TAG", "setKeyboard: schema 为空，保持上次键盘 " + sLoadedKeyboard);
                return sLoadedKeyboard;
            }
            Log.w("TAG", "setKeyboard: schema 为空且无可用键盘，暂不重算");
            return "qwerty36";
        }
        if (TextUtils.isEmpty(id)) id = schemaId;

        // ① 偏好里已有记录：设置里手选的值，或上一次 auto 解析后回写的值。
        //    偏好是唯一事实来源，解析链只在「没有记录 / 记录失效 / 点了自动匹配」时执行。
        String picked = stripLua(Config.getKeyboard(schemaId));
        if (!TextUtils.isEmpty(picked)) {
            if (kbdUsable(picked)) {
                Log.w("TAG", "setKeyboard: 偏好 " + picked);
                return picked;
            }
            Log.w("TAG", "setKeyboard: 偏好 " + picked + " 无对应文件，重新解析");
        }

        // ② auto：方案名同名键盘优先
        Log.w("TAG", "setKeyboard:auto " + schemaId);
        if (kbdUsable(schemaId))
            return rememberKeyboard(schemaId, schemaId);

        // ③ 方案没有同名键盘，才问主题 get_keyboard(id, alphabet)
        String themed = schemaId;
        try {
            themed = ThemeManager.getKeyboard(schemaId, false);
        } catch (Throwable t) {
            Log.w("TAG", "setKeyboard:theme " + t);
        }
        themed = stripLua(themed);
        Log.w("TAG", "setKeyboard:theme " + schemaId + " -> " + themed);
        if (!TextUtils.isEmpty(themed) && kbdUsable(themed))
            return rememberKeyboard(schemaId, themed);

        // ④ 兜底：解析全失败时，不要用一个 36 键覆盖正在正常显示的键盘。
        //    打开设置页再返回会触发 setTheme 重建，重建瞬间 schema 可能还没就绪，
        //    旧逻辑会一路落到 qwerty36，看起来就是「没做任何操作，键盘被换了」。
        if (!TextUtils.isEmpty(sLoadedKeyboard) && kbdFileExists(sLoadedKeyboard)) {
            Log.w("TAG", "setKeyboard: 解析失败，保持当前 " + sLoadedKeyboard);
            return sLoadedKeyboard;
        }
        Log.w("TAG", "setKeyboard:fallback qwerty36");
        return rememberKeyboard(schemaId, "qwerty36");
    }

    private boolean kbdFileExists(String name) {
        if (TextUtils.isEmpty(name)) return false;
        try {
            String f = name.endsWith(".lua") ? name : name + ".lua";
            if (f.startsWith("/")) return new File(f).exists();
            if (new File(Config.getKeyboardDir(), f).exists()) return true;
            // 少数主题把键盘直接放在主题根目录，而不是 keyboards/ 子目录
            return new File(Config.getThemeDir(Config.getTheme()), f).exists();
        } catch (Throwable t) {
            return false;
        }
    }

    private boolean kbdUsable(String name) {
        return !TextUtils.isEmpty(name) && (mViewCache.containsKey(name) || kbdFileExists(name));
    }

    private static String stripLua(String s) {
        if (s == null) return "";
        return s.endsWith(".lua") ? s.substring(0, s.length() - 4) : s;
    }

    /**
     * 把本次解析出的最终键盘写回偏好。
     * 值没变就不写，避免每次进输入法都碰 SharedPreferences。
     */
    private String rememberKeyboard(String schemaId, String file) {
        if (TextUtils.isEmpty(schemaId) || TextUtils.isEmpty(file)) return file;
        try {
            String old = Config.getKeyboard(schemaId);
            if (!file.equals(old))
                Config.setKeyboard(schemaId, file);
        } catch (Throwable t) {
            Log.w("TAG", "setKeyboard: remember " + t);
        }
        return file;
    }

    @Override
    public InputStream findResource(String name) {
        if (TextUtils.isEmpty(name))
            return null;
        try {
            if (new File(name).exists())
                return new FileInputStream(name);
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        try {
            return new FileInputStream(new File(Config.getKeyboardDir(), name));
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        // 主题根目录也作为搜索根：部分主题的键盘不放在 keyboards/ 子目录
        try {
            File f = new File(Config.getThemeDir(Config.getTheme()), name);
            if (f.exists())
                return new FileInputStream(f);
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        if (!name.endsWith(".lua"))
            return null;
        try {
            return getContext().getAssets().open("themes/default/keyboards/" + name);
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        try {
            //name = name.replace(".lua", "");
            //if (!name.startsWith("themes/default/") && !TextUtils.isEmpty(name)) {
            //    //Toast.makeText(getContext(), "未找到 " + name, Toast.LENGTH_SHORT).show();
            //    return null;
            //}
            return getContext().getAssets().open(name);
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        return null;
    }

    @Override
    public String findFile(String filename) {
        if (TextUtils.isEmpty(filename))
            return null;
        if (filename.startsWith("/"))
            return filename;
        File f = new File(Config.getKeyboardDir(), filename);
        if (f.exists())
            return f.getAbsolutePath();
        File g = new File(Config.getThemeDir(Config.getTheme()), filename);
        if (g.exists())
            return g.getAbsolutePath();
        return f.getAbsolutePath();
    }

    public void invalidateComposingKeys() {
        if (mKeyboardView instanceof KeyboardView)
            ((KeyboardView) mKeyboardView).invalidateComposingKeys();
    }

    public void invalidateAllKeys() {
        if (mKeyboardView instanceof KeyboardView)
            ((KeyboardView) mKeyboardView).invalidateAllKeys();
        //for (KeyboardView value : mViewCache.values()) {
        //    value.invalidateAllKeys();
        //}
    }

    public boolean isShifted() {
        return ModifierState.isShifted();
    }

    public void setShifted(boolean shifted) {
        if (mKeyboardView instanceof KeyboardView)
            ((KeyboardView) mKeyboardView).setShifted(shifted);
    }

    public void setAsciiMode(boolean asciiMode) {
        if (mKeyboardView instanceof KeyboardView)
            ((KeyboardView) mKeyboardView).setAsciiMode(asciiMode);
    }

    public View getKeyboardView() {
        return mKeyboardView;
    }
}

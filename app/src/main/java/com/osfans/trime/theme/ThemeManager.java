/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.theme;

import static android.content.res.Configuration.UI_MODE_NIGHT_MASK;
import static android.content.res.Configuration.UI_MODE_NIGHT_YES;

import android.content.Context;
import android.content.res.Resources;
import android.media.AudioAttributes;
import android.media.SoundPool;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;

import com.androlua.LuaApplication;
import com.androlua.LuaUtil;
import com.osfans.trime.AiClient;
import com.osfans.trime.BuildConfig;
import com.osfans.trime.Config;
import com.osfans.trime.Key;
import com.osfans.trime.TrimeService;
import com.osfans.trime.core.Rime;
import com.osfans.trime.core.RimeSchema;
import com.osfans.trime.enums.InlineModeType;
import com.osfans.trime.editor.LuaPatchManager;
import com.osfans.trime.util.Function;

import org.luaj.Globals;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.ResourceFinder;
import org.luaj.lib.jse.JsePlatform;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class ThemeManager {

    private static final int mCandidateHeight = 48;
    private static final int mKeyboardHeight = 240;

    private static Globals mGlobals;
    private static LuaTable mColor;
    private static Style mStyle;
    private static Vibrator vibrator;
    private static SoundPool mSoundPool;
    private static InlineModeType mInlineModeType = null;
    private static AiClient mAiClient;
    private static AiClient mAsrClient;
    private static AiClient mAsrClient2;

    public static ResourceFinder getFinder() {
        return mResourceFinder;
    }

    public static Globals getGlobals() {
        return mGlobals;
    }

    /** 主题工作室数据桥接：暴露当前配色表（配色脚本执行后的最终 LuaTable） */
    public static LuaTable getColor() {
        return mColor;
    }

    public static void vibrate(VibrationEffect ve) {
        if (vibrator == null) {
            Context context = LuaApplication.getInstance();
            if (context != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    VibratorManager vibratorManager = (VibratorManager) context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
                    vibrator = vibratorManager.getDefaultVibrator();
                } else {
                    vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
                }
            }
        }
        if (vibrator != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(ve);
            }
        }
    }

    private final static ResourceFinder mResourceFinder = new ResourceFinder() {
        @Override
        public InputStream findResource(String name) {
            if (TextUtils.isEmpty(name)) {
                try {
                    return LuaApplication.getInstance().getAssets().open("themes/default/main.lua");
                } catch (Exception ioe) {
                    ioe.printStackTrace();
                }
                return null;
            }
            try {
                if (name.startsWith("themes/default/"))
                    return LuaApplication.getInstance().getAssets().open(name);
            } catch (Exception ioe) {
                ioe.printStackTrace();
            }
            try {
                if (new File(name).exists())
                    return new FileInputStream(name);
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                File f = new File(Config.getThemeDir(), Config.getTheme() + "/" + name);
                if (f.exists())
                    return new FileInputStream(f);
            } catch (Exception e) {
                e.printStackTrace();
            }
            if (!name.endsWith(".lua"))
                return null;
            /*try {
                return LuaApplication.getInstance().getAssets().open("themes/default/"+name);
            } catch (Exception ioe) {
                ioe.printStackTrace();
            }*/
            return null;
        }

        @Override
        public String findFile(String filename) {
            if (TextUtils.isEmpty(filename))
                return null;
            if (filename.startsWith("/"))
                return filename;
            return new File(Config.getThemeDir(), filename).getAbsolutePath();
        }
    };

    public static void setTheme(String name) {
        mStyle = null;
        clearSound();
        Config.setTheme(name);
        mGlobals = JsePlatform.standardGlobals();
        mGlobals.finder = mResourceFinder;
        try {
            File base = new File(Config.getThemeDir(name), "main.lua");
            if (!base.isFile()) base = new File("main.lua");
            LuaValue func = mGlobals.loadfilex(base.isFile() ? base.getAbsolutePath() : "main.lua");
            if (func.isfunction()) {
                func.call();
                try { LuaPatchManager.applyFile(mGlobals, mGlobals, base); }
                catch (Exception e) { sendMsg("主题补丁: " + e); }
            } else {
                sendMsg("setTheme " + func.tojstring());
                func = mGlobals.loadfilex("themes/default/main.lua");
                if (func.isfunction())
                    func.call();
            }
        } catch (Exception e) {
            sendMsg("setTheme " + e.toString());
        }
        String styleName = Function.loadString(LuaApplication.getInstance(), Config.getStyleKey(name), mGlobals.get("style").optjstring("light"));
        setStyle(styleName);
        Key.presetKeys = getPresetKeys();
        loadAiClient();
        loadAsrClient();
        loadAsrClient2();
        //Style candidate = getStyle().getStyle("candidate");
        //Rime.setRimeOption("_hide_candidate",!candidate.get("show").optboolean(true));
        //Style comment = getStyle().getStyle("candidate").getStyle("comment");
        //Rime.setRimeOption("_hide_comment",!comment.get("show").optboolean(true));
    }

    public static void sendMsg(String s) {
        TrimeService trime = TrimeService.getInstance();
        if (trime != null)
            trime.sendMsg(s);
    }

    public static void setStyle(String name) {
        mStyle = null;
        mInlineModeType = null;
        clearSound();
        Config.setStyle(name);
        mColor = new LuaTable(mGlobals);
        LuaTable mt = new LuaTable(mGlobals);
        mt.set("__index", mGlobals);
        mColor.setmetatable(mt);
        String path = "styles/" + name + "/main.lua";
        try {
            File base = new File(Config.getStyleDir(name), "main.lua");
            if (!base.isFile()) base = new File(path);
            LuaValue func = mGlobals.loadfilex(base.isFile() ? base.getAbsolutePath() : path, mColor);
            if (func.isfunction()) {
                func.call();
                try { LuaPatchManager.applyFile(mGlobals, mColor, base); }
                catch (Exception e) { sendMsg("配色补丁: " + e); }
                return;
            } else {
                sendMsg("setStyle " + func.tojstring());
            }
        } catch (Exception e) {
            sendMsg("setStyle " + e);
        }
        try {
            LuaValue func = mGlobals.loadfilex("themes/default/styles/light/main.lua", mColor);
            if (func.isfunction()) {
                func.call();
            }
        } catch (Exception e) {
            Log.e("theme", "setStyle: " + e);
        }
    }

    public static Style getStyle() {
        if (mStyle == null)
            mStyle = new Style(mColor);
        return mStyle;
    }

    public static int getHeight() {
        if (Rime.getRimeOption("_hide_candidate"))
            return getStyle().getSize("height", mCandidateHeight + mKeyboardHeight) - getStyle().getStyle("keyboard").getSize("height", mKeyboardHeight) - getStyle().getStyle("candidate").getSize("height", mCandidateHeight) + getKeyboardHeight();
        return getStyle().getSize("height", mCandidateHeight + mKeyboardHeight) - getStyle().getStyle("keyboard").getSize("height", mKeyboardHeight) - getStyle().getStyle("candidate").getSize("height", mCandidateHeight) + getKeyboardHeight() + getCandidateHeight();
    }

    public static int getContentHeight() {
        if (Rime.getRimeOption("_hide_candidate"))
            return getKeyboardHeight();
        return getCandidateHeight() + getKeyboardHeight();
    }

    public static int getRawContentHeight() {
        if (Rime.getRimeOption("_hide_candidate"))
            return getStyle().getStyle("keyboard").getSize("height", mKeyboardHeight);
        return getStyle().getStyle("keyboard").getSize("height", mKeyboardHeight) + getStyle().getStyle("candidate").getSize("height", mCandidateHeight);
    }

    public static int getCandidateHeight() {
        return (int) (getStyle().getStyle("candidate").getSize("height", mCandidateHeight) * Math.min(1, Config.getKeyboardHeightScale()));
    }

    public static int getKeyboardHeight() {
        return (int) (getStyle().getStyle("keyboard").getSize("height", mKeyboardHeight) * Config.getKeyboardHeightScale());
    }

    public static InlineModeType getInlinePreedit() {
        if (mInlineModeType != null)
            return mInlineModeType;
        switch (mStyle.getStyle("preedit").getString("inline", "none")) {
            case "preview":
            case "true":
                mInlineModeType = InlineModeType.INLINE_PREVIEW;
                break;
            case "preedit":
            case "composition":
                mInlineModeType = InlineModeType.INLINE_COMPOSITION;
                break;
            case "input":
                mInlineModeType = InlineModeType.INLINE_INPUT;
                break;
            default:
                mInlineModeType = InlineModeType.INLINE_NONE;
                break;
        }
        return mInlineModeType;
    }

    private static final DisplayMetrics mDisplayMetrics = Resources.getSystem().getDisplayMetrics();

    public static int dp2px(float f) {
        return (int) (TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP, f, mDisplayMetrics));
    }


    public static LuaValue getPresetKeys() {
        LuaTable keys = mGlobals.get("preset_keys").opttable(new LuaTable());
        LuaTable env = new LuaTable();
        try {
            env.setmetamethod("__index", mGlobals);
            LuaValue func = mGlobals.loadfilex("themes/default/main.lua", env);
            if (func.isfunction())
                func.call();
        } catch (Exception e) {
            e.printStackTrace();
            return keys;
        }
        if (env.rawget("preset_keys").istable())
            keys.setmetamethod("__index", env.get("preset_keys").opttable(new LuaTable()));
        return keys;
    }

    public static String getActionLabel(String key, String def) {
        LuaValue action = mGlobals.get("action_labels");
        if (!action.istable())
            return def;
        return action.get(key).optjstring(def);
    }

    public static int getDialogTheme() {
        if ((LuaApplication.getInstance().getResources().getConfiguration().uiMode & UI_MODE_NIGHT_MASK) == UI_MODE_NIGHT_YES) {
            return android.R.style.Theme_DeviceDefault_Dialog_Alert;
        } else {
            return android.R.style.Theme_DeviceDefault_Light_Dialog_Alert;
        }
    }

    public static String getKeyboard(String id) {
        return getKeyboard(id, true);
    }

    /**
     * @param usePref false = 只执行主题 get_keyboard(id, alphabet)，完全不看偏好。
     *                InputView 里「显式选择 → 方案同名 → 主题」的顺序由它自己控制，
     *                这里传 false 才能保证中间层不会把偏好偷偷插回来。
     */
    public static String getKeyboard(String id, boolean usePref) {
        if (usePref) {
            // 必须用调用方传进来的 id 读偏好。
            // 旧实现是无参 Config.getKeyboard()，它内部用 Rime.getCurrentRimeSchema() 拼键；
            // 从设置页返回、Rime 尚未就绪的瞬间该值是 ".default"，于是读到的是
            // <主题>_.default_keyboard（历史镜像键，里面可能躺着 qwerty36），
            // 主题 get_keyboard 被跳过，键盘被静默换掉。
            String k = Config.getKeyboard(id);
            Log.w("theme", "getKeyboard:Config " + id + ";" + k);
            // 偏好里存的是当前实际键盘；只有对应文件真的存在才算数，
            // 否则回退主题 get_keyboard()，避免拿一个不存在的文件名去 loadfile。
            if (!TextUtils.isEmpty(k)) {
                if (new File(Config.getKeyboardPath(k)).exists())
                    return k;
                Log.w("theme", "getKeyboard: 偏好 " + k + " 无对应键盘文件，回退主题 get_keyboard()");
            }
        }
        LuaValue fun = mGlobals.get("get_keyboard");
        if (fun.isfunction()) {
            try {
                String alphabet = "abcdefghijklmnopqrstuvwxyz";
                try {
                    RimeSchema schema = new RimeSchema(id);
                    alphabet = schema.getAlphabet();
                } catch (Exception e) {
                    File f = new File(Config.getUserDataDir(), id + ".schema.yaml");
                    if (f.exists()) {
                        String input = new String(LuaUtil.readAll(f.getAbsolutePath()));
                        String regex = "alphabet:\\s*(.*)";
                        Pattern pattern = Pattern.compile(regex);
                        Matcher matcher = pattern.matcher(input);
                        if (matcher.find()) {
                            // matcher.group(1) 提取第一个括号内的内容
                            String result = matcher.group(1);
                            if (!TextUtils.isEmpty(result)) {
                                alphabet = result;
                                Log.w("theme", "getKeyboard:alphabet " + alphabet);
                            }
                        }
                    }

                }
                LuaValue ret = fun.call(LuaValue.valueOf(id), LuaValue.valueOf(alphabet));
                Log.w("theme", "getKeyboard:ret " + ret);
                if (ret.isstring())
                    id = ret.tojstring();
            } catch (Exception e) {
                if (BuildConfig.DEBUG)
                    e.printStackTrace();
            }
        }
        return id;
    }

    public static int loadSound(String soundPath) {
        Log.w("theme", "loadSound: " + soundPath);
        if (mSoundPool == null) {
            AudioAttributes attributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA) // 提示音类型
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
            mSoundPool = new SoundPool.Builder()
                    .setMaxStreams(5) // 允许同时播放 5 个声音（防止连打时截断）
                    .setAudioAttributes(attributes)
                    .build();
            mSoundPool.setOnLoadCompleteListener(new SoundPool.OnLoadCompleteListener() {
                @Override
                public void onLoadComplete(SoundPool soundPool, int sampleId, int status) {
                    //if (status != 0) {
                    // status 为 0 表示成功，非 0 表示失败
                    Log.e("SoundHelper", "加载失败！ID: " + sampleId + " 状态码: " + status);
                    //}
                }
            });
        }
        // 检查文件是否存在
        java.io.File file = new java.io.File(soundPath);
        if (!file.exists()) {
            Log.e("SoundHelper", "文件根本不存在: " + soundPath);
            return -1;
        }
        return mSoundPool.load(soundPath, 1);
    }

    public static void play(int soundId) {
        if (mSoundPool != null && soundId > 0) {
            // 参数依次为：左声道、右声道、优先级、循环、速率
            mSoundPool.play(soundId, 1.0f, 1.0f, 1, 0, 1.0f);
        }
    }

    public static void clearSound() {
        if (mSoundPool != null) {
            mSoundPool.release();
            mSoundPool = null;
        }
    }

    public static Object callFunction(String s, Object... args) {
        if (mGlobals == null)
            return null;
        LuaValue f = mGlobals.get(s);
        if (f.isfunction()) {
            try {
                return f.jcall(args);
            } catch (Throwable e) {
                // 主题脚本里的 Lua 错误(如 attempt to index nil)原来会直接穿透
                // 到调用方所在的主线程,变成 FATAL EXCEPTION 让输入法崩掉。
                // 这里统一吞掉并记录:message 里带 chunk 和行号,方便定位。
                Log.e("ThemeManager", "callFunction " + s + " failed: " + e.getMessage(), e);
                return null;
            }
        }
        return null;
    }


    private static void loadAiClient() {
        mAiClient = null;
        LuaValue aiConfig = mGlobals.get("ai_config");
        if (aiConfig.istable()) {
            LuaValue base_url = aiConfig.get("base_url");
            if (!base_url.isstring() || base_url.length() == 0)
                return;
            LuaValue model = aiConfig.get("model");
            if (!model.isstring() || model.length() == 0)
                return;
            LuaValue key = aiConfig.get("key");
            if (!key.isstring() || key.length() == 0)
                return;
            LuaValue mSystemPrompt = aiConfig.get("system_prompt");
            LuaValue mExtraParams = aiConfig.get("extra_params");

            mAiClient = new AiClient(base_url.tojstring(), key.tojstring());
            mAiClient.setModel(model.tojstring());
            if (mSystemPrompt.isstring() && mSystemPrompt.length() > 0) {
                mAiClient.setSystemPrompt(mSystemPrompt.tojstring());
            }
            if (mExtraParams.isstring()) {
                mAiClient.setExtraParams(mExtraParams.tojstring());
            } else if (mExtraParams.istable()) {
                mAiClient.setExtraParams(org.luaj.android.json.encode(mExtraParams));
            }
        }
    }

    private static void loadAsrClient() {
        mAsrClient = buildAsrClient("asr_config");
    }

    /** 第二套 ASR 配置,供语音引擎里的 ai2 选项使用;与 ai_config(聊天)完全隔离 */
    private static void loadAsrClient2() {
        mAsrClient2 = buildAsrClient("asr_config2");
    }

    /** 从主题里的某份 ASR 配置表创建 client;表缺失或字段不全返回 null(该引擎选项就不显示) */
    private static AiClient buildAsrClient(String tableName) {
        LuaValue aiConfig = mGlobals.get(tableName);
        if (!aiConfig.istable()) return null;
        LuaValue base_url = aiConfig.get("base_url");
        if (!base_url.isstring() || base_url.length() == 0) return null;
        LuaValue model = aiConfig.get("model");
        if (!model.isstring() || model.length() == 0) return null;
        LuaValue key = aiConfig.get("key");
        if (!key.isstring() || key.length() == 0) return null;
        LuaValue mSystemPrompt = aiConfig.get("system_prompt");
        LuaValue mPrompt = aiConfig.get("prompt");
        LuaValue mExtraParams = aiConfig.get("extra_params");

        AiClient client = new AiClient(base_url.tojstring(), key.tojstring());
        client.setModel(model.tojstring());
        // 可选:api="transcriptions" 强制走 /audio/transcriptions;
        // 留空则按模型名自动判断(SenseVoice / whisper / ASR 视为专用识别模型)
        LuaValue api = aiConfig.get("api");
        if (api.isstring() && api.length() > 0) {
            client.setTranscribeMode(api.tojstring().toLowerCase().contains("transcri"));
        }
        if (mPrompt.isstring() && mPrompt.length() > 0) {
            client.setPrompt(mPrompt.tojstring());
        }
        if (mSystemPrompt.isstring() && mSystemPrompt.length() > 0) {
            client.setSystemPrompt(mSystemPrompt.tojstring());
        }
        if (mExtraParams.isstring()) {
            client.setExtraParams(mExtraParams.tojstring());
        } else if (mExtraParams.istable()) {
            client.setExtraParams(org.luaj.android.json.encode(mExtraParams));
        }
        return client;
    }

    public static AiClient getAiClient() {
        return mAiClient;
    }

    public static AiClient getAsrClient() {
        return mAsrClient;
    }

    public static AiClient getAsrClient2() {
        return mAsrClient2;
    }

    /**
     * 按语音引擎存储值取对应 client:
     *   "ai1"  → 第一套 asr_config
     *   "ai2"  → 第二套 asr_config2
     * 其它值返回 null(由 Speech 走 vivo/系统默认分支)。
     */
    public static AiClient getAsrClientForEngine(String engine) {
        if ("ai1".equals(engine) || "ai".equals(engine)) return mAsrClient;       // "ai" 为旧值,兼容映射到第一套
        if ("ai2".equals(engine) || "ai语音引擎".equals(engine)) return mAsrClient2; // "ai语音引擎" 为旧值,映射到第二套
        return null;
    }

    /** 供外部(如 Speech)在主题配置变化后强制重建 ASR 客户端(两套一起重建) */
    public static void reloadAsrClient() {
        if (mGlobals != null) {
            loadAsrClient();
            loadAsrClient2();
        }
    }

    /**
     * 返回两份 ASR 配置关键字段的签名字符串,供 Speech 在 start() 时比对,
     * 任一配置变化就触发两套 client 重建,实现即时生效。
     */
    public static String getAsrConfigSignature() {
        if (mGlobals == null) return "";
        StringBuilder sb = new StringBuilder();
        String[] keys = {"type", "base_url", "model", "key", "api", "prompt", "system_prompt"};
        for (String table : new String[]{"asr_config", "asr_config2"}) {
            LuaValue cfg = mGlobals.get(table);
            sb.append('[').append(table).append(']');
            if (cfg.istable()) {
                for (String k : keys) {
                    LuaValue v = cfg.get(k);
                    sb.append(k).append('=').append(v.isstring() ? v.tojstring() : v.typename()).append(';');
                }
            } else {
                sb.append("none");
            }
        }
        return sb.toString();
    }
}

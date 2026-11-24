/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.theme;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffColorFilter;
import android.graphics.Typeface;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.VibrationEffect;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.TextUtils;
import android.text.style.DynamicDrawableSpan;
import android.text.style.ImageSpan;
import android.view.Gravity;

import com.androlua.LuaApplication;
import com.androlua.LuaBitmap;
import com.androlua.LuaBitmapDrawable;
import com.osfans.trime.Config;

import org.luaj.LuaValue;

import java.io.File;
import java.io.IOException;
import java.util.HashMap;

/**
 * 缓存优化的 KeyStyle
 * 针对高频访问的属性（如动画参数、颜色）进行了字段级缓存，避免重复查询 LuaTable。
 */
public class KeyStyle extends Style {
    // 默认常量
    private static final int DEFAULT_TEXT_COLOR = 0xff000000;
    private static final int DEFAULT_TEXT_SIZE = 18;
    private static final int DEFAULT_BG_COLOR = 0xffffffff;

    // --- 缓存字段 ---
    // 使用基本类型避免装箱开销，使用 -1 或特定初值标记未缓存状态
    private float mTextSize = -1;
    private int mTextColor = 0;
    private boolean mHasCachedTextColor = false;

    private int mBackgroundColor = 0;
    private boolean mHasCachedBgColor = false;

    private float mScaleX = Float.NaN; // 使用 NaN 标记未缓存
    private float mScaleY = Float.NaN;
    private float mTranslationX = Float.MIN_VALUE; // 使用极小值标记未缓存
    private float mTranslationY = Float.MIN_VALUE;
    private float mTranslationZ = Float.MIN_VALUE;

    private int mElevation = -1;
    private int mShadowColor = 0;
    private boolean mHasCachedShadowColor = false;

    // 样式引用缓存
    private KeyStyle mHintStyle, mLongClickStyle, mPressedStyle;
    private int mGravity = -1;
    private VibrationEffect mVibrationEffect;
    private boolean mHasCachedVibrationEffect;
    private boolean mHasCachedVibrationEnabled;
    private boolean mVibrationEnabled;
    private int mSoundEffect = -1;
    private boolean mHasCachedSoundEffect;
    private boolean mHasCachedSoundEnabled;
    private boolean mSoundEnabled;
    private long mLongClickTime;
    private long mRepeatClickTime;
    private Typeface mTypeface;
    private boolean mShow;
    private boolean mHasCachedShow;
    private final HashMap<String, CharSequence> mSpanCache = new HashMap<>();

    public KeyStyle(LuaValue t) {
        super(t);
        getSoundEffect();
    }

    public KeyStyle(LuaValue t, Style def) {
        this(t);
        setStyle(def);
    }

    // --- 核心属性获取（带缓存逻辑） ---

    public float getTextSize() {
        if (mTextSize < 0) {
            mTextSize = getTextSize(DEFAULT_TEXT_SIZE);
        }
        return mTextSize;
    }

    public int getTextColor() {
        if (!mHasCachedTextColor) {
            mTextColor = getTextColor(DEFAULT_TEXT_COLOR);
            mHasCachedTextColor = true;
        }
        return mTextColor;
    }

    public int getBackgroundColor() {
        if (!mHasCachedBgColor) {
            mBackgroundColor = getColor("background", DEFAULT_BG_COLOR);
            mHasCachedBgColor = true;
        }
        return mBackgroundColor;
    }

    public Drawable getBackground() {
        // Drawable 涉及对象创建，由父类实现或按需获取，此处通常不适合在 Style 中长期常驻缓存
        return getBackground(DEFAULT_BG_COLOR);
    }

    // --- 动画相关属性（极高频调用） ---

    public float getScaleX() {
        if (Float.isNaN(mScaleX)) {
            mScaleX = getFloat("scale_x", 1.0f);
        }
        return mScaleX;
    }

    public float getScaleY() {
        if (Float.isNaN(mScaleY)) {
            mScaleY = getFloat("scale_y", 1.0f);
        }
        return mScaleY;
    }

    public float getTranslationX() {
        if (mTranslationX == Float.MIN_VALUE) {
            mTranslationX = getSize("translation_x", 0);
        }
        return mTranslationX;
    }

    public float getTranslationY() {
        if (mTranslationY == Float.MIN_VALUE) {
            mTranslationY = getSize("translation_y", 0);
        }
        return mTranslationY;
    }

    public float getTranslationZ() {
        if (mTranslationZ == Float.MIN_VALUE) {
            mTranslationZ = getSize("translation_z", 0);
        }
        return mTranslationZ;
    }

    // --- 其他样式属性 ---

    public int getElevation() {
        if (mElevation < 0) {
            mElevation = getSize("elevation", 0);
        }
        return mElevation;
    }

    public int getShadowColor() {
        if (!mHasCachedShadowColor) {
            mShadowColor = getColor("shadow_color", 0);
            mHasCachedShadowColor = true;
        }
        return mShadowColor;
    }

    public int getGravity() {
        if (mGravity == -1) {
            mGravity = getGravity(Gravity.CENTER);
        }
        return mGravity;
    }


    // --- 嵌套样式引用缓存 ---

    public KeyStyle getHintKeyStyle() {
        if (mHintStyle == null) mHintStyle = getKeyStyle("hint", this);
        return mHintStyle;
    }

    public KeyStyle getLongClickKeyStyle() {
        if (mLongClickStyle == null) mLongClickStyle = getKeyStyle("long_click", this);
        return mLongClickStyle;
    }

    public KeyStyle getPressedStyle() {
        if (mPressedStyle == null) mPressedStyle = getKeyStyle("pressed", this);
        return mPressedStyle;
    }

    public VibrationEffect getVibrationEffect() {
        if (!mHasCachedVibrationEffect) {
            mHasCachedVibrationEffect = true;
            LuaValue ve = get("vibration_effect");

            if (ve.istable()) {
                LuaValue vt = ve.get(1); // 时间轴
                LuaValue va = ve.get(2); // 强度轴

                // 关键：取两者长度的最小值，防止 Lua 配置不一致导致崩溃
                int len = Math.min(vt.length(), va.length());

                if (len > 0) {
                    long[] timings = new long[len];
                    int[] amplitudes = new int[len];
                    for (int i = 0; i < len; i++) {
                        timings[i] = vt.get(i + 1).optlong(0);
                        // 强制约束振幅在 0-255，防止 Lua 填错导致非法参数异常
                        int amp = va.get(i + 1).optint(0);
                        amplitudes[i] = Math.max(0, Math.min(255, amp));
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            mVibrationEffect = VibrationEffect.createWaveform(timings, amplitudes, -1);
                        } catch (Exception e) {
                            // 最后的兜底，防止意外的非法参数
                            mVibrationEffect = null;
                        }
                    }
                }
            }
        }
        return mVibrationEffect;
    }

    public boolean isVibrationEnabled() {
        if (!mHasCachedVibrationEnabled) {
            mHasCachedVibrationEnabled = true;
            mVibrationEnabled = get("vibration_enabled").toboolean();
        }
        return mVibrationEnabled;
    }

    public int getSoundEffect() {
        if (!mHasCachedSoundEffect) {
            mHasCachedSoundEffect = true;
            LuaValue ve = get("sound_effect");
            if (ve.isstring()) {
                String s = ve.tojstring();
                String path = Config.getStylePath(s);
                if (new File(path).exists()) {
                    mSoundEffect = ThemeManager.loadSound(path);
                } else {
                    path = Config.getSoundPath(s);
                    if (new File(path).exists())
                        mSoundEffect = ThemeManager.loadSound(path);
                }
            }
        }
        return mSoundEffect;
    }

    public boolean isSoundEnabled() {
        if (!mHasCachedSoundEnabled) {
            mHasCachedSoundEnabled = true;
            mSoundEnabled = get("sound_enabled").toboolean();
        }
        return mSoundEnabled;
    }

    public long getLongClickTime() {
        if (mLongClickTime == 0)
            mLongClickTime = get("long_click_time").optlong(1000);
        return mLongClickTime;
    }

    public long getRepeatClickTime() {
        if (mRepeatClickTime == 0)
            mRepeatClickTime = get("repeat_click_time").optlong(200);
        return mRepeatClickTime;
    }

    public Typeface getFont() {
        if (mTypeface == null)
            mTypeface = getFont("font");
        return mTypeface;
    }

    public boolean isShow() {
        if (!mHasCachedShow) {
            LuaValue show = get("show");
            mShow = show.isnil() || show.toboolean();
            mHasCachedShow = true;
        }
        return mShow;
    }

    public CharSequence getSpan(final String text) {
        if (TextUtils.isEmpty(text))
            return text;
        CharSequence s = mSpanCache.get(text);
        if (s != null)
            return s;
        String path = Config.findImagePath(text.endsWith(".png") ? text : text + ".png");
        if (!TextUtils.isEmpty(path)) {
            SpannableString span = new SpannableString(text);
            try {
                Bitmap bitmap = LuaBitmap.getLocalBitmap(path);
                int targetColor = getTextColor(); // 你的目标颜色（例如 Trime 主题色）
                BitmapDrawable bmp = new BitmapDrawable(bitmap);
                if (getSingleColorIfPure(bitmap) == null) {
                    if (targetColor != 0 && (targetColor & 0x00FFFFFF) != 0) {
                        float r = Color.red(targetColor) / 255f;
                        float g = Color.green(targetColor) / 255f;
                        float b = Color.blue(targetColor) / 255f;
                        float a = Color.alpha(targetColor) / 255f;

                        // 灰度转换系数（标准生理亮度公式）
                        float lr = 0.213f;
                        float lg = 0.715f;
                        float lb = 0.072f;

                        ColorMatrix cm = new ColorMatrix(new float[]{
                                lr * r, lg * r, lb * r, 0, 0,  // 新的 R = (原R*lr + 原G*lg + 原B*lb) * 目标R
                                lr * g, lg * g, lb * g, 0, 0,  // 新s G = (原R*lr + 原G*lg + 原B*lb) * 目标G
                                lr * b, lg * b, lb * b, 0, 0,  // 新的 B = (原R*lr + 原G*lg + 原B*lb) * 目标B
                                0, 0, 0, a, 0   // 保持原图透明度并乘以目标Alpha
                        });

                        ColorFilter filter = new ColorMatrixColorFilter(cm);
                        bmp.setColorFilter(filter);
                    }
                } else {
                    PorterDuffColorFilter colorFilter = new PorterDuffColorFilter(getTextColor(), PorterDuff.Mode.SRC_IN);
                    bmp.setColorFilter(colorFilter);
                }

                bmp.setBounds(0, 0, ThemeManager.dp2px(getTextSize()), ThemeManager.dp2px(getTextSize()));
                ImageSpan image = new ImageSpan(bmp, DynamicDrawableSpan.ALIGN_CENTER);
                span.setSpan(image, 0, text.length(), Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
                mSpanCache.put(text, span);
                return span;
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        mSpanCache.put(text, text);
        return text;
    }

    /**
     * 判断图片是否为单色图标（忽略透明区域）
     *
     * @param bitmap 待检测的位图
     * @return 如果图片除透明外只有一种 RGB 颜色，返回该颜色值（包含原始Alpha）；否则返回 null
     */
    public static Integer getSingleColorIfPure(Bitmap bitmap) {
        if (bitmap == null) return null;

        int width = bitmap.getWidth();
        int height = bitmap.getHeight();

        Integer baseColor = null; // 用于存储第一个找到的非透明像素的 RGB

        // 采样步长：如果图片很大，可以设置步长（如 2）来提高性能
        int step = 1;

        for (int x = 0; x < width; x += step) {
            for (int y = 0; y < height; y += step) {
                int pixel = bitmap.getPixel(x, y);

                // 1. 去除全透明区域：如果 Alpha 为 0，跳过不计入判断
                if (Color.alpha(pixel) == 0) {
                    continue;
                }

                // 2. 提取 RGB 部分 (忽略透明度进行比较)
                int currentColorRGB = pixel & 0x00FFFFFF;

                if (baseColor == null) {
                    // 记录第一个非透明像素的 RGB 作为基准
                    baseColor = currentColorRGB;
                } else {
                    // 3. 与基准色对比
                    if (currentColorRGB != baseColor) {
                        return null; // 发现第二种颜色，不是单色图
                    }
                }
            }
        }

        // 如果循环结束 baseColor 仍为 null，说明是全透明图片
        return baseColor;
    }
}

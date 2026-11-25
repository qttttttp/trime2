/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import android.content.Context;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityManager;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

import com.androlua.LuaApplication;

import org.luaj.Globals;

import java.util.ArrayList;

public class KeyboardView extends FrameLayout {
    private final ArrayList<KeyView> mKeys;
    private final ArrayList<KeyView> mComposingKeys;
    protected Globals globals;
    private boolean mShifted;
    private static AccessibilityManager mAm;
    private boolean keySwipe = false;
    private boolean mAsciiMode;
    private boolean mAsciiModeLock;
    private boolean mLock;

    public static boolean isTouchExplorationEnabled() {
        if (mAm == null) {
            Context context = LuaApplication.getInstance();
            if (context != null) {
                // 缓存单例对象
                mAm = (AccessibilityManager) context.getApplicationContext()
                        .getSystemService(Context.ACCESSIBILITY_SERVICE);
            }
        }
        // 使用变量判空，防止 context 获取失败导致的 NPE
        return mAm != null && mAm.isTouchExplorationEnabled();
    }

    public KeyboardView(@NonNull Context context, Globals globals) {
        super(context);
        mKeys = new ArrayList<>();
        mComposingKeys = new ArrayList<>();
        setClipChildren(false);    // 允许子控件阴影超出边界
        setClipToPadding(false);
        setAsciiModeLock(globals.get("ascii_mode").toboolean());
        setLock(globals.get("lock").toboolean());
    }
    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        try {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        }catch (Exception e){
            e.printStackTrace();
        }
    }
    public boolean isAsciiMode() {
        return mAsciiMode || mAsciiModeLock;
    }

    public void setAsciiMode(boolean b) {
        mAsciiMode = b;
    }

    public void setAsciiModeLock(boolean b) {
        mAsciiModeLock = b;
    }

    /**
     * 递归处理新添加的视图
     */
    private void processViewAdded(View view) {
        if (view instanceof KeyView) {
            KeyView kv = (KeyView) view;
            if (!mKeys.contains(kv)) {
                mKeys.add(kv);
                // 如果是特殊的 KeyView 类型，可以分类存储
                if (kv.isComposingKey()) mComposingKeys.add(kv);
            }
        } else if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            // 扫描该容器内已经存在的子 View（针对 Lua 一次性添加一个大布局的情况）
            for (int i = 0; i < group.getChildCount(); i++) {
                processViewAdded(group.getChildAt(i));
            }
        }
    }

    /**
     * 递归处理移除的视图
     */
    private void processViewRemoved(View view) {
        if (view instanceof KeyView) {
            mKeys.remove(view);
            mComposingKeys.remove(view);
            if (view == lastKey) lastKey = null; // 清理触摸追踪状态
        } else if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                processViewRemoved(group.getChildAt(i));
            }
        }
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        // 2. 核心：如果列表为空，说明是重新显示，立即全量扫描当前已有的 View 树
        if (mKeys.isEmpty()) {
            processViewAdded(this);
            if (mShifted != ModifierState.isShifted()) {
                mShifted = ModifierState.isShifted();
                invalidateAllKeys();
            }
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        // 1. 显式清空列表，切断强引用链
        mKeys.clear();
        mComposingKeys.clear();
        lastKey = null;
        super.onDetachedFromWindow();
    }

    public boolean isLabelUppercase() {
        return false;
    }


    public ArrayList<KeyView> getComposingKeys() {
        return mComposingKeys;
    }

    // 假设这是你的 KeyboardView 容器
    private View lastKey = null; // 记录上一个按下的按键

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        if (!keySwipe)
            return super.dispatchTouchEvent(ev);
        // 1. 如果 TalkBack 开启，建议走系统默认流程，否则读屏无法线性遍历按键
        if (isTouchExplorationEnabled()) {
            return super.dispatchTouchEvent(ev); // 交给系统默认分发逻辑
        }
        int action = ev.getActionMasked();
        float x = ev.getX();
        float y = ev.getY();

        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_MOVE:
                // 1. 寻找当前坐标对应的 View
                View currentKey = findKeyAt(x, y);
                //Log.w("KeyDebug", "findKeyAt: " + currentKey);

                if (currentKey != lastKey) {
                    // 2. 状态切换：旧按键弹起，新按键按下
                    if (lastKey != null) {
                        lastKey.setPressed(false);
                        lastKey.refreshDrawableState(); // 关键：通知系统状态已变，去匹配 SLA
                    }
                    if (currentKey != null) {
                        // 设置热点（Ripple 会从手指进入的位置开始扩散）
                        currentKey.drawableHotspotChanged(x - currentKey.getLeft(), y - currentKey.getTop());
                        currentKey.setPressed(true);
                        currentKey.refreshDrawableState(); // 关键：通知系统状态已变，去匹配 SLA
                    }
                    lastKey = currentKey;
                }
                break;

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                // 3. 抬起逻辑
                if (lastKey != null) {
                    if (action == MotionEvent.ACTION_UP) {
                        // 手动触发点击回调
                        lastKey.performClick();
                    }
                    lastKey.setPressed(false);
                    lastKey = null;
                }
                break;
        }

        // 关键：必须返回 true，声明该布局消费所有触摸
        // 这样事件就不会传递给子 View 的 onTouchEvent
        return true;
    }

    private View findKeyAt(float x, float y) {
        for (KeyView key : mKeys) {
            if (key.contains((int) x, (int) y))
                return key;
        }
        return null;
    }

    public void addView(KeyView child, ViewGroup.LayoutParams params) {
        super.addView(child, params);
        if (child.isComposingKey()) {
            mComposingKeys.add(child);
        }
        mKeys.add(child);
    }

    public void addView(ViewGroup child, ViewGroup.LayoutParams params) {
        super.addView(child, params);
        // 统一调用收集逻辑，不仅限于 Flexbox
        collectKeyViews(child);
    }

    /**
     * 递归收集布局树中所有的 KeyView 并分类存储
     *
     * @param root 当前需要扫描的根布局
     */
    private void collectKeyViews(ViewGroup root) {
        for (int i = 0; i < root.getChildCount(); i++) {
            View child = root.getChildAt(i);

            if (child instanceof KeyView) {
                KeyView key = (KeyView) child;

                // 1. 添加到全局总表（使用 contains 判断防止重复注册）
                if (!mKeys.contains(key)) {
                    mKeys.add(key);

                    // 2. 根据属性进行分类登记
                    if (key.isComposingKey()) {
                        mComposingKeys.add(key);
                    }
                }
            } else if (child instanceof ViewGroup) {
                // 3. 如果是容器（如 FlexboxLayout, LinearLayout 等），递归向下扫描
                collectKeyViews((ViewGroup) child);
            }
        }
    }

    public void invalidateComposingKeys() {
        for (KeyView key : mComposingKeys) {
            key.invalidateKey();
        }
    }

    public void invalidateAllKeys() {
        for (KeyView key : mKeys) {
            key.invalidateKey();
        }
    }

    public boolean isShifted() {
        return mShifted;
    }

    public void setShifted(boolean shifted) {
        mShifted = shifted;
        invalidateAllKeys();
    }

    public boolean isLock() {
        return mLock;
    }

    public void setLock(boolean b) {
        mLock = b;
    }

    public void setKeySwipe(boolean b){
        keySwipe = b;
    }
}

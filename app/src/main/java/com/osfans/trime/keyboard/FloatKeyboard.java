/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import android.content.Context;
import android.os.Build;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.GridLayout;

import androidx.annotation.NonNull;

import com.osfans.trime.Key;
import com.osfans.trime.TrimeService;
import com.osfans.trime.theme.KeyStyle;
import com.osfans.trime.theme.Style;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.Globals;
import org.luaj.LuaTable;

import java.util.ArrayList;
import java.util.List;

public class FloatKeyboard extends KeyboardView {

    private final List<String> mKeys;
    private final Style mPopupStyle;
    private final KeyStyle mKeyStyle;
    private double mHeight;
    private double mWidth;

    private double mKeyWidth;
    private LuaTable mLayout;
    private double mLeft;
    private int mKeyHeight;
    private int mOffsetX;

    public FloatKeyboard(@NonNull Context context, Globals globals, List<String> keys) {
        super(context, globals);
        setClipChildren(false);
        setClipToPadding(false);
        mKeys = keys;
        long time = System.currentTimeMillis();
        mPopupStyle=ThemeManager.getStyle().getStyle("popup",ThemeManager.getStyle().getStyle("keyboard"));
        mKeyStyle=mPopupStyle.getKeyStyle("key",ThemeManager.getStyle().getKeyStyle());
        setBackground(mPopupStyle.getBackground(0xffdddddd));
        loadRows();
        Log.w("FloatKeyboard", "init time: " + (System.currentTimeMillis() - time));
        setKeySwipe(true);
        setElevation(mPopupStyle.getInt("elevation"));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            int dShadowColor = mPopupStyle.getColor("shadow_color");
            if (dShadowColor != 0) {
                setOutlineAmbientShadowColor(dShadowColor);
                setOutlineSpotShadowColor(dShadowColor);
            }
        }
    }

    private void loadRows() {
        GridLayout grid = new GridLayout(getContext());
        grid.setClipChildren(false);
        grid.setClipToPadding(false);
        grid.setColumnCount(mPopupStyle.getInt("column_count",5));
        TrimeService mTrime = TrimeService.getInstance();
        mHeight = ThemeManager.getKeyboardHeight();
        mWidth = mTrime.getWidth();
        int len = mKeys.size();
        mKeyWidth = mKeyStyle.getInt("width",10);
        mKeyHeight = mKeyStyle.getInt("height",15);
        for (int i = 0; i < len; i++) {
            loadKey(grid, mKeys.get(i), mKeyWidth, mKeyHeight);
        }
        addView(grid, new ViewGroup.LayoutParams(getRawWidth(), getRawHeight()));
    }


    private void loadKey(GridLayout grid, String key, double width, double height) {
        width = (mWidth * width / 100);
        height = (mHeight * height / 100);
        KeyView keyView = new KeyView(getContext(), new Key(key), mKeyStyle);
        FrameLayout.LayoutParams layoutParams = new FrameLayout.LayoutParams((int) width, (int) height, Gravity.TOP | Gravity.LEFT);
        grid.addView(keyView, layoutParams);
    }

    public int getRawHeight() {
        return (int) (mHeight * mKeyHeight / 100) * ((mKeys.size() - 1) / 5 + 1);
    }

    public int getRawWidth() {
        return (int) (mWidth * mKeyWidth / 100) * Math.min(mKeys.size(), 5);
    }

    public void setOffsetX(int x) {
        mOffsetX=x;
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        ev.offsetLocation(mOffsetX,0);
        return super.dispatchTouchEvent(ev);
    }
}

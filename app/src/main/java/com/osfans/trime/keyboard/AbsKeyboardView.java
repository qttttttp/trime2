/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import android.content.Context;
import android.util.Log;
import android.view.Gravity;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

import com.osfans.trime.Key;
import com.osfans.trime.TrimeService;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.Globals;
import org.luaj.LuaTable;

public class AbsKeyboardView extends KeyboardView{

    private final double mRowHeight;
    private final double mKeyWidth;
    private double mHeight;
    private double mWidth;
    private LuaTable mKeys;
    private LuaTable mLayout;

    public AbsKeyboardView(@NonNull Context context, Globals globals) {
        super(context,globals);
        this.globals = globals;
        String style = globals.get("style").optjstring("keyboard");
        long time=System.currentTimeMillis();
        setBackground(ThemeManager.getStyle().getStyle(style).getBackground(0xffdddddd));
        mRowHeight = globals.get("key_height").optdouble(10);
        mKeyWidth = globals.get("key_width").optdouble(20);
        loadRows();
        Log.w("RowKeyboardView", "init time: "+(System.currentTimeMillis()-time) );
    }

    private void loadRows() {
        TrimeService mTrime= TrimeService.getInstance();
        mHeight = ThemeManager.getKeyboardHeight();
        mWidth = mTrime.getWidth();

        mLayout = globals.get("layout").opttable(null);
        mKeys = globals.get("keys").checktable();
        int len = mKeys.length();
        for (int i = 0; i < len; i++) {
            loadKey(mKeys.get(i + 1).checktable());
        }
    }
    private void loadKey(LuaTable key) {
        //LuaTable layout=key.get("layout").opttable(mLayout);
        int width = (int) (mWidth*key.get("width").optdouble(mKeyWidth)/100);
        int height = (int) (mHeight*key.get("height").optdouble(mRowHeight)/100);
        int x = (int) (mWidth*key.get("x").optdouble(0)/100);
        int y = (int) (mHeight*key.get("y").optdouble(0)/100);
        KeyView keyView = new KeyView(getContext(),new Key(key));
        keyView.setShapeDetectionEnabled(true);
        FrameLayout.LayoutParams layoutParams = new FrameLayout.LayoutParams(width, height, Gravity.TOP| Gravity.LEFT);
        layoutParams.leftMargin=x;
        layoutParams.topMargin=y;
        addView(keyView,layoutParams);
    }
}

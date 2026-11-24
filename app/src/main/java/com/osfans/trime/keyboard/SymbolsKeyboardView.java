/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import android.content.Context;
import android.util.Log;
import android.view.ContextThemeWrapper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import androidx.viewpager2.widget.ViewPager2;

import com.google.android.material.tabs.TabLayout;
import com.google.android.material.tabs.TabLayoutMediator;
import com.osfans.trime.Config;
import com.osfans.trime.Event;
import com.osfans.trime.Key;
import com.osfans.trime.TrimeService;
import com.osfans.trime.keyboard.adapter.ListPagerAdapter;
import com.osfans.trime.theme.KeyStyle;
import com.osfans.trime.theme.Style;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.Globals;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.ResourceFinder;
import org.luaj.lib.jse.JsePlatform;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;

public class SymbolsKeyboardView extends LinearLayout implements ResourceFinder {
    private final LuaTable mKeyMap;
    private final KeyStyle mKeyStyle;
    private final TrimeService mTrime;
    private final Style mSymbolStyle;
    private final KeyStyle mTabStyle;
    private final KeyStyle mToolStyle;
    private ViewPager2 viewPager;
    private ListPagerAdapter mAdapter;

    public SymbolsKeyboardView(@NonNull Context context) {
        super(context);
        long time = System.currentTimeMillis();
        Globals globals = JsePlatform.standardGlobals();
        globals.finder = this;
        globals.loadfile("symbols.lua").call();
        mKeyMap = globals.get("key_maps").checktable();
        mSymbolStyle = ThemeManager.getStyle().getStyle("symbol");
        mKeyStyle = mSymbolStyle.getKeyStyle("key", ThemeManager.getStyle().getKeyStyle("key"));
        mTabStyle = mSymbolStyle.getKeyStyle("tab_bar", ThemeManager.getStyle().getKeyStyle("candidate"));
        mToolStyle = mSymbolStyle.getKeyStyle("tool_bar", ThemeManager.getStyle().getKeyStyle("candidate"));
        mTrime = TrimeService.getInstance();
        setBackground(mSymbolStyle.getBackground(0x00000000));
        initView();
        Log.w("SymbolsKeyboardView", "init time: " + (System.currentTimeMillis() - time));
    }

    public SymbolsKeyboardView(@NonNull Context context, Globals globals) {
        super(context);
        long time = System.currentTimeMillis();
        mKeyMap = globals.get("key_maps").checktable();
        mSymbolStyle = ThemeManager.getStyle().getStyle("symbol");
        mKeyStyle = mSymbolStyle.getKeyStyle("key", ThemeManager.getStyle().getKeyStyle("key"));
        mTabStyle = mSymbolStyle.getKeyStyle("tab_bar", ThemeManager.getStyle().getKeyStyle("candidate"));
        mToolStyle = mSymbolStyle.getKeyStyle("tool_bar", ThemeManager.getStyle().getKeyStyle("candidate"));
        mTrime = TrimeService.getInstance();
        setBackground(mSymbolStyle.getBackground(0x00000000));
        initView();
        Log.w("SymbolsKeyboardView", "init time: " + (System.currentTimeMillis() - time));
    }

    private void initView() {
        // 导入 android.view.ContextThemeWrapper
        Context themedContext = new ContextThemeWrapper(getContext(), androidx.appcompat.R.style.Theme_AppCompat_Light);
        // 使用 themedContext 来初始化 TabLayout 或 View
        TabLayout tabLayout = new TabLayout(themedContext);
        tabLayout.setTabTextColors(mKeyStyle.getTextColor(), mKeyStyle.getKeyStyle("pressed", mKeyStyle).getTextColor());
        tabLayout.setSelectedTabIndicatorColor(mTabStyle.getColor("indicator_color", mSymbolStyle.getColor("indicator_color", mKeyStyle.getKeyStyle("pressed", mKeyStyle).getTextColor())));
        tabLayout.setTabMode(TabLayout.MODE_SCROLLABLE);
        viewPager = new ViewPager2(getContext());
        LinearLayout root = new LinearLayout(getContext());
        root.setOrientation(LinearLayout.VERTICAL);
        if (mTabStyle.getGravity() == Gravity.BOTTOM) {
            root.addView(viewPager, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
            root.addView(tabLayout, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, mTabStyle.getHeight(ViewGroup.LayoutParams.WRAP_CONTENT)));
        } else {
            root.addView(tabLayout, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, mTabStyle.getHeight(ViewGroup.LayoutParams.WRAP_CONTENT)));
            root.addView(viewPager, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        }
        addView(root, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
        mAdapter = new ListPagerAdapter(mKeyMap);
        viewPager.setAdapter(mAdapter);
        // 2. 使用 TabLayoutMediator 连接 TabLayout 和 ViewPager2
        new TabLayoutMediator(tabLayout, viewPager, (tab, position) -> {
            tab.setText(mKeyMap.get(position + 1).get("name").optjstring(String.valueOf(position + 1)));
        }).attach();
        LinearLayout mButtonBar = new LinearLayout(getContext());
        mButtonBar.setOrientation(LinearLayout.VERTICAL);

        KeyView mHide = new KeyView(getContext(), mKeyStyle);
        mHide.setText("△");
        mHide.setContentDescription("返回");
        mHide.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                mTrime.showSymbolsView(false);
            }
        });
        KeyView mPrev = new KeyView(getContext(), mKeyStyle);
        mPrev.setText("⇑");
        mPrev.setContentDescription("上一页");
        mPrev.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
               pageUp();
            }
        });
        KeyView mNext = new KeyView(getContext(), mKeyStyle);
        mNext.setText("⇓");
        mNext.setContentDescription("下一页");
        mNext.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
               pageDown();
            }
        });
        KeyView backSpace = new KeyView(getContext(), mKeyStyle);
        backSpace.setText(" ⌫");
        backSpace.setContentDescription("删除");
        backSpace.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                mTrime.onKey(KeyEvent.KEYCODE_DEL, 0);
            }
        });

        LuaValue keys = mToolStyle.get("keys");
        if (keys.istable()) {
            int len = keys.length();
            for (int i = 0; i < len; i++) {
                String k = keys.get(i + 1).tojstring();
                switch (k) {
                    case "hide":
                        mButtonBar.addView(mHide, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                        break;
                    case "page_up":
                        mButtonBar.addView(mPrev, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                        break;
                    case "page_down":
                        mButtonBar.addView(mNext, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                        break;
                    default:
                        KeyView key = new KeyView(getContext(), new Key(new Event(k)), mKeyStyle);
                        mButtonBar.addView(key, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                }
            }
        } else {
            mButtonBar.addView(mHide, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
            mButtonBar.addView(mPrev, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
            mButtonBar.addView(mNext, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
            mButtonBar.addView(backSpace, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
        }
        switch (mToolStyle.getGravity(Gravity.RIGHT)) {
            case Gravity.LEFT:
                setOrientation(HORIZONTAL);
                mButtonBar.setOrientation(VERTICAL);
                addView(mButtonBar, 0, new LinearLayout.LayoutParams(mToolStyle.getHeight(ThemeManager.getCandidateHeight()), ViewGroup.LayoutParams.MATCH_PARENT));
                break;
            case Gravity.RIGHT:
                setOrientation(HORIZONTAL);
                mButtonBar.setOrientation(VERTICAL);
                addView(mButtonBar, new LinearLayout.LayoutParams(mToolStyle.getHeight(ThemeManager.getCandidateHeight()), ViewGroup.LayoutParams.MATCH_PARENT));
                break;
            case Gravity.TOP:
                setOrientation(VERTICAL);
                mButtonBar.setOrientation(HORIZONTAL);
                addView(mButtonBar, 0, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, mToolStyle.getHeight(ThemeManager.getCandidateHeight())));
                break;
            case Gravity.BOTTOM:
                setOrientation(VERTICAL);
                mButtonBar.setOrientation(HORIZONTAL);
                addView(mButtonBar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, mToolStyle.getHeight(ThemeManager.getCandidateHeight())));
                break;
        }
        //addView(mButtonBar, new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));
    }

    public boolean pageDown() {
        RecyclerView list = getListView(viewPager, mAdapter);
        list.smoothScrollBy(0, list.getHeight());
        return true;
    }

    public boolean pageUp() {
        RecyclerView list = getListView(viewPager, mAdapter);
        list.smoothScrollBy(0, -list.getHeight());
        return true;
    }

    private RecyclerView getListView(ViewPager2 viewPager2, ListPagerAdapter mAdapter) {
        // 1. 获取当前页码
        int currentPos = viewPager2.getCurrentItem();

// 2. 访问 ViewPager2 内部的 RecyclerView
        RecyclerView internalRecyclerView = (RecyclerView) viewPager2.getChildAt(0);

// 3. 找到当前位置对应的 ViewHolder
        RecyclerView.ViewHolder viewHolder = internalRecyclerView.findViewHolderForAdapterPosition(currentPos);

        if (viewHolder instanceof ListPagerAdapter.ListViewHolder) {
            // 4. 获取你在 ViewHolder 中定义的 recyclerView
            return ((ListPagerAdapter.ListViewHolder) viewHolder).recyclerView;
            // 现在你可以对当前页的 RecyclerView 进行操作了
        }
        return mAdapter.getListView();
    }


    @Override
    public InputStream findResource(String name) {
        try {
            if (new File(name).exists())
                return new FileInputStream(name);
        } catch (Exception e) {
        }
        try {
            return new FileInputStream(new File(Config.getKeyboardDir(), name));
        } catch (Exception e) {
        }

        try {
            return getContext().getAssets().open("themes/default/keyboards/" + name);
        } catch (Exception ioe) {
           /*if (BuildConfig.DEBUG)
             e.printStackTrace();*/
        }
        try {
            return getContext().getAssets().open("themes/default/keyboards/symbols.lua");
        } catch (Exception ioe) {
           /*if (BuildConfig.DEBUG)
             e.printStackTrace();*/
        }
        return null;
    }

    @Override
    public String findFile(String filename) {
        if (filename.startsWith("/"))
            return filename;
        return new File(Config.getKeyboardDir(), filename).getAbsolutePath();
    }

}

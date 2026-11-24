/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import android.content.Context;
import android.view.ContextThemeWrapper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import androidx.viewpager2.widget.ViewPager2;

import com.google.android.material.tabs.TabLayout;
import com.google.android.material.tabs.TabLayoutMediator;
import com.osfans.trime.Event;
import com.osfans.trime.Key;
import com.osfans.trime.TrimeService;
import com.osfans.trime.keyboard.adapter.WaterfallAdapter;
import com.osfans.trime.keyboard.adapter.WaterfallPagerAdapter;
import com.osfans.trime.theme.KeyStyle;
import com.osfans.trime.theme.Style;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.LuaValue;

public class ClipboardKeyboardView extends LinearLayout {

    private final TrimeService mTrime;
    private final KeyStyle mKeyStyle;
    private final Style mClipboardStyle;
    private final KeyStyle mTabStyle;
    private final KeyStyle mToolStyle;
    private WaterfallPagerAdapter mAdapter;
    private KeyView mUndo;
    private ViewPager2 viewPager;
    private final ViewPager2.OnPageChangeCallback mOnPageChangeCallback = new ViewPager2.OnPageChangeCallback() {
        @Override
        public void onPageSelected(int position) {
            super.onPageSelected(position);
            try {
                ((WaterfallAdapter) getListView(viewPager, mAdapter).getAdapter()).setData();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    };

    public ClipboardKeyboardView(@NonNull Context context) {
        super(context);
        mClipboardStyle = ThemeManager.getStyle().getStyle("clipboard");
        mKeyStyle = mClipboardStyle.getKeyStyle("key", ThemeManager.getStyle().getKeyStyle("key"));
        mTabStyle = mClipboardStyle.getKeyStyle("tab_bar", ThemeManager.getStyle().getKeyStyle("candidate"));
        mToolStyle = mClipboardStyle.getKeyStyle("tool_bar", ThemeManager.getStyle().getKeyStyle("candidate"));
        mTrime = TrimeService.getInstance();
        setBackground(mClipboardStyle.getBackground(0x00000000));
        initView();
        setClipChildren(false);
        setClipToPadding(false);
    }

    private void initView() {
        // 导入 android.view.ContextThemeWrapper
        Context themedContext = new ContextThemeWrapper(getContext(), androidx.appcompat.R.style.Theme_AppCompat_Light);
        // 使用 themedContext 来初始化 TabLayout 或 View
        TabLayout tabLayout = new TabLayout(themedContext);
        tabLayout.setTabTextColors(mKeyStyle.getTextColor(), mKeyStyle.getKeyStyle("pressed", mKeyStyle).getTextColor());
        tabLayout.setSelectedTabIndicatorColor(mTabStyle.getColor("indicator_color", mClipboardStyle.getColor("indicator_color", mKeyStyle.getKeyStyle("pressed", mKeyStyle).getTextColor())));
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
        mAdapter = new WaterfallPagerAdapter();
        viewPager.setAdapter(mAdapter);
        // 2. 使用 TabLayoutMediator 连接 TabLayout 和 ViewPager2
        new TabLayoutMediator(tabLayout, viewPager, (tab, position) -> {
            switch (position) {
                case 0:
                    tab.setText("剪切板");
                    break;
                case 1:
                    tab.setText("短语");
                    break;
            }
        }).attach();

        LinearLayout mButtonBar = new LinearLayout(getContext());
        mButtonBar.setOrientation(LinearLayout.VERTICAL);

        KeyView mHide = new KeyView(getContext(), mKeyStyle);
        mHide.setText("△");
        mHide.setContentDescription("返回");
        mHide.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                mTrime.showClipboardView(false);
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
        mUndo = new KeyView(getContext(), mKeyStyle);
        mUndo.setText("撤销");
        mUndo.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                mTrime.onKey(KeyEvent.KEYCODE_Z, KeyEvent.META_CTRL_ON);
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
            mButtonBar.addView(mUndo, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
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

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        viewPager.registerOnPageChangeCallback(mOnPageChangeCallback);
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        viewPager.unregisterOnPageChangeCallback(mOnPageChangeCallback);
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

    private RecyclerView getListView(ViewPager2 viewPager2, WaterfallPagerAdapter mAdapter) {
        // 1. 获取当前页码
        int currentPos = viewPager2.getCurrentItem();

// 2. 访问 ViewPager2 内部的 RecyclerView
        RecyclerView internalRecyclerView = (RecyclerView) viewPager2.getChildAt(0);

// 3. 找到当前位置对应的 ViewHolder
        RecyclerView.ViewHolder viewHolder = internalRecyclerView.findViewHolderForAdapterPosition(currentPos);

        if (viewHolder instanceof WaterfallPagerAdapter.ListViewHolder) {
            // 4. 获取你在 ViewHolder 中定义的 recyclerView
            return ((WaterfallPagerAdapter.ListViewHolder) viewHolder).recyclerView;
            // 现在你可以对当前页的 RecyclerView 进行操作了
        }
        return mAdapter.getListView();
    }


    public void update() {

    }

    public void show() {
        viewPager.setCurrentItem(0, false);
        viewPager.post(new Runnable() {
            @Override
            public void run() {
                getListView(viewPager, mAdapter).scrollToPosition(0);
                mOnPageChangeCallback.onPageSelected(1);
            }
        });
    }


    public void showPhrase() {
        viewPager.setCurrentItem(1, false);
        viewPager.post(new Runnable() {
            @Override
            public void run() {
                getListView(viewPager, mAdapter).scrollToPosition(0);
                mOnPageChangeCallback.onPageSelected(1);
            }
        });
    }
}

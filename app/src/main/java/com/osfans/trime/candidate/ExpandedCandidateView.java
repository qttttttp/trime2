/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.candidate;

import android.content.Context;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.LinearSmoothScroller;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.flexbox.AlignItems;
import com.google.android.flexbox.FlexDirection;
import com.google.android.flexbox.FlexWrap;
import com.google.android.flexbox.FlexboxLayoutManager;
import com.google.android.flexbox.JustifyContent;
import com.osfans.trime.Event;
import com.osfans.trime.Key;
import com.osfans.trime.TrimeService;
import com.osfans.trime.core.CandidateItem;
import com.osfans.trime.keyboard.KeyView;
import com.osfans.trime.theme.KeyStyle;
import com.osfans.trime.theme.Style;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.LuaValue;

import java.util.ArrayList;

public class ExpandedCandidateView extends LinearLayout {

    private final TrimeService mTrime;
    private final Style mCandidateStyle;
    private final KeyStyle mKeyStyle;
    private RecyclerView mListView;
    private FlexboxCandidateAdapter mAdapter;
    private KeyView mChar;

    public ExpandedCandidateView(@NonNull Context context) {
        super(context);
        Style candidateStyle = ThemeManager.getStyle().getStyle("candidate");
        mCandidateStyle = candidateStyle.getStyle("expanded", candidateStyle);
        mKeyStyle = mCandidateStyle.getKeyStyle("key", ThemeManager.getStyle().getKeyStyle("key"));
        mTrime = TrimeService.getInstance();
        setBackground(mCandidateStyle.getBackground(0x00000000));
        initView();
        //setClipChildren(false);
        //setClipToPadding(false);
    }

    private void initView() {
        mListView = new RecyclerView(getContext());
        mListView.setClipChildren(false);
        mListView.setClipToPadding(false);
        FlexboxLayoutManager flexManager = new FlexboxLayoutManager(getContext()) {
            @Override
            public void onLayoutChildren(RecyclerView.Recycler recycler, RecyclerView.State state) {
                try {
                    super.onLayoutChildren(recycler, state);
                } catch (IndexOutOfBoundsException e) {
                    // 仅记录日志，不让应用崩溃
                    android.util.Log.e("ExpandedCandidate", "Catching Flexbox layout crash", e);
                }
            }
        };
        // 1. 主轴设为横向 (ROW)
        flexManager.setFlexDirection(FlexDirection.ROW);
        flexManager.setFlexWrap(FlexWrap.WRAP);             // 开启换行（换列）
        // 4. 设置对齐方式
        // 1. 改为左对齐，配合 Adapter 里的 flexGrow 实现整齐填充
        flexManager.setJustifyContent(JustifyContent.FLEX_START);
        flexManager.setAlignItems(AlignItems.CENTER);
        mListView.setLayoutManager(flexManager);
        mListView.setItemViewCacheSize(40); // 增加缓存数量
        mListView.setItemAnimator(null);
        //mListView.setInitialPrefetchItemCount(8); // 提前预取
        LinearLayout mButtons = new LinearLayout(getContext());
        mButtons.setOrientation(VERTICAL);
        mButtons.setClipChildren(false);
        mButtons.setClipToPadding(false);

        LinearLayout mButtonBar = new LinearLayout(getContext());
        mButtonBar.setOrientation(VERTICAL);
        mButtonBar.setClipChildren(false);
        mButtonBar.setClipToPadding(false);

        LinearLayout layout = new LinearLayout(getContext());

        switch (mCandidateStyle.getKeyStyle("filter_bar").getGravity(Gravity.LEFT)) {
            case Gravity.LEFT:
                mButtons.setOrientation(VERTICAL);
                layout.setOrientation(HORIZONTAL);
                layout.addView(mButtons, new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));
                layout.addView(mListView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                addView(layout, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                break;
            case Gravity.RIGHT:
                mButtons.setOrientation(VERTICAL);
                layout.setOrientation(HORIZONTAL);
                layout.addView(mListView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                layout.addView(mButtons, new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));
                addView(layout, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                break;
            case Gravity.TOP:
                mButtons.setOrientation(HORIZONTAL);
                layout.setOrientation(VERTICAL);
                layout.addView(mButtons, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ThemeManager.getCandidateHeight()));
                layout.addView(mListView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                addView(layout, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                break;
            case Gravity.BOTTOM:
                mButtons.setOrientation(HORIZONTAL);
                layout.setOrientation(VERTICAL);
                layout.addView(mListView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                layout.addView(mButtons, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ThemeManager.getCandidateHeight()));
                addView(layout, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
                break;
        }
        if (!mCandidateStyle.getKeyStyle("filter_bar").getBoolean("show", true)) {
            mButtons.setVisibility(GONE);
        }
        switch (mCandidateStyle.getKeyStyle("tool_bar").getGravity(Gravity.RIGHT)) {
            case Gravity.LEFT:
                setOrientation(HORIZONTAL);
                mButtonBar.setOrientation(VERTICAL);
                addView(mButtonBar, 0, new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));
                break;
            case Gravity.RIGHT:
                setOrientation(HORIZONTAL);
                mButtonBar.setOrientation(VERTICAL);
                addView(mButtonBar, new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));
                break;
            case Gravity.TOP:
                setOrientation(VERTICAL);
                mButtonBar.setOrientation(HORIZONTAL);
                addView(mButtonBar, 0, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ThemeManager.getCandidateHeight()));
                break;
            case Gravity.BOTTOM:
                setOrientation(VERTICAL);
                mButtonBar.setOrientation(HORIZONTAL);
                addView(mButtonBar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ThemeManager.getCandidateHeight()));
                break;
        }

        //addView(mButtons,new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));
        //addView(mListView,new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.MATCH_PARENT,1));
        //addView(mButtonBar,new LinearLayout.LayoutParams(ThemeManager.getCandidateHeight(), ViewGroup.LayoutParams.MATCH_PARENT));

        // 添加左侧六个笔画过滤/功能键
        addStrokeKey(mButtons, "h", "一", "横"); //
        addStrokeKey(mButtons, "s", "丨", "竖"); //
        addStrokeKey(mButtons, "p", "丿", "撇"); //
        addStrokeKey(mButtons, "n", "丶", "点/捺"); //
        addStrokeKey(mButtons, "z", "乙", "折"); //
        addStrokeKey(mButtons, null, "X", "清空过滤"); //  (对应你代码中的 x)

        mListView.setAdapter(mAdapter = new FlexboxCandidateAdapter(new ArrayList<>()));

        KeyView mHide = new KeyView(getContext(), mKeyStyle);
        mHide.setText("△");
        mHide.setContentDescription("收起候选面板");
        mHide.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                mTrime.showExtractedCandidatesView(false);
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
        mChar = new KeyView(getContext(), mKeyStyle);
        mChar.setText("全/单");
        mChar.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                mChar.setText(CandidatesManager.toggleFilterChar() ? "单/全" : "全/单");
                update();
            }
        });

        LuaValue keys = mCandidateStyle.getKeyStyle("tool_bar").get("keys");
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
                    case "char_filter":
                        mButtonBar.addView(mChar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
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
            mButtonBar.addView(mChar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
        }
    }

    public boolean pageDown() {
        mListView.smoothScrollBy(0, mListView.getHeight());
        return true;
    }

    public boolean pageUp() {
        mListView.smoothScrollBy(0, -mListView.getHeight());
        return true;
    }

    private void addStrokeKey(LinearLayout parent, String stroke, String label, String cd) {
        KeyView key = new KeyView(getContext(), mKeyStyle);
        key.setText(label);
        key.setContentDescription(cd);
        key.setOnClickListener(v -> {
            CandidatesManager.filterStroke(stroke, label);
            update();
        });
        parent.addView(key, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, 1));
    }

    public void update() {
        if (mListView.isComputingLayout()) {
            // 如果正在布局，延迟一帧更新，防止冲突
            mListView.post(this::update);
            return;
        }
        CandidatesManager.reset();
        mListView.stopScroll(); // 刷新数据前停止可能的滑动
        mAdapter.setData(CandidatesManager.next(40));
        mListView.scrollToPosition(0);
        //mListView.invalidateItemDecorations();
    }

    public void show() {
        if (mListView.isComputingLayout()) {
            // 如果正在布局，延迟一帧更新，防止冲突
            mListView.post(this::show);
            return;
        }
        CandidatesManager.reset();
        CandidatesManager.resetFilter();
        mAdapter.setData(CandidatesManager.next(40));
        mListView.scrollToPosition(0);
        mChar.setText(CandidatesManager.isFilterChar() ? "单/全" : "全/单");
        //mListView.invalidateItemDecorations();
        if (mAdapter.getItemCount() == 0) {
            mTrime.showExtractedCandidatesView(false);
        }
    }

    public ArrayList<CandidateItem> getData() {
        return mAdapter.getData();
    }

    public void setData(ArrayList<CandidateItem> data) {
        mAdapter.setData(data);
    }

    public int getIdx() {
        // 1. 获取 LayoutManager 并转型
        RecyclerView.LayoutManager layoutManager = mListView.getLayoutManager();

        if (layoutManager instanceof FlexboxLayoutManager) {
            FlexboxLayoutManager linearManager = (FlexboxLayoutManager) layoutManager;

            // 2. 获取第一个“可见”项的序号（只要露出一像素就算）
            int firstVisibleItemPosition = linearManager.findFirstVisibleItemPosition();

            // 3. 获取第一个“完全可见”项的序号（整个 Item 都在屏幕内）
            int firstCompletelyVisibleItemPosition = linearManager.findFirstCompletelyVisibleItemPosition();

            return firstCompletelyVisibleItemPosition;
        }
        return 0;
    }

    public void setIdx(int idx) {
        if (idx < 0 || idx >= mAdapter.getItemCount() - 1)
            return;
        FlexboxLayoutManager layoutManager = (FlexboxLayoutManager) mListView.getLayoutManager();
        if (layoutManager == null) return;


        layoutManager.scrollToPosition(idx);
        // 2. 延迟一点点进行平滑置顶
        mListView.post(() -> {
            // 1. 先瞬间移动到目标位置（虽然不保证置顶，但能把目标拉入预加载范围）
            LinearSmoothScroller smoothScroller = new LinearSmoothScroller(getContext()) {
                @Override
                protected int getVerticalSnapPreference() {
                    return SNAP_TO_START;
                }
            };
            smoothScroller.setTargetPosition(idx);
            layoutManager.startSmoothScroll(smoothScroller);
        });
    }
}

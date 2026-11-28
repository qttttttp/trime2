/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.candidate;

import static android.widget.LinearLayout.HORIZONTAL;
import static com.osfans.trime.keyboard.KeyboardView.isTouchExplorationEnabled;
import static com.osfans.trime.theme.ThemeManager.dp2px;

import android.content.Context;
import android.os.Build;
import android.util.Log;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityEvent;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.osfans.trime.TrimeService;
import com.osfans.trime.core.CandidateItem;
import com.osfans.trime.core.Rime;
import com.osfans.trime.keyboard.KeyView;
import com.osfans.trime.theme.Style;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.LuaValue;

import java.util.ArrayList;

public class CandidateView extends LinearLayout implements View.OnClickListener {

    private final TrimeService mTrime;
    private final Style mCandidateStyle;
    private RecyclerView mListView;
    private KeyView mHide;
    private CandidateAdapter mAdapter;
    private ToolbarView mToolbarView;
    private LinearLayout root;

    public CandidateView(@NonNull Context context) {
        super(context);
        mTrime = TrimeService.getInstance();
        mCandidateStyle = ThemeManager.getStyle().getStyle("candidate");
        setClipChildren(false);
        setClipToPadding(false);
        initView();
    }
    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        try {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        }catch (Exception e){
            e.printStackTrace();
        }
    }
    private void initView() {
        root = new LinearLayout(getContext()) {
            @Override
            public CharSequence getAccessibilityClassName() {
                return "com.nirenr.trime.candidate.CandidateItem";
            }
        };
        root.setOrientation(HORIZONTAL);
        root.setBackground(mCandidateStyle.getBackground(0xffdddddd));
        int elevation = mCandidateStyle.getSize("elevation", 2);
        root.setElevation(elevation);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            int dShadowColor = mCandidateStyle.getColor("shadow_color", 0);
            if (dShadowColor != 0) {
                root.setOutlineAmbientShadowColor(dShadowColor);
                root.setOutlineSpotShadowColor(dShadowColor);
            }
        }
        // 设置 CandidateView 自身的高度，防止输入法界面闪烁
        int height = ThemeManager.getCandidateHeight() - elevation;
        LayoutParams lp = new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
        lp.setMargins(0, 0, 0, elevation);
        addView(root, lp);
        mListView = new RecyclerView(getContext());
        mListView.setClipChildren(false);
        mListView.setClipToPadding(false);
        // 性能优化：横向候选栏通常变动频繁，关闭动画更流畅
        mListView.setItemAnimator(null);
        // 2. 设置布局管理器 (核心步骤：指定为 HORIZONTAL)
        LinearLayoutManager layoutManager = new LinearLayoutManager(
                getContext(),
                LinearLayoutManager.HORIZONTAL, // 横向布局
                false
        );
        mListView.setLayoutManager(layoutManager);
        // 必须设为 false，否则 RecyclerView 会跳过尺寸计算
        mListView.setHasFixedSize(false);
        LuaValue hide = mCandidateStyle.get("key");
        mHide = new KeyView(getContext(), mCandidateStyle.getKeyStyle("key", ThemeManager.getStyle().getKeyStyle("key")));
        if (hide.istable()) {
            mHide.setText(hide.get("text").optjstring("▽"));
        }else {
            mHide.setText("▽");

        }

        mHide.setContentDescription("更多候选");
        mHide.setOnClickListener(this);
        mHide.setMinimumWidth(height);
        root.addView(mListView, new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height, 1));
        root.addView(mHide, new LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, height));
        mListView.setAdapter(mAdapter = new CandidateAdapter(new ArrayList<>()));
    }

    public boolean pageDown() {
        mListView.smoothScrollBy(mListView.getWidth(), 0);
        return true;
    }

    public boolean pageUp() {
        mListView.smoothScrollBy(mListView.getWidth(), 0);
        return true;
    }
    @Override
    public void onClick(View v) {
        if (mAdapter.getItemCount()>0)
            mTrime.showExtractedCandidatesView(true);
        else
            mTrime.requestHideSelf(0);
    }


    public void update() {
        if (mListView.isComputingLayout()) {
            mListView.post(this::update);
            return;
        }
        CandidatesManager.reset();
        mAdapter.setData(CandidatesManager.next());
        mListView.scrollToPosition(0);
        //mListView.invalidateItemDecorations();
        announceCandidate(0);
    }

    public void show() {
        int mIdx = Rime.getHighlightRimeCandidate();
        if (mIdx > 0) {
            mAdapter.setIdx(mIdx);
            announceCandidate(mIdx);
            return;
        }

        if (mListView.isComputingLayout()) {
            mListView.post(this::show);
            return;
        }
        CandidatesManager.reset();
        CandidatesManager.resetFilter();
        mAdapter.setData(CandidatesManager.next());
        // 第一种方式：直接调用 RecyclerView 的方法
        mListView.scrollToPosition(0);
        //mListView.invalidateItemDecorations();
        mListView.requestLayout();
        announceCandidate(0);
    }

    public void show(int idx) {
        int mIdx = Rime.getHighlightRimeCandidate();
        if (mIdx > 0) {
            mAdapter.setIdx(mIdx);
            announceCandidate(mIdx);
            return;
        }

        if (mListView.isComputingLayout()) {
            mListView.post(this::show);
            return;
        }
        CandidatesManager.reset();
        CandidatesManager.resetFilter();
        //CandidatesManager.setStart(idx);
        mAdapter.setData(CandidatesManager.next());
        // 第一种方式：直接调用 RecyclerView 的方法
        //mListView.invalidateItemDecorations();
        mListView.requestLayout();
        announceCandidate(0);
        setIdx(idx);
    }

    private void announceCandidate(int index) {
        if (index < 0 || index >= mAdapter.getItemCount()) return;

        if(!isTouchExplorationEnabled())
            return;
        // 设置朗读文本
        String text = mAdapter.getItem(index).getText();
        root.setContentDescription(text);
        // 发送事件
        root.sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_SELECTED);
    }

    public void showToolbarView(boolean b) {
        if (mToolbarView == null) {
            mToolbarView = new ToolbarView(getContext());
            addView(mToolbarView, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        }
        mToolbarView.setVisibility(b ? View.VISIBLE : View.GONE);
        root.setVisibility(!b ? View.VISIBLE : View.GONE);
    }

    public void invalidateAllKeys() {
        if (mToolbarView != null) {
            mToolbarView.invalidateAllKeys();
        }
    }

    public void setSchema(String id) {
        mToolbarView.setSchema(id);
    }

    public boolean prevCandidate() {
        boolean ret = mAdapter.prevCandidate();
        if(ret)
            announceCandidate(Rime.getHighlightRimeCandidate());
        return ret;
    }

    public boolean nextCandidate() {
        boolean ret = mAdapter.nextCandidate();
        if(ret)
            announceCandidate(Rime.getHighlightRimeCandidate());
        return ret;
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

        if (layoutManager instanceof LinearLayoutManager) {
            LinearLayoutManager linearManager = (LinearLayoutManager) layoutManager;

            // 2. 获取第一个“可见”项的序号（只要露出一像素就算）
            int firstVisibleItemPosition = linearManager.findFirstVisibleItemPosition();

            // 3. 获取第一个“完全可见”项的序号（整个 Item 都在屏幕内）
            int firstCompletelyVisibleItemPosition = linearManager.findFirstCompletelyVisibleItemPosition();

            return firstCompletelyVisibleItemPosition;
        }
        return 0;
    }

    public void setIdx(int idx) {
        if(idx<0||idx>=mAdapter.getItemCount()-1)
            return;
        LinearLayoutManager layoutManager = (LinearLayoutManager) mListView.getLayoutManager();
        if (layoutManager != null) {
            // 参数1：目标索引
            // 参数2：偏移量（0 表示完全置顶）
            layoutManager.scrollToPositionWithOffset(idx, 0);
        }
    }

    public ToolbarView getToolbar() {
        return mToolbarView;
    }
}

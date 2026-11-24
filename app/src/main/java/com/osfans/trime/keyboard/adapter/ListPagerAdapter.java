/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard.adapter;

import android.view.View;
import android.view.ViewGroup;
import android.widget.AbsListView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.flexbox.AlignItems;
import com.google.android.flexbox.FlexDirection;
import com.google.android.flexbox.FlexWrap;
import com.google.android.flexbox.FlexboxLayoutManager;
import com.google.android.flexbox.JustifyContent;

import org.luaj.LuaValue;

public class ListPagerAdapter extends RecyclerView.Adapter<ListPagerAdapter.ListViewHolder> {

    private LuaValue mDataMap; // Key: 页面索引, Value: 该页的数据列表
    private RecyclerView mListView;

    public ListPagerAdapter(LuaValue dataMap) {
        this.mDataMap = dataMap;
    }

    @NonNull
    @Override
    public ListViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        // 动态创建一个 RecyclerView 作为 ViewPager 的每一页
        RecyclerView recyclerView = new RecyclerView(parent.getContext());
        recyclerView.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        recyclerView.setClipChildren(false);
        recyclerView.setClipToPadding(false);

        FlexboxLayoutManager flexManager = new FlexboxLayoutManager(parent.getContext()){
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
        //flexManager.setAlignItems(AlignItems.CENTER);
        flexManager.setAlignItems(AlignItems.STRETCH);
        recyclerView.setLayoutManager(flexManager);
        return new ListViewHolder(recyclerView);
    }

    @Override
    public void onBindViewHolder(@NonNull ListViewHolder holder, int position) {
        // 获取当前页面的数据
        LuaValue pageData = mDataMap.get(position+1).get("keys");
        // 这里需要你写一个普通的 RecyclerView 适配器来展示具体行数据
        LuaValueListAdapter itemAdapter = new LuaValueListAdapter(pageData);
        holder.recyclerView.setAdapter(itemAdapter);
        mListView=holder.recyclerView;
    }

    @Override
    public int getItemCount() {
        return mDataMap.length();
    }

    public RecyclerView getListView() {
        return mListView;
    }

    public static class ListViewHolder extends RecyclerView.ViewHolder {
        public final RecyclerView recyclerView;
        ListViewHolder(@NonNull View itemView) {
            super(itemView);
            recyclerView = (RecyclerView) itemView;
        }
    }
}

/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard.adapter;

import android.util.Log;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import androidx.recyclerview.widget.StaggeredGridLayoutManager;

import com.osfans.trime.TrimeService;

import java.util.List;

public class WaterfallPagerAdapter extends RecyclerView.Adapter<WaterfallPagerAdapter.ListViewHolder> {

    private RecyclerView mListView;

    public WaterfallPagerAdapter() {
    }

    @NonNull
    @Override
    public WaterfallPagerAdapter.ListViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        // 动态创建一个 RecyclerView 作为 ViewPager 的每一页
        RecyclerView recyclerView = new RecyclerView(parent.getContext());
        recyclerView.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        recyclerView.setClipChildren(false);
        recyclerView.setClipToPadding(false);
        // 参数说明：2 代表列数，VERTICAL 代表垂直滚动
        StaggeredGridLayoutManager layoutManager =
                new StaggeredGridLayoutManager(2, StaggeredGridLayoutManager.VERTICAL);

        // 关键设置：防止 Item 切换位置导致闪烁（可选）
        layoutManager.setGapStrategy(StaggeredGridLayoutManager.GAP_HANDLING_MOVE_ITEMS_BETWEEN_SPANS);
        recyclerView.setLayoutManager(layoutManager);
        recyclerView.setItemViewCacheSize(40); // 增加缓存数量
        recyclerView.setItemAnimator(null);
        return new WaterfallPagerAdapter.ListViewHolder(recyclerView);
    }

    @Override
    public void onBindViewHolder(@NonNull WaterfallPagerAdapter.ListViewHolder holder, int position) {
        // 获取当前页面的数据
        List<String> pageData = position==0?TrimeService.getInstance().getClipboard():TrimeService.getInstance().getPhrase();
        // 这里需要你写一个普通的 RecyclerView 适配器来展示具体行数据
        Log.w("WaterfallPagerAdapter", "onBindViewHolder: "+pageData );
        WaterfallAdapter itemAdapter = new WaterfallAdapter(pageData, position!=0);
        holder.recyclerView.setAdapter(itemAdapter);
        mListView=holder.recyclerView;
    }

    @Override
    public int getItemCount() {
        return 2;
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

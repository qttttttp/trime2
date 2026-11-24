/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard.adapter;

import android.content.res.Configuration;
import android.os.Build;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.androlua.LuaApplication;
import com.google.android.flexbox.FlexboxLayoutManager;
import com.osfans.trime.TrimeService;
import com.osfans.trime.keyboard.KeyView;
import com.osfans.trime.theme.KeyStyle;
import com.osfans.trime.theme.Style;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.LuaValue;

import java.util.List;

public class LuaValueListAdapter extends RecyclerView.Adapter<LuaValueListAdapter.ListViewHolder> {
    private final LuaValue mData;
    private final Style mSymbolStyle;
    private final KeyStyle mTextStyle;
    private final boolean mLandscape;

    public LuaValueListAdapter(LuaValue data) {
        mData = data;
        mSymbolStyle = ThemeManager.getStyle().getStyle("symbol");
        mTextStyle = mSymbolStyle.getKeyStyle("text", ThemeManager.getStyle().getKeyStyle());
        int orientation = LuaApplication.getInstance().getResources().getConfiguration().orientation;

        if (orientation == Configuration.ORIENTATION_LANDSCAPE) {
            // 横屏 (Landscape)
            mLandscape = true;
        } else {
            // 竖屏 (Portrait)
            mLandscape = false;
        }
    }

    @NonNull
    @Override
    public ListViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        KeyView tv = new KeyView(parent.getContext(), mTextStyle);
        //tv.setTextSize(TypedValue.COMPLEX_UNIT_DIP,mSymbolStyle.getTextSize(24));
        int dp8 = ThemeManager.dp2px(8);
        tv.setPadding(dp8 , dp8, dp8 , dp8);
        tv.setClickable(true);
        //tv.setTextColor(mSymbolStyle.getTextColor(0xff000000));
        //TypedValue outValue = new TypedValue();
        //parent.getContext().getTheme().resolveAttribute(android.R.attr.selectableItemBackground, outValue, true);
        //tv.setBackgroundResource(outValue.resourceId);
        FlexboxLayoutManager.LayoutParams params = new FlexboxLayoutManager.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setFlexGrow(1.0f);
        //params.setFlexBasisPercent(mSymbolStyle.getFloat("flex_basis",-1f));
        tv.setLayoutParams(params);
        ListViewHolder holder = new ListViewHolder(tv, tv);
        // 在这里只设置一次监听器
        holder.itemView.setOnClickListener(v -> {
            int position = holder.getBindingAdapterPosition(); // 获取当前实时位置
            if (position != RecyclerView.NO_POSITION && mData != null) {
                String item = mData.get(position + 1).optjstring(String.valueOf(position + 1));
                TrimeService.getInstance().commitText(item);
            }
        });
        return holder;
    }

    @Override
    public void onBindViewHolder(@NonNull ListViewHolder holder, int position) {
        holder.tv.setText(mData.get(position + 1).optjstring(String.valueOf(position + 1)));
        holder.tv.setSingleLine(true);
        holder.itemView.setContentDescription(holder.tv.getText());
        FlexboxLayoutManager.LayoutParams params = (FlexboxLayoutManager.LayoutParams) holder.tv.getLayoutParams();
        params.width = ViewGroup.LayoutParams.WRAP_CONTENT;
        params.height = ViewGroup.LayoutParams.WRAP_CONTENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            params.setFlexBasisPercent(holder.tv.getText().toString().codePoints().count() <= 3 ? (mLandscape ? 0.099f : 0.199f) : -1f);
        }else {
            params.setFlexBasisPercent(holder.tv.getText().length() <= 3 ? (mLandscape ? 0.099f : 0.199f) : -1f);
        }
        holder.tv.setLayoutParams(params);
    }

    @Override
    public int getItemCount() {
        return mData.length();
    }

    public static class ListViewHolder extends RecyclerView.ViewHolder {
        public final KeyView tv;

        public ListViewHolder(@NonNull View itemView, KeyView tv) {
            super(itemView);
            this.tv = tv;
        }
    }
}

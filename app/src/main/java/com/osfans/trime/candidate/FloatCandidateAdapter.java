/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.candidate;

import android.content.Context;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.text.TextPaint;
import android.text.TextUtils;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.SubMenu;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.osfans.trime.TrimeService;
import com.osfans.trime.core.CandidateItem;
import com.osfans.trime.core.Rime;
import com.osfans.trime.theme.KeyStyle;
import com.osfans.trime.theme.ThemeManager;
import com.osfans.trime.util.Function;

import java.util.ArrayList;

public class FloatCandidateAdapter extends RecyclerView.Adapter<FloatCandidateAdapter.CandidateViewHolder> {

    private final ArrayList<CandidateItem> mData;
    private final KeyStyle mCandidateStyle;
    private final KeyStyle mCommentStyle;
    private final KeyStyle mCandidatePressedStyle;
    private final KeyStyle mCommentPressedStyle;
    private boolean mIsLoading;
    private int mIdx;
    private int oldIdx;
    private final Drawable mCandidatePressedBackground;
    private final Handler mHandler = new Handler();
    private int mMaxWidth;

    public FloatCandidateAdapter(ArrayList<CandidateItem> data) {
        this.mData = data;
        mCandidateStyle = ThemeManager.getStyle().getKeyStyle("candidate");
        mCandidatePressedStyle = mCandidateStyle.getKeyStyle("pressed", mCandidateStyle);
        mCommentStyle = mCandidateStyle.getKeyStyle("comment", mCandidateStyle);
        mCommentPressedStyle = mCommentStyle.getKeyStyle("pressed", mCommentStyle);
        mCandidatePressedBackground = mCandidatePressedStyle.getBackground();
    }

    @NonNull
    @Override
    public CandidateViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        Context context = parent.getContext();
        // 1. 创建容器（相当于 XML 里的 LinearLayout）
        LinearLayout layout = new LinearLayout(context) {
            @Override
            public CharSequence getAccessibilityClassName() {
                return "com.nirenr.trime.candidate.CandidateItem";
            }
        };
        layout.setGravity(Gravity.START);
        // 在 onCreateViewHolder 里的 layout 设置之后添加
        //TypedValue outValue = new TypedValue();
        //context.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, outValue, true);
        //layout.setBackgroundResource(outValue.resourceId);
        layout.setClickable(true);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        // 内边距：左右 8dp, 上下 2dp
        int px8 = ThemeManager.dp2px(12);
        int px1 = ThemeManager.dp2px(1);
        layout.setPadding(px8, px1, px8, px1);

        // 设置容器 LayoutParams
        RecyclerView.LayoutParams lp = new RecyclerView.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT); // 横向列表高度建议 MATCH_PARENT
        layout.setLayoutParams(lp);

        TextView tvComment = new TextView(context);
        tvComment.setPadding(0, 0, 0, 0);
        tvComment.setLineSpacing(0, 0);
        tvComment.setGravity(Gravity.START);
        tvComment.setTextColor(mCommentStyle.getTextColor(0xff444444));
        tvComment.setTextSize(TypedValue.COMPLEX_UNIT_DIP, mCommentStyle.getTextSize(12));
        tvComment.setIncludeFontPadding(true);
        tvComment.setTypeface(mCommentStyle.getFont());

        TextView tvText = new TextView(context);
        tvText.setMarqueeRepeatLimit(-1);
        tvText.setPadding(0, 0, 0, 0);
        tvText.setLineSpacing(0, 0.1f);
        tvText.setGravity(Gravity.START);
        tvText.setTextColor(mCandidateStyle.getTextColor(0xff000000));
        tvText.setTextSize(TypedValue.COMPLEX_UNIT_DIP, mCandidateStyle.getTextSize(22));
        tvText.setIncludeFontPadding(true); // 去除由于字体规范导致的额外内边距
        tvText.setTypeface(mCandidateStyle.getFont());
        // 1. 先加注释（上方）
        LinearLayout.LayoutParams commentLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        commentLp.gravity = Gravity.START;
// 2. 后加正文（下方）
        LinearLayout.LayoutParams textLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        textLp.gravity = Gravity.START;

        layout.addView(tvText, textLp);
        layout.addView(tvComment, commentLp);
        CandidateViewHolder holder = new CandidateViewHolder(layout, tvComment, tvText);
        holder.itemView.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    mIdx = holder.getBindingAdapterPosition();
                    //Rime.highlightRimeCandidate(mIdx);
                    scrollToIdx();
                }
                return false;
            }
        });
        // 在这里只设置一次监听器
        holder.itemView.setOnClickListener(v -> {
            int position = holder.getBindingAdapterPosition(); // 获取当前实时位置
            if (position != RecyclerView.NO_POSITION && mData != null) {
                CandidateItem item = mData.get(position);
                if (item.getIndex() == -1) {
                    TrimeService.getInstance().commitText(item.getText());
                    TrimeService.getInstance().setCandidates(null);
                } else {
                    TrimeService.getInstance().selectCandidate(item.getIndex());
                }
            }
        });
        holder.itemView.setOnLongClickListener(v -> {
            int position = holder.getBindingAdapterPosition(); // 获取当前实时位置
            if (position != RecyclerView.NO_POSITION && mData != null) {
                CandidateItem candidateItem = mData.get(position);
                PopupMenu popupMenu = new PopupMenu(context, holder.itemView);
                if (candidateItem.getIndex() != -1) {
                    popupMenu.getMenu().add("忘记该词").setOnMenuItemClickListener(new MenuItem.OnMenuItemClickListener() {
                        @Override
                        public boolean onMenuItemClick(@NonNull MenuItem item) {
                            Rime.forgetRimeCandidate(position);
                            TrimeService.getInstance().getRime().clearComposition();
                            return true;
                        }
                    });
                }
                popupMenu.getMenu().add("问AI").setOnMenuItemClickListener(new MenuItem.OnMenuItemClickListener() {
                    @Override
                    public boolean onMenuItemClick(@NonNull MenuItem item) {
                        Function.handle(TrimeService.getInstance(), "gpt", "查询以下字词的读音,解释和字源：" + candidateItem.getText());
                        return true;
                    }
                });
                popupMenu.getMenu().add("查编码").setOnMenuItemClickListener(new MenuItem.OnMenuItemClickListener() {
                    @Override
                    public boolean onMenuItemClick(@NonNull MenuItem item) {
                        Function.handle(TrimeService.getInstance(), "gpt", "输出不少于十种输入方案以下字词的编码：" + candidateItem.getText());
                        return true;
                    }
                });
                SubMenu subMenu = popupMenu.getMenu().addSubMenu("翻译");
                String[] langs = new String[]{
                        "英语",
                        "西班牙语",
                        "俄语",
                        "法语",
                        "葡萄牙语",
                        "阿拉伯语",
                        "日语",
                        "韩语",
                };
                for (String lang : langs) {
                    subMenu.add(lang).setOnMenuItemClickListener(new MenuItem.OnMenuItemClickListener() {
                        @Override
                        public boolean onMenuItemClick(@NonNull MenuItem item) {
                            Function.handle(TrimeService.getInstance(), "gpt", "将以下字词翻译为"+lang+"：" + candidateItem.getText());
                            return true;
                        }
                    });
                }

                popupMenu.getMenu().add("取消").setOnMenuItemClickListener(new MenuItem.OnMenuItemClickListener() {
                    @Override
                    public boolean onMenuItemClick(@NonNull MenuItem item) {
                        popupMenu.dismiss();
                        return true;
                    }
                });
                popupMenu.show();

            }
            return true;
        });
        return holder;
    }

    @Override
    public void onBindViewHolder(@NonNull CandidateViewHolder holder, int position) {
        final CandidateItem data = mData.get(position);
        // 处理注释为空的情况，隐藏 View 节省空间
        if (TextUtils.isEmpty(data.getComment())) {
            holder.tvComment.setVisibility(View.GONE);
            holder.tvComment.setText(data.getComment());
        } else {
            holder.tvComment.setVisibility(View.VISIBLE);
            holder.tvComment.setText(data.getComment());
        }
        holder.tvText.setText(data.getText());

        int tvCommentWidth = (int) holder.tvComment.getPaint().measureText(data.getComment());
        int tvTextWidth = (int) holder.tvText.getPaint().measureText(data.getText());
        int sWidth = holder.tvText.getResources().getDisplayMetrics().widthPixels;
        if(tvCommentWidth+tvTextWidth>sWidth){
            ((LinearLayout)holder.itemView).setOrientation(LinearLayout.VERTICAL);
            mMaxWidth=Math.max(mMaxWidth,Math.max(tvCommentWidth,tvTextWidth));
            holder.tvComment.setMaxWidth(sWidth);
            holder.tvText.setMaxWidth(sWidth);
        }else {
            ((LinearLayout)holder.itemView).setOrientation(LinearLayout.HORIZONTAL);
            mMaxWidth=Math.max(mMaxWidth,tvCommentWidth+tvTextWidth);
            holder.tvComment.setMaxWidth(sWidth);
            holder.tvText.setMaxWidth(sWidth);
        }
        Log.w("TAG", "onBindViewHolder:1 "+tvCommentWidth );
        Log.w("TAG", "onBindViewHolder:2 "+tvTextWidth );
        Log.w("TAG", "onBindViewHolder:3 "+mMaxWidth );
        holder.itemView.setContentDescription(data.getText());
        holder.itemView.setSelected(mIdx == position);
        holder.itemView.setBackground(mIdx == position ? mCandidatePressedBackground : null);
        holder.tvText.setTextColor(mIdx == position ? mCandidatePressedStyle.getTextColor() : mCandidateStyle.getTextColor());
        holder.tvComment.setTextColor(mIdx == position ? mCommentPressedStyle.getTextColor() : mCommentStyle.getTextColor());
        //holder.itemView.setElevation(mIdx == position? mCandidatePressedStyle.getElevation():0);
        // 2. 强制处理宽度更新
        holder.itemView.post(() -> {
            ViewGroup.LayoutParams lp = holder.itemView.getLayoutParams();
            if (lp != null) {
                lp.height = ViewGroup.LayoutParams.WRAP_CONTENT;
                lp.width = ViewGroup.LayoutParams.WRAP_CONTENT;
                holder.itemView.setLayoutParams(lp);
                // 关键：强制要求父容器重新布局
                holder.itemView.requestLayout();
            }
        });
        // 检查是否滑到了最后三项（提前加载，体验更好）
        //if (position >= getItemCount() - 3) {
        //    // 使用 post 避免在布局阶段刷新
        //    holder.itemView.post(this::loadNextPage);
        //}
    }

    private void loadNextPage() {
        if (mIsLoading) return;
        mIsLoading = true;
        ArrayList<CandidateItem> cand = CandidatesManager.next();
        if (cand != null && !cand.isEmpty()) {
            int startPos = mData.size();
            mData.addAll(cand);
            // 不要 notifyDataSetChanged()，只通知新增的部分，性能更好
            notifyItemRangeInserted(startPos, cand.size());
        }
        mIsLoading = false;
    }

    @Override
    public int getItemCount() {
        return mData == null ? 0 : mData.size();
    }

    public void setData(ArrayList<CandidateItem> next) {
        mIdx = 0;
        oldIdx = 0;
        mMaxWidth=0;
        mData.clear();
        mData.addAll(next);
        if (!next.isEmpty())
            Rime.highlightRimeCandidate(next.get(0).getIndex());
        notifyDataSetChanged();
    }

    private RecyclerView mRecyclerView;

    @Override
    public void onAttachedToRecyclerView(@NonNull RecyclerView recyclerView) {
        super.onAttachedToRecyclerView(recyclerView);
        this.mRecyclerView = recyclerView; // 获取列表控件引用
    }

    @Override
    public void onDetachedFromRecyclerView(@NonNull RecyclerView recyclerView) {
        super.onDetachedFromRecyclerView(recyclerView);
        this.mRecyclerView = null; // 防止内存泄漏
    }

    public boolean prevCandidate() {
        if (mIdx <= 0) return false;
        mIdx--;
        scrollToIdx();
        return true;
    }

    public boolean nextCandidate() {
        if (mData.isEmpty())
            return false;
        if (mData.size() - 1 == mIdx) return true;
        mIdx++;
        scrollToIdx();
        return true;
    }

    private void scrollToIdx() {
        if (mRecyclerView != null) {
            // 自动滚动到 mIdx 所在位置
            mRecyclerView.smoothScrollToPosition(mIdx);
        }
        notifyItemChanged(oldIdx);
        oldIdx = mIdx;
        notifyItemChanged(mIdx);
        /*mHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                notifyItemChanged(mIdx);
            }
        },50);*/
        Rime.highlightRimeCandidate(mData.get(mIdx).getIndex());
    }

    public void setIdx(int idx) {
        if (idx < 0 || idx >= getItemCount() - 1)
            return;
        mIdx = idx;
        scrollToIdx();
    }

    public CandidateItem getItem(int index) {
        return mData.get(index);
    }

    public ArrayList<CandidateItem> getData() {
        return mData;
    }

    public int getMaxItemWidth(Context context) {
        Log.w("TAG", "onBindViewHolder:4 "+mMaxWidth );
        return mMaxWidth + ThemeManager.dp2px(32);
    }

    public static class CandidateViewHolder extends RecyclerView.ViewHolder {

        public final TextView tvComment;
        public final TextView tvText;

        public CandidateViewHolder(@NonNull View itemView, TextView tvComment, TextView tvText) {
            super(itemView);
            this.tvComment = tvComment;
            this.tvText = tvText;
        }
    }
}

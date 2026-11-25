/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.util.AttributeSet;
import android.widget.TextView;

import androidx.appcompat.widget.AppCompatTextView;

import com.osfans.trime.theme.ThemeManager;

@SuppressLint("AppCompatCustomView")
public class TightTextView extends TextView {
    private final Rect mTextBounds = new Rect();
    // 紧凑系数：0.8 表示只保留 80% 的排版高度，越小越紧凑
    private float mTightFactor = 0.5f;

    public TightTextView(Context context) {
        super(context);
        int dp = ThemeManager.dp2px(2);
        setPadding(dp,dp,dp,dp);
        setIncludeFontPadding(false);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        String text = getText().toString();
        Paint paint = getPaint();
        paint.getTextBounds(text, 0, text.length(), mTextBounds);

        Paint.FontMetrics fm = paint.getFontMetrics();

        // 宽度依然紧贴实际像素
        int width = mTextBounds.width() + getPaddingLeft() + getPaddingRight();

        // 【核心优化点】：不使用全量高度，而是压缩 ascent 和 descent 的空间
        // 这样既保留了基准线位置（区分 - _），又缩减了外部留白
        float contentHeight = Math.max((fm.descent - fm.ascent) * mTightFactor, mTextBounds.height());
        int height = (int) contentHeight + getPaddingTop() + getPaddingBottom();

        setMeasuredDimension(width, height);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        String text = getText().toString();
        Paint paint = getPaint();
        paint.setColor(getCurrentTextColor());
        //Paint.FontMetrics fm = paint.getFontMetrics();

        // 1. 水平居中（保持不变）
        float x = (getWidth() / 2f) - (mTextBounds.width() / 2f) - mTextBounds.left;

        // 2. 垂直对齐：
        // 我们依然基于 Baseline 绘制，但要确保这行字在被压缩后的 View 里垂直居中
        // 标准公式：View中心 - (ascent + descent) / 2
        float baselineY = (getHeight() / 2f) - mTextBounds.top/2f;// (fm.ascent + fm.descent) / 2f;

        canvas.drawText(text, x, baselineY, paint);
    }

    // 允许动态调节紧凑度
    public void setTightFactor(float factor) {
        this.mTightFactor = factor;
        requestLayout();
    }

    @Override
    public void setText(CharSequence text, BufferType type) {
        super.setText(text, type);
        postInvalidate();
    }
}

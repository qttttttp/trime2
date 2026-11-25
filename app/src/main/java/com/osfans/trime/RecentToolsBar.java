/*
 * r27.45：设置页顶部的「最近使用工具」快捷栏（独立文件，不触碰上游代码）。
 * 横排 3 个按钮，点击以 LuaActivity 启动对应工具的 main.lua。
 * 历史不足时用内置工具补足；只启动脚本，不做其它事。
 */
package com.osfans.trime;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.androlua.LuaActivity;
import com.androlua.LuaApplication;

import java.io.File;

public class RecentToolsBar extends LinearLayout {

    /** 内置工具目录名（即 manifest.txt 的安装名）。 */
    private static final String[] DEFAULT_TOOLS = {"主题工作室", "一键更新"};
    private static final int BUTTON_COUNT = 3;

    private final Context mContext;
    private String mToolsDir;
    // 主题色（r27.46/0.9.1）：默认沿用原深色；PrefLauncher 传入 HomeAppearance 颜色以融入卡片风格
    private int mCardColor = Color.rgb(45, 52, 62);
    private int mStrokeColor = Color.rgb(90, 100, 115);
    private int mTextColor = Color.rgb(230, 230, 230);
    private int mCornerDp = 6;
    private int mTextSp = 13;

    public RecentToolsBar(Context context) {
        super(context);
        mContext = context;
        setOrientation(LinearLayout.HORIZONTAL);
        setGravity(Gravity.CENTER_VERTICAL);
        int pad = dp(8);
        setPadding(pad, dp(4), pad, dp(4));
        try {
            mToolsDir = LuaApplication.getInstance().getLuaExtDir("tools");
        } catch (Throwable e) {
            mToolsDir = null;
        }
        buildButtons();
    }

    /**
     * 0.9.1 卡片式设置页专用构造：把外观交给 HomeAppearance 的视觉令牌，
     * 使三个工具按钮与设置页其它卡片风格一致。启动逻辑与默认构造完全相同。
     */
    public RecentToolsBar(Context context, int cardColor, int strokeColor, int textColor) {
        this(context);
        mCardColor = cardColor;
        mStrokeColor = strokeColor;
        mTextColor = textColor;
        mCornerDp = 12;
        mTextSp = 12;
        buildButtons();
    }

    /** 重新读取历史并重建按钮；由 PrefLauncher.onResume 调用。 */
    public void refresh() {
        removeAllViews();
        buildButtons();
    }

    private void buildButtons() {
        if (mToolsDir == null) {
            TextView hint = makeButton("（工具目录不可用）");
            addView(hint, new LinearLayout.LayoutParams(0, dp(40), 1));
            return;
        }
        java.util.List<String> tools = ToolHistory.resolve(mToolsDir, DEFAULT_TOOLS, BUTTON_COUNT);
        if (tools.isEmpty()) {
            TextView hint = makeButton("（暂无工具）");
            addView(hint, new LinearLayout.LayoutParams(0, dp(40), 1));
            return;
        }
        for (final String name : tools) {
            TextView btn = makeButton(name);
            btn.setOnClickListener(new OnClickListener() {
                @Override
                public void onClick(View v) {
                    openTool(name);
                }
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(40), 1);
            lp.setMargins(dp(3), 0, dp(3), 0);
            addView(btn, lp);
        }
    }

    private void openTool(String name) {
        File main = new File(new File(mToolsDir, name), "main.lua");
        if (!main.isFile()) {
            Toast.makeText(mContext, "工具不存在：" + name, Toast.LENGTH_SHORT).show();
            return;
        }
        // 从快捷栏打开也算一次使用，置顶历史
        ToolHistory.record(mToolsDir, name);
        Intent intent = new Intent(mContext, LuaActivity.class);
        intent.setData(Uri.parse(main.getAbsolutePath()));
        // 设置页是普通 Activity：以 NEW_TASK 启动独立文档，行为与「工具」里一致
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT);
            intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
        }
        try {
            mContext.startActivity(intent);
        } catch (Exception e) {
            Toast.makeText(mContext, "启动工具失败：" + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private TextView makeButton(String text) {
        TextView tv = new TextView(mContext);
        tv.setText(text);
        tv.setGravity(Gravity.CENTER);
        tv.setTextSize(mTextSp);
        tv.setTextColor(mTextColor);
        tv.setSingleLine(true);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(mCardColor);
        bg.setCornerRadius(dp(mCornerDp));
        bg.setStroke(1, mStrokeColor);
        tv.setBackgroundDrawable(bg);
        return tv;
    }

    private int dp(float v) {
        return Math.round(v * mContext.getResources().getDisplayMetrics().density);
    }
}

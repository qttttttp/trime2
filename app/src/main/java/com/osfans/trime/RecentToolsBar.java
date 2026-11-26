/*
 * r27.68：设置页「切换输入法」状态卡片下方的工具快捷栏（独立文件，不触碰上游代码）。
 * 2 列 × 2 行共 4 个按钮，样式与设置页其它卡片一致（HomeCardView）。
 * 取值：init.lua 里 show=true 的固定显示；有最近使用时 show 最多 3 个、留 1 位给最近使用；
 * 都没有则按目录顺序补足；一个工具都没有时整栏隐藏。
 * 只做纯文本读取与脚本启动，绝不执行工具里的 Lua 代码。
 */
package com.osfans.trime;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.androlua.LuaActivity;
import com.androlua.LuaApplication;
import com.osfans.trime.ui.HomeAppearance;
import com.osfans.trime.ui.HomeCardView;

import java.io.File;
import java.util.List;

public class RecentToolsBar extends LinearLayout {

    private static final int BUTTON_COUNT = 4;
    private final Context mContext;
    private final HomeAppearance a;
    private String mToolsDir;

    public RecentToolsBar(Context context) {
        this(context, new HomeAppearance(context, false));
    }

    /** 0.9.1 卡片式设置页专用构造：复用 HomeAppearance 的视觉令牌，与下方卡片一致。 */
    public RecentToolsBar(Context context, HomeAppearance a) {
        super(context);
        mContext = context;
        this.a = a;
        setOrientation(LinearLayout.VERTICAL);
        try {
            mToolsDir = LuaApplication.getInstance().getLuaExtDir("tools");
        } catch (Throwable e) {
            mToolsDir = null;
        }
        refresh();
    }

    /** 重新读取 show / 历史并重建按钮；由 PrefLauncher.onResume 调用。 */
    public void refresh() {
        removeAllViews();
        List<String> tools = ToolHistory.resolveGrid(mToolsDir, BUTTON_COUNT);
        if (tools.isEmpty()) {
            // 没有任何工具：整栏（含标题）不显示
            setVisibility(View.GONE);
            return;
        }
        setVisibility(View.VISIBLE);

        // 标题，样式与 PrefLauncher.section() 保持一致
        TextView title = a.text("最近使用工具", 17, a.ink, true);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-1, -2);
        tp.topMargin = a.dp(18);
        tp.bottomMargin = a.dp(10);
        addView(title, tp);
        if (Build.VERSION.SDK_INT >= 28) title.setAccessibilityHeading(true);

        // 两列两行：每两个按钮一行，各占 1 份宽度
        for (int i = 0; i < tools.size(); i += 2) {
            LinearLayout row = new LinearLayout(mContext);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.TOP);
            row.setBaselineAligned(false);
            for (int j = 0; j < 2 && i + j < tools.size(); j++) {
                final String name = tools.get(i + j);
                String label = ToolHistory.displayName(mToolsDir, name);
                HomeCardView card = new HomeCardView(mContext, a,
                        R.drawable.home_more, a.accent, label, false, null,
                        v -> openTool(name));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1);
                if (j > 0) lp.setMarginStart(a.dp(8));
                row.addView(card, lp);
            }
            LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
            rp.bottomMargin = a.dp(8);
            addView(row, rp);
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
}

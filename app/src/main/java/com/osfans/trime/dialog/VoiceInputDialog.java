/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.dialog;


import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.pm.ServiceInfo;
import android.provider.Settings;
import android.speech.RecognitionService;
import android.text.TextUtils;

import com.androlua.LuaApplication;
import com.osfans.trime.AiClient;
import com.osfans.trime.TrimeService;
import com.osfans.trime.theme.ThemeManager;
import com.osfans.trime.util.Function;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class VoiceInputDialog {
    private final AlertDialog mDig;

    public VoiceInputDialog(Context context) {
        // label 是列表里显示的文字,value 是写进 recognition_service 的值。
        // 两套 ASR 引擎按主题里的配置动态列出:配了 asr_config/asr_config2 就各显示一项,
        // 都没配就不显示。名称取 config.name（没配则按模型前缀/URL 根名兜底），
        // 括号里保持不变，仍是该配置当前的“转写/多模态”模式。
        ArrayList<String> labels = new ArrayList<>();
        ArrayList<String> values = new ArrayList<>();

        String defLabel = "系统默认";
        String defTitle = labelOfComponent(context, resolveDefaultComponent(context));
        if (!TextUtils.isEmpty(defTitle)) {
            defLabel = "系统默认（" + defTitle + "）";
        }
        labels.add(defLabel);
        values.add("默认");

        labels.add("vivo 语音");
        values.add("vivo");

        // ai1 = 第一套 asr_config,ai2 = 第二套 asr_config2;各自配置了才列出
        // 名称按各自 config.name 显示（缺省回退 ai1/ai2），括号里的模式标注保持不变
        AiClient asr1 = ThemeManager.getAsrClient();
        AiClient asr2 = ThemeManager.getAsrClient2();
        if (asr1 != null) {
            String n1 = asr1.getDisplayName();
            labels.add((TextUtils.isEmpty(n1) ? "ai1" : n1) + "（" + modeLabel(asr1) + "）");
            values.add("ai1");
        }
        if (asr2 != null) {
            String n2 = asr2.getDisplayName();
            labels.add((TextUtils.isEmpty(n2) ? "ai2" : n2) + "（" + modeLabel(asr2) + "）");
            values.add("ai2");
        }

        // 列出系统里所有实现了 RecognitionService 的引擎(小爱、讯飞、Google、搜狗等)
        Set<String> seen = new HashSet<>();
        for (String[] e : listRecognitionServices(context.getPackageManager())) {
            String key = e[1] + "/" + e[2];
            if (!seen.add(key)) continue;
            String label = e[0];
            for (String used : labels) {
                if (used.equals(label)) {          // 同名不同包(如两家都叫"语音服务")
                    label = label + " · " + e[1];
                    break;
                }
            }
            labels.add(label);
            values.add(e[0] + "/" + e[1] + "/" + e[2]);
        }

        String name = Function.getPref(context).getString("recognition_service", "vivo");
        int idx = values.indexOf(name);
        if (idx < 0 && !TextUtils.isEmpty(name)) {
            // 旧版本存下的值(比如显示名或已卸载的引擎):原样列出,避免选中项错位
            labels.add(name + "（当前设置）");
            values.add(name);
            idx = values.size() - 1;
        }
        if (idx < 0) idx = 0;

        final String[] mValues = values.toArray(new String[0]);
        final String[] mEngines = labels.toArray(new String[0]);

        mDig = new AlertDialog.Builder(context)
                .setTitle("语音识别引擎")
                .setSingleChoiceItems(mEngines, idx, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        Function.saveString(LuaApplication.getInstance(), "recognition_service", mValues[which]);
                        // 立即让已运行的输入法重建语音引擎,不必重启键盘/输入法。
                        // 输入法服务未运行时 getInstance() 为 null,下次启动创建 Speech 时会读到新配置。
                        TrimeService svc = TrimeService.getInstance();
                        if (svc != null) svc.applySpeechEngineChange();
                        dialog.dismiss();
                    }
                })
                .setNegativeButton(android.R.string.cancel, null)
                .create();
    }

    /** 选项括号里的模式说明:专用转写 / 多模态,跟随 client 实际判定的模式 */
    private static String modeLabel(AiClient client) {
        return client.isTranscribeMode() ? "转写" : "多模态";
    }

    /**
     * 系统当前选定的默认识别服务,格式 "包名/类名";读不到返回 null。
     */
    private static String resolveDefaultComponent(Context context) {
        try {
            String s = Settings.Secure.getString(context.getContentResolver(), "voice_recognition_service");
            return TextUtils.isEmpty(s) ? null : s;
        } catch (Exception e) {
            return null;
        }
    }

    private static String labelOfComponent(Context context, String component) {
        if (TextUtils.isEmpty(component)) return null;
        try {
            ComponentName cn = ComponentName.unflattenFromString(component);
            if (cn == null) return null;
            PackageManager pm = context.getPackageManager();
            Intent intent = new Intent(RecognitionService.SERVICE_INTERFACE).setComponent(cn);
            //noinspection deprecation
            ResolveInfo ri = pm.resolveService(intent, 0);
            if (ri == null) return null;
            CharSequence t = ri.loadLabel(pm);
            return TextUtils.isEmpty(t) ? cn.getPackageName() : t.toString();
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * 返回 [显示名, 包名, 服务类名] 列表。
     */
    private static List<String[]> listRecognitionServices(PackageManager pm) {
        List<String[]> out = new ArrayList<>();
        try {
            Intent intent = new Intent(RecognitionService.SERVICE_INTERFACE);
            // 必须用 0 而不是 MATCH_DEFAULT_ONLY:
            // 很多厂商自带的识别服务(小米小爱等)没有声明 CATEGORY_DEFAULT,
            // 带上 MATCH_DEFAULT_ONLY 就被过滤掉,列表里永远看不到。
            //noinspection deprecation
            List<ResolveInfo> infos = pm.queryIntentServices(intent, 0);
            if (infos == null) return out;
            for (ResolveInfo ri : infos) {
                ServiceInfo si = ri.serviceInfo;
                if (si == null) continue;
                CharSequence title = ri.loadLabel(pm);
                String label = TextUtils.isEmpty(title) ? si.packageName : title.toString();
                out.add(new String[]{label, si.packageName, si.name});
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return out;
    }

    public void show() {
        mDig.show();
    }
}

/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.util;

import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Created by nirenr on 2019/1/1.
 */

public class Cloud {
    private static final String url = "https://olime.baidu.com/py?inputtype=py&bg=0&ed=20&result=hanzi&resultcoding=utf-8&ch_en=0&clientinfo=web&version=1&input=";
    private static final String url2 = "https://www.google.cn/inputtools/request?ime=pinyin&text=";
    private static final String url3 = "http://suggestion.baidu.com/su?p=3&cb=window.bdsug.sug&wd=";
    private static final Pattern p = Pattern.compile("\\[\"([^\"]*)");
    private static final Pattern p2 = Pattern.compile("\"([^\",:]*)\"");
    private static HttpUtil.HttpTask sTask;
    private static HttpUtil.HttpTask sTask2;
    private static HashMap<String, String> cache = new HashMap<>();

    public static void get(final String py, final CloudCallback callback) {
        if (sTask != null)
            sTask.cancel();
        if (sTask2 != null)
            sTask2.cancel();
        sTask = null;
        sTask2 = null;
        final ArrayList<String> ss = new ArrayList<>();
       /*Rime.RimeCandidate[] cs = Rime.getCandidates();
        for (Rime.RimeCandidate c : cs) {
            ss.add(c.text);
        }*/
        sTask = HttpUtil.get(url2 + py, new HttpUtil.HttpCallback() {
            @Override
            public void onDone(HttpUtil.HttpResult result) {
                final ArrayList<String> list = new ArrayList<>();
                if (result.code == 200) {
                    try {
                        //JSONArray cs = new JSONArray(result.text).getJSONArray(1).getJSONArray(0);
                        String sText = new JSONArray(result.text).getJSONArray(1).getJSONArray(0).getJSONArray(1).getString(0);
                        //String sComment = cs.getString(0);
                        if (sText.length() > 1) {
                            if(!ss.contains(sText)) {
                                list.add(sText);
                                //callback.onDone(sText);
                            }
                            /*Rime.RimeCandidate rc = new Rime.RimeCandidate();
                            rc.comment=sComment;
                            rc.text=sText;*/
                         }
                    } catch (JSONException e) {
                        e.printStackTrace();
                    }
                }
                sTask = null;
                sTask2 = HttpUtil.get(url + py, new HttpUtil.HttpCallback() {
                    @Override
                    public void onDone(HttpUtil.HttpResult result) {
                        //Log.i("rime", "onDone: " + result.text);
                        if (result.code == 200) {
                            Matcher m = p.matcher(result.text);
                            while (m.find()) {
                                String g = m.group(1);
                                Log.i("rime", "onDone:3 "+g);
                                //Log.i("rime", "onDone:4 "+ss.contains(g));
                                if(ss.contains(g))
                                    continue;
                                if (!list.contains(g))
                                    list.add(g);
                            }
                        }
                        callback.onDone(list);
                        sTask2 = null;
                    }
                });
            }
        });
    }

    public static void sug(String py, final CloudCallback callback) {
        Log.i("rime", "onDone:sug1 " + py);
        sTask2 = HttpUtil.get(url3 + py, new HttpUtil.HttpCallback() {
            @Override
            public void onDone(HttpUtil.HttpResult result) {
                Log.i("rime", "onDone:sug " + result.text);
                final ArrayList<String> list = new ArrayList<>();
                if (result.code == 200) {
                    Matcher m = p2.matcher(result.text);
                    while (m.find()) {
                        String g = m.group(1);
                        Log.i("rime", "onDone:3 "+g);
                        Log.i("rime", "onDone:4 "+list.contains(g));
                        if(list.contains(g))
                            continue;
                        list.add(g);
                    }
                }
                callback.onDone(list);
                sTask2 = null;
            }
        });
    }

    public static interface CloudCallback {
        public void onDone(ArrayList<String> list);

        public void onDone(String text);
    }
}

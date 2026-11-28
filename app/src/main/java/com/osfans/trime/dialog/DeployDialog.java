/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.dialog;

import android.annotation.SuppressLint;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.DialogInterface;
import android.os.AsyncTask;
import android.os.Handler;
import android.os.IBinder;
import android.text.TextUtils;
import android.util.Log;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Toast;

import com.osfans.trime.Config;
import com.osfans.trime.TrimeService;
import com.osfans.trime.core.Rime;
import com.osfans.trime.core.RimeMessage;
import com.osfans.trime.data.opencc.OpenCCDictManager;
import com.osfans.trime.theme.ThemeManager;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStreamReader;

public class DeployDialog {

    private final AlertDialog mDig;
    private final Handler mHandler = new Handler();
    private IBinder mToken;

    public DeployDialog(Context context) {
        mDig = new AlertDialog.Builder(context, ThemeManager.getDialogTheme())
                .setTitle("正在部署")
                .setMessage("请稍后。。。")
                .create();
    }

    public void show() {
        try {
            mDig.show();
        } catch (Exception e) {
            Toast.makeText(mDig.getContext(), "开始部署",Toast.LENGTH_SHORT).show();
        }
        deploy();
    }

    private void deploy() {
        try {
            Runtime.getRuntime().exec("logcat logcat -c");
        } catch (IOException e) {
            e.printStackTrace();
        }
        Log.i("rime", "Deploy: start");
        try {
            TrimeService.getInstance().deploy();
        } catch (Exception ex) {
            Log.e("TAG", "Deploy Exception" + ex);
        }
        Rime.registerRimeMessageHandler(new Rime.Consumer<RimeMessage<?>>() {
            @Override
            public void accept(RimeMessage<?> rimeMessage) {
                if(rimeMessage instanceof RimeMessage.DeployMessage){
                    RimeMessage.DeployMessage msg = (RimeMessage.DeployMessage) rimeMessage;
                    if (msg.getData() != RimeMessage.DeployMessage.State.Start) {
                        OpenCCDictManager.buildOpenCCDict();
                        mHandler.post(new Runnable() {
                            @Override
                            public void run() {
                                deployDone();
                            }
                        });
                        Rime.unregisterRimeMessageHandler(this);
                    }

                }
            }
        });
    }

    @SuppressLint("StaticFieldLeak")
    private void deployDone(){
        new AsyncTask<String, String, String>() {
            @Override
            protected String doInBackground(String... strings) {
                Log.i("rime", "Deploy: end");
                return execCmd("logcat -d -v long");
            }

            @Override
            protected void onPostExecute(String s) {
                super.onPostExecute(s);
                mDig.dismiss();
                if (TextUtils.isEmpty(s)) {
                    showDialog(new AlertDialog.Builder(mDig.getContext(), Config.getDialogTheme())
                            .setTitle("完成")
                            .setPositiveButton(mDig.getContext().getString(android.R.string.ok), new DialogInterface.OnClickListener() {
                                @Override
                                public void onClick(DialogInterface dialog, int which) {

                                }
                            }).create());
                } else {
                   showDialog(new AlertDialog.Builder(mDig.getContext(), Config.getDialogTheme())
                            .setTitle("提示")
                            .setMessage(s)
                            .setPositiveButton(mDig.getContext().getString(android.R.string.ok), new DialogInterface.OnClickListener() {
                                @Override
                                public void onClick(DialogInterface dialog, int which) {

                                }
                            }).create());
                }
            }
        }.execute();
    }

    public String execCmd(String cmd) {
        StringBuilder result = new StringBuilder();
        BufferedReader dis = null;
        BufferedWriter buf = null;
        try {
            String mDir = Config.getUserDataDir();
            File dir = new File(mDir, "logs");
            if (!dir.exists())
                dir.mkdirs();
            buf = new BufferedWriter(new FileWriter(new File(dir, "deploy.log")));
        } catch (IOException e) {
            e.printStackTrace();
        }
        try {
            Process p = Runtime.getRuntime().exec(cmd);
            dis = new BufferedReader(new InputStreamReader(p.getInputStream()));

            String line = null;
            int n = 0;
            boolean ok = false;
            while ((line = dis.readLine()) != null) {
                n++;
                if (buf != null) {
                    buf.write(line);
                    buf.newLine();
                    buf.flush();
                }
                if (line.contains("E/")) {
                    ok = true;
                    int idx = line.indexOf("]");
                    if (idx > 1)
                        line = line.substring(idx + 1);
                    result.append(line).append("\n");
                } else if (ok) {
                    if (!line.startsWith("\t")) {
                        ok = false;
                        continue;
                    }
                    result.append(line).append("\n");
                }
            }
            //p.waitFor();
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            if (dis != null) {
                try {
                    dis.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
        }
        if (buf != null) {
            try {
                buf.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        return result.toString().trim();
    }


    public void show(IBinder token) {
        if(mDig==null)
            return;
        mToken=token;
        if(mToken==null){
            show();
            return;
        }
        Window win = mDig.getWindow();
        WindowManager.LayoutParams attr = win.getAttributes();
        attr.type=WindowManager.LayoutParams.TYPE_APPLICATION_ATTACHED_DIALOG;
        win.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
        attr.token=token;
        win.setAttributes(attr);
        try {
            mDig.show();
        } catch (Exception e) {
            Toast.makeText(mDig.getContext(), "开始部署",Toast.LENGTH_SHORT).show();
        }
        deploy();
    }

    private void showDialog(Dialog mDig){
        if(mToken==null){
            mDig.show();
            return;
        }
        Window win = mDig.getWindow();
        WindowManager.LayoutParams attr = win.getAttributes();
        attr.type=WindowManager.LayoutParams.TYPE_APPLICATION_ATTACHED_DIALOG;
        win.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
        attr.token=mToken;
        win.setAttributes(attr);
        try {
            mDig.show();
        } catch (Exception e) {
            Toast.makeText(mDig.getContext(), "完成",Toast.LENGTH_SHORT).show();
        }
    }

}

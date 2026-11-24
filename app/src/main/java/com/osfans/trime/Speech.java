/*
 * Copyright (C) 2015-present, osfans
 * waxaca@163.com https://github.com/osfans
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package com.osfans.trime;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.media.SoundPool;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.Vibrator;
import android.provider.Settings;
import android.speech.RecognitionListener;
import android.speech.RecognitionService;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.text.TextUtils;
import android.util.Log;
import android.view.accessibility.AccessibilityManager;
import android.widget.Toast;


import com.androlua.LuaUtil;
import com.osfans.trime.data.opencc.OpenCCDictManager;
import com.osfans.trime.speech.RecognizerListener;
import com.osfans.trime.speech.VivoRecognizer;
import com.osfans.trime.theme.ThemeManager;
import com.osfans.trime.util.AudioRecorderHelper;
import com.osfans.trime.util.Function;
import com.osfans.trime.core.Rime;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;

import static android.Manifest.permission.RECORD_AUDIO;
import static android.content.Context.VIBRATOR_SERVICE;
import static android.media.AudioManager.STREAM_MUSIC;

/**
 * {@link RecognitionListener 語音輸入}
 */
class Speech implements RecognitionListener, RecognizerListener {
    public static final String RES_ID = "RES_ID";
    public static final String NAME = "NAME";
    public static final String config = "config";

    private SoundPool mSoundPool;   // destroy() 后置 null,playSound 需判空
    private AiClient mAsrClient;
    private AudioRecorderHelper mAudioRecorderHelper;
    private VivoRecognizer vSpeech;
    private int mSoundCancel;
    private int mSoundError;
    private int mSoundStart;
    private int mSoundSuccess;
    private int mSoundEnd;
    private final Vibrator mVibrator;
    private int duration = 10;
    private SpeechRecognizer speech = null;
    private boolean mDefaultRecognizer = false;
    private String mCfg = null;   // 创建当前引擎时用的配置,用于检测"切换引擎"
    private String mAsrSig = null; // 创建引擎时的 asr_config 签名,用于检测配置变更

    private Intent recognizerIntent;
    private String TAG = "Speech";
    private TrimeService context;
    private int state = STATE_CANCEL;
    public static final int STATE_DONE = -1;
    public static final int STATE_ERROR = -2;
    public static final int STATE_READY = 0;
    public static final int STATE_BEGIN = 1;
    public static final int STATE_END = 2;
    public static final int STATE_START = 3;
    public static final int STATE_CANCEL = -3;

    public Speech(TrimeService context) {
        this.context = context;
        mVibrator = (Vibrator) context.getSystemService(VIBRATOR_SERVICE);
        SharedPreferences pref = Function.getPref(context);
        duration = (int) (pref.getInt("key_vibrate_duration", duration) * 1.5);

        mSoundPool = new SoundPool(4, STREAM_MUSIC, 0);
        mSoundCancel = mSoundPool.load(context, R.raw.speech_recognition_cancel, 1);
        mSoundError = mSoundPool.load(context, R.raw.speech_recognition_error, 1);
        mSoundStart = mSoundPool.load(context, R.raw.speech_recognition_start, 1);
        mSoundSuccess = mSoundPool.load(context, R.raw.speech_recognition_success, 1);
        mSoundEnd = mSoundPool.load(context, R.raw.speech_speech_end, 1);

        initEngine();
    }

    /**
     * 按当前 recognition_service 配置创建识别引擎。
     * 配置取值:
     *   "ai"              AI 大模型引擎(录音后自己发请求)
     *   "ai语音引擎"       ai语音引擎,另一套独立的 AI 引擎(录音后发请求)
     *   "vivo"            vivo 语音 SDK
     *   "默认"             系统默认识别服务 SpeechRecognizer
     *   "显示名/包名/类名"  系统里某个具体的 RecognitionService(小爱、讯飞、Google 等)
     */
    private void initEngine() {
        releaseEngine();
        mAsrClient = ThemeManager.getAsrClient();
        String cfg = Function.getPref(context).getString("recognition_service", "vivo");
        mCfg = cfg;
        mAsrSig = ThemeManager.getAsrConfigSignature();

        // 用 lastIndexOf 解析:显示名里带 "/" 也不会错位(旧代码 split("/") 取 [1][2] 会崩)
        int p2 = cfg.lastIndexOf('/');
        int p1 = p2 > 0 ? cfg.lastIndexOf('/', p2 - 1) : -1;
        if (p1 >= 0) {
            String pkg = cfg.substring(p1 + 1, p2);
            String cls = cfg.substring(p2 + 1);
            Log.i(TAG, "Speech: " + pkg + ":" + cls);
            speech = createRecognizer(new ComponentName(pkg, cls));
            if (speech == null) {
                // 该服务被卸载/禁用/不导出 → 回退系统默认,不让语音功能整个失效
                Log.w(TAG, "指定识别服务不可用,回退系统默认: " + pkg + "/" + cls);
                speech = createRecognizer(null);
            }
        } else if ((cfg.equals("ai") || cfg.equals("ai语音引擎")) && mAsrClient != null) {
            // "ai" 与 "ai语音引擎" 是两套独立的引擎选项,都走 AI 录音识别路径。
            mAudioRecorderHelper = new AudioRecorderHelper();
        } else if (cfg.equals("vivo")) {
            vSpeech = new VivoRecognizer(context, this);
        } else {
            // "默认"(以及 ai 未配置、旧版残留值) → 系统默认识别服务。
            // 旧实现里 "默认" 会掉进 vivo 分支,非 vivo 机型上必然失败。
            speech = createRecognizer(null);
        }
    }

    /**
     * 供 TrimeService.applySpeechEngineChange() 调用:用户在设置页切换语音引擎后立即重建。
     * 与 start() 里的比对兜底互补——这里做到"选择即生效",不必等下次按语音键。
     */
    void reloadEngine() {
        initEngine();
        state = STATE_CANCEL;
    }

    private void releaseEngine() {
        if (mAudioRecorderHelper != null) {
            try { mAudioRecorderHelper.release(); } catch (Exception ignored) { }
            mAudioRecorderHelper = null;
        }
        if (vSpeech != null) {
            try { vSpeech.cancel(); } catch (Exception ignored) { }
            try { vSpeech.destroy(); } catch (Exception ignored) { }
            vSpeech = null;
        }
        if (speech != null) {
            try { speech.cancel(); } catch (Exception ignored) { }
            try { speech.destroy(); } catch (Exception ignored) { }
            speech = null;
        }
    }

    private boolean hasAudioPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true;
        return context.checkSelfPermission(RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    private void openPermissionSettings() {
        try {
            Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", context.getPackageName(), null));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(i);
        } catch (Exception e) {
            Log.w(TAG, "openPermissionSettings failed", e);
        }
    }


    private SpeechRecognizer createRecognizer(ComponentName cn) {
        try {
            SpeechRecognizer r = (cn == null)
                    ? SpeechRecognizer.createSpeechRecognizer(context)
                    : SpeechRecognizer.createSpeechRecognizer(context, cn);
            if (r != null) {
                r.setRecognitionListener(this);
                mDefaultRecognizer = (cn == null);
            }
            return r;
        } catch (Exception e) {
            Log.w(TAG, "createRecognizer failed: " + (cn == null ? "default" : cn.flattenToShortString()), e);
            return null;
        }
    }

    private HashMap<String, ComponentName> getService(Context context) {
        HashMap<String, ComponentName> appMap = new HashMap<>();
        ArrayList<String> list = new ArrayList<String>();
        PackageManager manager = context.getPackageManager();
        Intent mainIntent = new Intent(RecognitionService.SERVICE_INTERFACE); //取出Intent 为Action_Main的程序
        List<ResolveInfo> apps = manager.queryIntentServices(mainIntent, 0); //利用包管理器将起取出来
        Collections.sort(apps, new ResolveInfo.DisplayNameComparator(manager));

        int count = apps.size();
        for (int i = 0; i < count; i++) {
            //ApplicationInfo application = new ApplicationInfo();
            ResolveInfo info = apps.get(i);

            CharSequence title = info.loadLabel(manager);
            ComponentName componentName = new ComponentName(
                    info.serviceInfo.applicationInfo.packageName,
                    info.serviceInfo.name);
            appMap.put(title.toString(), componentName);
        }
        return appMap;
    }

    private void playSound(int id) {
        // release() 之后 mSoundPool 为 null。之前直接 play 会触发 native 层的
        // "no weak ref, object released" —— 说明销毁后还有回调在播报。
        SoundPool pool = mSoundPool;
        if (pool != null) {
            try {
                pool.play(id, 0.5f, 0.5f, 0, 0, 1);
            } catch (Throwable ignored) {
            }
        }
        vibrate();
    }

    public void vibrate() {
        if (mVibrator != null) {
            mVibrator.cancel();
            mVibrator.vibrate(duration);
        }
    }

    private void alert(String text) {
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show();
    }

    private final Handler mMainHandler = new Handler(Looper.getMainLooper());

    /**
     * 统一的"识别结果 → 上屏"流程。
     * <p>
     * OpenCC 转换首次调用要加载词典(实测可达数秒),原来它和 Lua 回调、commitText
     * 全在主线程跑,而这几步正好处在 SpeechRecognizer 的主线程 Handler 回调里 ——
     * 于是出现 "duration=5008ms ... InternalRecognitionListener.handleMessage",
     * 键盘整块卡住。这里把转换挪到后台线程,只把 Lua 回调和上屏 post 回主线程。
     */
    private void deliverResult(final String raw, final boolean s2t2, final boolean s2t) {
        if (raw == null) return;
        new Thread(() -> {
            String text = raw;
            if (s2t2) {
                try {
                    text = OpenCCDictManager.convertLine(raw, s2t ? "s2t.json" : "t2s.json");
                } catch (Throwable e) {
                    Log.w(TAG, "OpenCC convert failed", e);
                }
            }
            final String out = text;
            mMainHandler.post(() -> commitResult(out));
        }, "speech-convert").start();
    }

    /** 必须在主线程:ThemeManager.callFunction 跑 Lua,commitText 操作输入连接 */
    private void commitResult(String result) {
        try {
            TrimeService trime = TrimeService.getInstance();
            if (trime == null || result == null) return;
            Object ret = ThemeManager.callFunction("onSpeechResults", result);
            if (ret != null) {
                if (ret.equals(Boolean.FALSE)) return;
                if (ret instanceof String) result = ret.toString();
            }
            trime.commitText(result);
        } catch (Throwable e) {
            Log.w(TAG, "commitResult failed", e);
        }
    }


    public void start() {
        // 兜底:每次开始识别前比对配置,变了就地把引擎换掉。
        // 常规切换由 VoiceInputDialog → TrimeService.applySpeechEngineChange() 即时处理,
        // 这里是双保险(asr_config 被主题脚本热改、或偏好在别处被改时也能生效)。
        String cfgNow = Function.getPref(context).getString("recognition_service", "vivo");
        String asrSig = ThemeManager.getAsrConfigSignature();
        boolean engineChanged = mCfg == null || !mCfg.equals(cfgNow);
        boolean asrChanged = mAsrSig == null || !mAsrSig.equals(asrSig);
        if (engineChanged || asrChanged) {
            if (asrChanged) {
                Log.i(TAG, "asr_config 已变更,重建 ASR 客户端");
                ThemeManager.reloadAsrClient();
            }
            if (engineChanged) {
                Log.i(TAG, "识别引擎已切换: " + mCfg + " -> " + cfgNow);
            }
            initEngine();
            state = STATE_CANCEL;   // 换了引擎,旧状态作废
        }

        if (!hasAudioPermission()) {
            alert("缺少录音权限，请在系统设置里授予「录音」权限后重试");
            playSound(mSoundError);
            return;
        }
        if (speech == null && vSpeech == null && mAudioRecorderHelper == null) {
            alert("没有可用的语音识别引擎，请在语音设置里选择（如小爱同学、Google 语音服务）");
            playSound(mSoundError);
            return;
        }
        if (speech != null && mDefaultRecognizer && !SpeechRecognizer.isRecognitionAvailable(context)) {
            alert("系统没有默认的语音识别服务，请在语音设置里选择引擎（如小爱同学、Google 语音服务）");
            playSound(mSoundError);
            return;
        }
        Log.i(TAG, "start " + state);
        switch (state) {
            case STATE_BEGIN:
                stop();
                break;
            case STATE_START:
            case STATE_READY:
            case STATE_END:
                cancel();
                break;
            default:
                startListening();
        }
    }

    private void startListening() {
        if (mAudioRecorderHelper != null) {
            mAudioRecorderHelper.startRecord();
            state = STATE_START;
            state = STATE_BEGIN;
        } else if (vSpeech != null) {
            vSpeech.startInputting();
            state = STATE_START;
        } else if (speech != null) {
            recognizerIntent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
            // EXTRA_LANGUAGE_MODEL 是 RecognizerIntent 的必填项,缺了会被识别服务
            // 直接拒绝(ERROR_CLIENT / IllegalArgumentException),这正是"默认引擎用不了"的原因之一
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false);
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.getPackageName());
            // 尽量走在线识别:部分机型离线引擎只给 10 秒,在线一般更宽松也更准
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false);
            // 这三个只影响"说完后多久判定结束",很多机型会忽略,加上没有副作用
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L);
            recognizerIntent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 2000L);
            //recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "en");
            //recognizerIntent.putExtra(RecognizerIntent.EXTRA_PROMPT, "開始語音");
            speech.startListening(recognizerIntent);
            state = STATE_START;
        }

    }

    public void cancel() {
        playSound(mSoundCancel);
        state = STATE_CANCEL;
        vibrate();
        if (vSpeech != null)
            vSpeech.cancel();
        if (speech != null)
            speech.cancel();
    }

    public void stop() {
        Log.i(TAG, "stop");
        vibrate();
        if (mAudioRecorderHelper != null) {
            state = STATE_END;
            playSound(mSoundEnd);
            byte[] bs = mAudioRecorderHelper.stopRecord();
            AiClient.AiCallback cb = new AiClient.AiCallback() {
                @Override
                public void onSuccess(String result) {
                    Log.w(TAG, "onSuccess: " + result);
                    playSound(mSoundSuccess);
                    state = STATE_DONE;
                    if (TrimeService.getInstance() == null) return;
                    boolean s2t2 = Function.getPref(context).getBoolean("voice_input_s2t", false);
                    boolean s2t = !Rime.getRimeOption("simplification");
                    // 回调在 OkHttp 线程,不能直接碰 Lua 和输入连接
                    deliverResult(result, s2t2, s2t);
                }

                @Override
                public void onFailure(Exception e) {
                    Log.w(TAG, "onFailure: " + e.getMessage());
                    state = STATE_ERROR;
                    playSound(mSoundError);
                    alert(e.getMessage() == null ? "语音识别失败" : e.getMessage());
                }
            };
            // 专用 ASR 模型(SenseVoice / whisper / ASR)走 multipart 转写,
            // 免费且不受 10 秒限制;多模态理解模型仍走 chat/completions。
            if (mAsrClient != null && mAsrClient.isTranscribeMode()) {
                Log.i(TAG, "录音转写: " + bs.length + "B");
                mAsrClient.transcribeAudio(bs, cb);
            } else if (mAsrClient != null) {
                mAsrClient.recognizeAudio(bs, cb);
            }
            return;
        }
        if (vSpeech != null)
            vSpeech.stop();
        if (speech != null)
            speech.stopListening();
    }

    public void destroy() {
        releaseEngine();
        SoundPool pool = mSoundPool;
        mSoundPool = null;
        if (pool != null) {
            try { pool.setOnLoadCompleteListener(null); } catch (Throwable ignored) { }
            try { pool.release(); } catch (Throwable ignored) { }
        }
    }

    /** 窗口隐藏时用:停止识别,但保留对象和引擎,避免每次弹键盘都重新构造 */
    public void cancelSilently() {
        state = STATE_CANCEL;
        try {
            if (vSpeech != null) vSpeech.cancel();
        } catch (Throwable ignored) { }
        try {
            if (speech != null) speech.cancel();
        } catch (Throwable ignored) { }
    }

    @Override
    public void onBeginningOfSpeech() {
        try {
            state = STATE_BEGIN;
            Log.i(TAG, "onBeginningOfSpeech");
        } catch (Throwable e) {
            Log.w(TAG, "onBeginningOfSpeech failed", e);
        }
    }

    @Override
    public void onBufferReceived(byte[] buffer) {
        //Log.i(TAG, "onBufferReceived: " + buffer);
    }

    @Override
    public void onEndOfSpeech() {
        try {
            state = STATE_END;
            Log.i(TAG, "onEndOfSpeech");
            playSound(mSoundEnd);
        } catch (Throwable e) {
            Log.w(TAG, "onEndOfSpeech failed", e);
        }
        //alert("正在识别...");
    }

    @Override
    public void onError(int errorCode) {
        try {
            state = STATE_ERROR;
            Log.w(TAG, "onError: " + errorCode + " " + getErrorText(errorCode));
            if (errorCode == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                // 权限其实有:系统识别服务首次绑定时的偶发误报,识别通常照常进行,
                // 弹「权限不足」反而误导,这里只记日志。
                if (hasAudioPermission()) return;
                alert("缺少录音权限，请在系统设置里授予「录音」权限");
                playSound(mSoundError);
                openPermissionSettings();
                return;
            }
            alert(getErrorText(errorCode));
            playSound(mSoundError);
        } catch (Throwable e) {
            Log.w(TAG, "onError failed", e);
        }
    }

    @Override
    public void onEvent(int arg0, Bundle arg1) {
        Log.i(TAG, "onEvent");
    }

    @Override
    public void onPartialResults(Bundle arg0) {
        Log.i(TAG, "onPartialResults");
    }

    @Override
    public void onReadyForSpeech(Bundle arg0) {
        try {
            state = STATE_READY;
            Log.i(TAG, "onReadyForSpeech");
            //alert("开始说话：");
            playSound(mSoundStart);
            vibrate();
        } catch (Throwable e) {
            Log.w(TAG, "onReadyForSpeech failed", e);
        }
    }

    @Override
    public void onResults(Bundle results) {
        try {
            if (speech == null)
                return;
            //stop();
            playSound(mSoundSuccess);
            state = STATE_DONE;
            //Log.i(TAG, "onResults"+results);
            if (TrimeService.getInstance() == null) return;
            ArrayList<String> matches = results == null ? null
                    : results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
            //String opencc_config = Function.getPref(context).getString("voice_input_s2t_config","none");
            boolean s2t2 = Function.getPref(context).getBoolean("voice_input_s2t", false);
            boolean s2t = !Rime.getRimeOption("simplification");
            if (matches != null && !matches.isEmpty()) {
                // EXTRA_MAX_RESULTS=1,取第一条即可;全遍历会把多个候选连在一起上屏
                deliverResult(matches.get(0), s2t2, s2t);
            }
        } catch (Throwable e) {
            // 任何异常都不能穿透到 SpeechRecognizerImpl 的主线程 Handler,否则整个进程崩
            Log.w(TAG, "onResults failed", e);
        }
    }

    @Override
    public void onRmsChanged(float rmsdB) {
        //Log.i(TAG, "onRmsChanged: " + rmsdB);
    }

    private static String getErrorText(int errorCode) {
        String message;
        switch (errorCode) {
            case SpeechRecognizer.ERROR_AUDIO:
                message = "錄音錯誤";
                break;
            case SpeechRecognizer.ERROR_CLIENT:
                message = "客戶端錯誤";
                break;
            case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS:
                message = "权限不足";
                break;
            case SpeechRecognizer.ERROR_NETWORK:
                message = "網絡錯誤";
                break;
            case SpeechRecognizer.ERROR_NETWORK_TIMEOUT:
                message = "網絡超時";
                break;
            case SpeechRecognizer.ERROR_NO_MATCH:
                message = "未能識別";
                break;
            case SpeechRecognizer.ERROR_RECOGNIZER_BUSY:
                message = "識別服務忙";
                break;
            case SpeechRecognizer.ERROR_SERVER:
                message = "服務器錯誤";
                break;
            case SpeechRecognizer.ERROR_SPEECH_TIMEOUT:
                message = "無語音輸入";
                break;
            default:
                message = "未知錯誤";
                break;
        }
        return message;
    }

    public int getState() {
        return state;
    }


    @Override
    public void onReady() {
        onReadyForSpeech(null);
    }

    @Override
    public void onBegin() {
        onBeginningOfSpeech();
    }

    @Override
    public void onEnd() {
        onEndOfSpeech();
    }

    @Override
    public void onResult(String result) {
        try {
            if (vSpeech == null && speech == null)
                return;
            //stop();
            playSound(mSoundSuccess);
            state = STATE_DONE;
            if (TrimeService.getInstance() == null) return;
            boolean s2t2 = Function.getPref(context).getBoolean("voice_input_s2t", false);
            boolean s2t = !Rime.getRimeOption("simplification");
            deliverResult(result, s2t2, s2t);
        } catch (Throwable e) {
            Log.w(TAG, "onResult failed", e);
        }
    }

    @Override
    public void onError(String msg) {
        try {
            state = STATE_ERROR;
            alert(msg);
            playSound(mSoundError);
        } catch (Throwable e) {
            Log.w(TAG, "onError(String) failed", e);
        }
    }
}

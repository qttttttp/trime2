package com.osfans.trime.speech;

import android.media.MediaRecorder;
import android.os.Bundle;
import android.util.Log;

import com.androlua.LuaApplication;
import com.osfans.trime.BuildConfig;
import com.osfans.trime.TrimeService;
import com.vivo.speechsdk.api.InitListener;
import com.vivo.speechsdk.api.SpeechConstants;
import com.vivo.speechsdk.api.SpeechError;
import com.vivo.speechsdk.api.SpeechEvent;
import com.vivo.speechsdk.api.SpeechSdk;
import com.vivo.speechsdk.asr.api.ASREngine;
import com.vivo.speechsdk.asr.api.IRecognizerListener;
import com.vivo.speechsdk.asr.api.IUpdateHotWordListener;

import org.json.JSONException;
import org.json.JSONObject;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

public class VivoRecognizer implements Recognizer, IRecognizerListener {

    private final TrimeService mService;
    private final RecognizerListener mListener;
    private ASREngine mEngine;

    public VivoRecognizer(TrimeService service, RecognizerListener listener) {
        mService = service;
        mListener = listener;
        init2();
    }

    private void init2() {
        if(!SpeechSdk.isInit()){
            SpeechSdk.init(LuaApplication.getInstance(), UUID.randomUUID().toString(), new InitListener() {
                @Override
                public void onSuccess() {
                    Log.w("VivoSdk", "onSuccess: ");
                    init2();
                }

                @Override
                public void onError(SpeechError error) {
                    Log.w("VivoSdk", "onError: "+error.getDescription() );
                }
            });
            return;
        }


        mEngine = ASREngine.createEngine();
        Bundle bundle = new Bundle();
        bundle.putString(SpeechConstants.KEY_APPID, BuildConfig.API_ID);
        bundle.putString(SpeechConstants.KEY_APPKEY, BuildConfig.API_KEY);
        bundle.putInt(SpeechConstants.KEY_ENGINE_MODE, SpeechConstants.TYPE_ENGINE_MODE_ONLINE);
        bundle.putString(SpeechConstants.KEY_ENGINE_TYPE, "shortasrinput");
        bundle.putBoolean(SpeechConstants.KEY_PRELOAD_ENABLE, false);
        bundle.putBoolean(SpeechConstants.KEY_CONNECTION_REUSE_ENABLE, true);
        mEngine.init(bundle, new InitListener() {
            @Override
            public void onSuccess() {
                //do something
            }

            @Override
            public void onError(SpeechError error) {
                //do something
            }
        });
    }

    @Override
    public void startListening() {
        if(mEngine==null){
            init2();
            return;
        }
        Bundle bundle = new Bundle();
        bundle.putBoolean(SpeechConstants.KEY_INNER_RECORD, true);
        bundle.putInt(SpeechConstants.KEY_REQUEST_MODE, SpeechConstants.TYPE_REQUEST_MODE_ASR);
        bundle.putString(SpeechConstants.KEY_BUSINESS_INFO, "vivo");
        bundle.putString(SpeechConstants.KEY_VAD_MODE, "normal");
        bundle.putInt(SpeechConstants.KEY_VAD_KEEP_SILENCE_COUNT, 8);
        bundle.putInt(SpeechConstants.KEY_AUDIO_SOURCE, MediaRecorder.AudioSource.MIC);
        bundle.putInt(SpeechConstants.KEY_PUNCTUATION, 2);
        bundle.putInt(SpeechConstants.KEY_VAD_FRONT_TIME, 5000);
        bundle.putInt(SpeechConstants.KEY_VAD_END_TIME, 1000);
        bundle.putBoolean(SpeechConstants.KEY_VAD_ENABLE, true);
        bundle.putBoolean(SpeechConstants.KEY_CHINESE_TO_DIGITAL, true);
        bundle.putInt(SpeechConstants.KEY_ASR_TIME_OUT, 5000);
        bundle.putBoolean(SpeechConstants.KEY_ENCODE_ENABLE, true);
        int code = mEngine.start(bundle, this);
        if (code != 0) {
            mListener.onError(String.valueOf(code));
            //start failed do something
        }
    }

    @Override
    public void startInputting() {
        if(mEngine==null){
            init2();
            return;
        }
        Bundle bundle = new Bundle();
        bundle.putBoolean(SpeechConstants.KEY_INNER_RECORD, true);
        bundle.putInt(SpeechConstants.KEY_REQUEST_MODE, SpeechConstants.TYPE_REQUEST_MODE_ASR);
        bundle.putString(SpeechConstants.KEY_BUSINESS_INFO, "vivo");
        bundle.putString(SpeechConstants.KEY_VAD_MODE, "normal");
        bundle.putInt(SpeechConstants.KEY_VAD_KEEP_SILENCE_COUNT, 4);
        bundle.putInt(SpeechConstants.KEY_AUDIO_SOURCE, MediaRecorder.AudioSource.MIC);
        bundle.putInt(SpeechConstants.KEY_PUNCTUATION, 1);
        bundle.putInt(SpeechConstants.KEY_VAD_FRONT_TIME, 5000);
        bundle.putInt(SpeechConstants.KEY_VAD_END_TIME, 5000);
        bundle.putBoolean(SpeechConstants.KEY_VAD_ENABLE, true);
        bundle.putBoolean(SpeechConstants.KEY_CHINESE_TO_DIGITAL, true);
        bundle.putInt(SpeechConstants.KEY_ASR_TIME_OUT, 5000);
        bundle.putBoolean(SpeechConstants.KEY_ENCODE_ENABLE, true);
        int code = mEngine.start(bundle, this);
        if (code != 0) {
            mListener.onError(String.valueOf(code));
            //start failed do something
        }
    }

    @Override
    public void stop() {
        if(mEngine==null){
            return;
        }
        mEngine.stop();
    }

    @Override
    public void cancel() {
        if(mEngine==null){
            return;
        }
        mEngine.cancel();
    }

    @Override
    public void destroy() {
        if(mEngine==null){
            return;
        }
        mEngine.destroy();
    }

    @Override
    public void updateUserData() {
    }

    @Override
    public void setLanguage(String language) {

    }

    @Override
    public void onResult(int i, String s) {
        try {
            JSONObject json = new JSONObject(s);
            if(json.getBoolean("is_last")) {
                mListener.onEnd();
                mService.getHandler().post(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            mListener.onResult(json.getString("text"));
                        } catch (Exception e) {
                            mListener.onError(e.toString());
                        }
                    }
                });
            }
        } catch (Exception e) {
            mListener.onResult(s);
        }
    }

    @Override
    public void onSpeechStart() {
        mListener.onBegin();
    }

    @Override
    public void onSpeechEnd() {
    }

    @Override
    public void onRecordStart() {
        mListener.onReady();
    }

    @Override
    public void onRecordEnd() {

    }

    @Override
    public void onVolumeChanged(int i, byte[] bytes) {

    }

    @Override
    public void onEnd() {
    }

    @Override
    public void onEvent(int i, Bundle bundle) {
        //Log.w("TAG", "onEvent: "+i +bundle);
    }

    @Override
    public void onError(SpeechError speechError) {
        mListener.onError(speechError.getDescription());
    }
}

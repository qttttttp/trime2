package com.osfans.trime.speech;

/**
 * Created by nirenr on 2018/11/30 0030.
 */

public interface RecognizerListener {
    public void onReady();
    public void onBegin();
    public void onEnd();
    public void onResult(String text);
    public void onError(String msg);

}

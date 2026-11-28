package com.osfans.trime.speech;

/**
 * Created by nirenr on 2018/11/30 0030.
 */

public interface Recognizer {
    public String zh_CN="zh_CN";
    public String zh_GD="zh_GD";
    public String en_GB="en_GB";

    public void startListening();
    public void startInputting();
    public void stop();
    public void cancel();
    public void destroy();
    public void updateUserData();
    public void setLanguage(String language);

}

package com.androlua;

import android.graphics.drawable.*;
import android.graphics.*;

import androidx.annotation.NonNull;

import org.luaj.LuaError;
import org.luaj.LuaFunction;
import org.luaj.LuaValue;
import com.osfans.trime.BuildConfig;


public class LuaDrawable extends Drawable {

    //private final LuaContext mContext;
    private LuaValue mDraw;

    private Paint mPaint;
    private LuaFunction mOnDraw;


    public LuaDrawable(LuaFunction func) {
        mDraw = func;
        mPaint = new Paint();
        //mContext = mDraw.getLuaState().getContext();
    }

    @Override
    public void draw(@NonNull Canvas p1) {
        try {
            if (mOnDraw == null) {
                Object r = mDraw.jcall(p1, mPaint, this);
                if (r != null && r instanceof LuaFunction)
                    mOnDraw = (LuaFunction) r;
            }
            if (mOnDraw != null) {
                mOnDraw.jcall(p1);
            }
        } catch (LuaError e) {
            if(BuildConfig.DEBUG)
			    e.printStackTrace();
        }
    }

    @Override
    public void setAlpha(int p1) {
        mPaint.setAlpha(p1);
        // TODO: Implement this method
    }

    @Override
    public void setColorFilter(ColorFilter p1) {
        mPaint.setColorFilter(p1);
        // TODO: Implement this method
    }

    @Override
    public int getOpacity() {
        // TODO: Implement this method
        return PixelFormat.UNKNOWN;
    }

    public Paint getPaint() {
        return mPaint;
    }
}

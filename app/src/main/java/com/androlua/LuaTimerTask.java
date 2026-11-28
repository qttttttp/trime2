package com.androlua;

import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaValue;

import java.io.*;
import java.util.regex.*;

public class LuaTimerTask extends TimerTaskX {
    private Globals L;

    private LuaContext mLuaContext;

    private LuaValue[] mArg = new LuaValue[0];

    private boolean mEnabled = true;

    private LuaValue mBuffer;

    public LuaTimerTask(LuaContext luaContext, LuaValue func, LuaValue[] arg) throws LuaError {
        mLuaContext = luaContext;
        if (arg != null)
            mArg = arg;
        mBuffer = func;
    }


    @Override
    public void run() {
        if (!mEnabled)
            return;
        mBuffer.invoke(mArg);

    }

    @Override
    public boolean cancel() {
        // TODO: Implement this method
        return super.cancel();
    }

    public void setArg(LuaValue... arg) {
        mArg = arg;
    }

    public void setEnabled(boolean enabled) {
        mEnabled = enabled;
    }

    public boolean isEnabled() {
        return mEnabled;
    }

};

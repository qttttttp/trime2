package org.luaj.android;

import android.annotation.SuppressLint;
import android.os.AsyncTask;

import com.androlua.AsyncTaskX;
import com.androlua.LuaContext;
import com.androlua.LuaGcable;
import com.osfans.trime.BuildConfig;

import org.luaj.Globals;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;

public class task extends VarArgFunction implements LuaGcable {
    private final LuaContext mCotext;
    private final Globals globals;
    private AsyncTaskX<Varargs, Varargs, Varargs> mTask;

    public task(LuaContext context) {
        mCotext = context;
        globals = mCotext.getLuaState();
        context.regGc(this);
    }

    @SuppressWarnings("deprecation")
    @SuppressLint("StaticFieldLeak")
    public Varargs invoke(Varargs args) {
        int n = args.narg();
        int i = n - 2;
        i = i >= 0 ? i : 0;
        LuaValue[] as = new LuaValue[i];
        LuaValue func = args.arg1();
        for (int i1 = 0; i1 < n - 2; i1++) {
            as[i1] = args.arg(i1 + 2);
        }
        mTask=new AsyncTaskX<Varargs, Varargs, Varargs>() {
            @Override
            protected Varargs doInBackground(Varargs... objects) {
                if (func.isnumber()) {
                    try {
                        Thread.sleep(func.tolong());
                    } catch (Exception e) {
                        if (BuildConfig.DEBUG)
                            e.printStackTrace();
                    }
                    return LuaValue.varargsOf(as);
                }
                try {
                    return func.invoke(as);
                } catch (Exception e) {
                    if (BuildConfig.DEBUG)
                        e.printStackTrace();
                    mCotext.sendError("task", e);
                    return LuaValue.varargsOf(new LuaValue[]{LuaValue.NIL, LuaValue.valueOf(e.toString())});
                }
            }

            @Override
            protected void onPostExecute(Varargs varargs) {
                if (n > 1) {
                    try {
                        args.arg(n).invoke(varargs);
                    } catch (Exception e) {
                        if (BuildConfig.DEBUG)
                            e.printStackTrace();
                        mCotext.sendError("task", e);
                    }
                }
            }
        };
        mTask.execute();
        return CoerceJavaToLua.coerce(mTask);
    }

    @Override
    public void gc() {
        if(mTask!=null)
            mTask.cancel(true);
    }

    @Override
    public boolean isGc() {
        return false;
    }
}

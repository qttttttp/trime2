package org.luaj.android;

import android.util.Log;

import com.androlua.LuaActivity;
import com.androlua.LuaContext;
import com.osfans.trime.BuildConfig;

import org.luaj.Globals;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;

public class call extends VarArgFunction {

    private final LuaContext mCotext;
    private final Globals globals;

    public call(LuaContext context){
        mCotext=context;
        globals=mCotext.getLuaState();
    }
    public Varargs invoke(Varargs args) {
        final LuaValue fn = args.arg1();
        int n = args.narg()-1;
        LuaValue[] as=new LuaValue[n];
        for (int i = 0; i < n; i++) {
            as[i]=args.arg(i+2);
        }
        ((LuaActivity)mCotext.getContext()).runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    if(fn.isfunction())
                        fn.invoke(as);
                    else
                        globals.get(fn).invoke(as);
                } catch (Exception e){
                    if(BuildConfig.DEBUG)
                        e.printStackTrace();
                    mCotext.sendError(toString(),e);
                }      }
        });
        return LuaValue.NONE;
    }
}

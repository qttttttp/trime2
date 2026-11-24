package org.luaj.android;

import com.androlua.LuaContext;
import com.androlua.LuaTimer;

import org.luaj.Globals;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;

public class timer extends VarArgFunction {

    private final LuaContext mCotext;
    private final Globals globals;
    private LuaTimer mLuaTimer;

    public timer(LuaContext context){
        mCotext=context;
        globals=mCotext.getLuaState();
    }
    public Varargs invoke(Varargs args) {
        final LuaValue fn = args.arg1();
        int d = args.arg(2).toint();
        int p = args.arg(3).toint();
        int n = args.narg()-3;
        LuaValue[] as=new LuaValue[n];
        for (int i = 0; i < n; i++) {
            as[i]=args.arg(i+4);
        }
        mLuaTimer=new LuaTimer(mCotext,fn,as);
        mLuaTimer.start(d,p);
        return CoerceJavaToLua.coerce(mLuaTimer);
    }
}

package org.luaj.android;

import com.androlua.LuaContext;
import com.osfans.trime.BuildConfig;

import org.luaj.Globals;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;

public class thread extends VarArgFunction {

    private final LuaContext mCotext;
    private final Globals globals;

    public thread(LuaContext context){
        mCotext=context;
        globals=mCotext.getLuaState();
    }
    public Varargs invoke(Varargs args) {
        LuaValue f = args.arg1();
        int n = args.narg()-1;
        LuaValue[] as=new LuaValue[n];
        for (int i = 0; i < n; i++) {
            as[i]=args.arg(i+2);
        }
        Thread t = new Thread() {
            @Override
            public void run() {
                try {
                    f.invoke(as);
                } catch (Exception e){
                    if(BuildConfig.DEBUG)
                        e.printStackTrace();
                    mCotext.sendError(toString(),e);
                }
             }
        };
        t.start();
         return CoerceJavaToLua.coerce(t);
    }
}

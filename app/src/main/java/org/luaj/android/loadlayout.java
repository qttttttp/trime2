package org.luaj.android;

import android.content.Context;

import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.luaj.Globals;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;

public class loadlayout extends VarArgFunction {
    private final Context mCotext;
    private final Globals globals;

    public loadlayout(LuaContext context){
        mCotext=context.getContext();
        globals=context.getLuaState();
    }
    public loadlayout(Context context,Globals globals){
        mCotext=context;
        this.globals=globals;
    }
    public Varargs invoke(Varargs args) {
        if (args.narg() == 1)
            return new LuaLayout(mCotext).load(args.arg1(), globals);
        return new LuaLayout(mCotext).load(args.arg1(), args.arg(2).checktable());
    }
}

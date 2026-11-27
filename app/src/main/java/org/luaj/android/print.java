 package org.luaj.android;

import android.util.Log;

import com.androlua.LuaContext;
import com.osfans.trime.TrimeService;

import org.luaj.Globals;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;

public class print extends VarArgFunction {
    private LuaContext mCotext;
    private final Globals globals;
    private TrimeService mTrime;

    public print(LuaContext context){
        mCotext=context;
        globals=mCotext.getLuaState();
    }
    public print(TrimeService context,Globals globals){
        mTrime=context;
        this.globals=globals;
    }
    public Varargs invoke(Varargs args) {
        LuaValue tostring = globals.baselib.tostring;
        StringBuilder buf = new StringBuilder();
        for (int i = 1, n = args.narg(); i <= n; i++) {
            buf.append((tostring.call(args.arg(i)).tojstring()));
            if(i < n)
                buf.append("    ");
        }
        if(mCotext==null){
            mTrime=TrimeService.getInstance();
        }

        if(mTrime!=null)
            mTrime.sendMsg(buf.toString());
        else
            mCotext.sendMsg(buf.toString());
        return NONE;
    }
}


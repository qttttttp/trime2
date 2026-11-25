package org.luaj.android;

import com.androlua.LuaContext;
import com.osfans.trime.TrimeService;

import org.luaj.Globals;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;

public class printf extends VarArgFunction {
    private LuaContext mCotext;
    private final Globals globals;
    private TrimeService mTrime;

    public printf(LuaContext context){
        mCotext=context;
        globals=mCotext.getLuaState();
    }
    public printf(TrimeService context, Globals globals){
        mTrime=context;
        this.globals=globals;
    }
    public Varargs invoke(Varargs args) {
        String ss = globals.stringlib.format.invoke(args).tojstring();
        if(mCotext==null){
            mTrime=TrimeService.getInstance();
        }
        if(mTrime!=null)
            mTrime.sendMsg(ss);
        else
            mCotext.sendMsg(ss);
        return NONE;
    }
}

package com.androlua;

import android.content.Context;
import android.view.View;
import android.widget.FrameLayout;

import org.luaj.LuaValue;

public class LuaView extends FrameLayout {
    public LuaView(Context context) {
        super(context);
    }
    public LuaView(Context context, LuaValue value) {
        super(context);
        addView(new LuaLayout(context).load(value).touserdata(View.class));
    }
}

package com.androlua;

import android.annotation.SuppressLint;
import android.app.*;
import android.view.*;
import android.os.*;

import org.luaj.*;

@SuppressLint("ValidFragment")
public class LuaFragment extends Fragment {

    private LuaTable mLayout = null;
    private LuaTable mEnv;

    public LuaFragment(LuaTable layout) {
        mLayout = layout;
    }

    public void setLayout(LuaTable layout) {
        mLayout = layout;
    }

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        try {
            mEnv = new LuaTable();
            return new LuaLayout(getActivity()).load(mLayout, mEnv).touserdata(View.class);
        } catch (LuaError e) {
            throw new IllegalArgumentException(e.getMessage());
        }
    }

    public LuaValue getView(String id) {
        if(mEnv==null)
            return null;
        return mEnv.get(id);
    }
}

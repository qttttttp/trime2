package com.androlua;

import android.annotation.SuppressLint;
import android.os.Bundle;
import android.preference.Preference;
import android.preference.PreferenceFragment;
import android.preference.PreferenceScreen;

import org.luaj.LuaError;
import org.luaj.Globals;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import com.osfans.trime.BuildConfig;
import org.luaj.lib.jse.CoerceJavaToLua;

/**
 * Created by Administrator on 2018/08/05 0005.
 */

@SuppressLint("ValidFragment")
public class LuaPreferenceFragment extends PreferenceFragment implements Preference.OnPreferenceChangeListener, Preference.OnPreferenceClickListener {

    private LuaTable mPreferences;
    private Preference.OnPreferenceChangeListener mOnPreferenceChangeListener;
    private Preference.OnPreferenceClickListener mOnPreferenceClickListener;

    public LuaPreferenceFragment(LuaTable preferences){
        super();
        mPreferences=preferences;
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        setPreferenceScreen(getPreferenceManager().createPreferenceScreen(getActivity()));
        //addPreferencesFromResource(R.xml.preference_screen);
        try{
            init(mPreferences);
        }catch (Exception e){
            LuaActivity.logError("LuaPreferenceFragment", e);
            if(BuildConfig.DEBUG)
                e.printStackTrace();
        }
    }

    public void setPreference(LuaTable preferences) {
        mPreferences = preferences;
    }

    private void init(LuaTable preferences) {
        PreferenceScreen ps = getPreferenceScreen();
        int len = preferences.length();
        Globals L = preferences.getGlobals();
        for (int i = 1; i <= len; i++) {
            LuaTable p = preferences.get(i).checktable();
            try {
                LuaValue cls = p.get(1);
                if (cls.isnil()) {
                    throw new IllegalArgumentException("First value Must be a Class<Preference>, checked import package.");
                }
                Preference pf = (Preference) cls.jcall(getActivity());
                pf.setOnPreferenceChangeListener(this);
                pf.setOnPreferenceClickListener(this);
                LuaValue[] ks = p.keys();
                for (LuaValue et : ks) {
                    if (et.isstring()) {
                        try {
                            javaSetter(pf, et.tojstring(), p.get(et));
                        } catch (LuaError e) {
                            e.printStackTrace();
                        }
                    }
                }
                  ps.addPreference(pf);
            } catch (Exception e) {
                //L.getContext().sendError("LuaPreferenceFragment",e);
            }
        }
    }

    private void javaSetter(Object obj, String methodName, Object value) throws LuaError {
        CoerceJavaToLua.coerce(obj).jset(methodName, value);
    }

    public void setOnPreferenceChangeListener(Preference.OnPreferenceChangeListener listener) {
        mOnPreferenceChangeListener = listener;
    }

    public void setOnPreferenceClickListener(Preference.OnPreferenceClickListener listener) {
        mOnPreferenceClickListener = listener;
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        if (mOnPreferenceChangeListener != null)
            return mOnPreferenceChangeListener.onPreferenceChange(preference, newValue);
        return true;
    }

    @Override
    public boolean onPreferenceClick(Preference preference) {
        if (mOnPreferenceClickListener != null)
            return mOnPreferenceClickListener.onPreferenceClick(preference);
        return false;
    }
}

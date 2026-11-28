package com.myopicmobile.textwarrior.common;

import android.text.SpannableString;
import android.text.TextUtils;
import android.text.style.ForegroundColorSpan;
import android.util.Log;

import org.luaj.Globals;
import org.luaj.LocVars;
import org.luaj.LuaString;
import org.luaj.LuaValue;
import org.luaj.Prototype;
import org.luaj.Upvaldesc;
import com.osfans.trime.BuildConfig;

import java.io.IOException;
import java.io.InputStream;
import java.io.UnsupportedEncodingException;
import java.util.ArrayList;
import java.util.HashMap;

/**
 * Created by nirenr on 2019/11/23.
 */

public class LuaParser {
    private static HashMap<String, ArrayList<Pair>> localMap = new HashMap<>();
    private static ArrayList<Var> varList = new ArrayList<>();
    private static ArrayList<Var> funcList = new ArrayList<>();
    private static ArrayList<LuaString> globalist = new ArrayList<>();

    public static void reset() {
        if (varList.isEmpty())
            return;
        localMap.clear();
        varList.clear();
        funcList.clear();
        globalist = new ArrayList<>();
        LexState.errormsg = null;
        LexState.globalsList.clear();
        LexState.lines.clear();
        LexState.valueMap.clear();
    }

    public static class Var {
        public int idx;
        public String name;
        public String type;
        public int startidx;
        public int endidx;

        public Var(String n, String t, int s, int e) {
            name = n;
            type = t;
            startidx = s;
            endidx = e;
        }

        public Var(String n, String t, int s, int e, int i) {
            name = n;
            type = t;
            startidx = s;
            endidx = e;
            idx = i;
        }

        @Override
        public String toString() {
            return String.format("Var (%s %s %s-%s)", name, type, startidx, endidx);
        }
    }

    public static class CharInputSteam extends InputStream {

        private final CharSequence mSrc;
        private final int mLen;
        private int idx = 0;

        public CharInputSteam(CharSequence src) {
            mSrc = src;
            mLen = src.length();
        }

        @Override
        public int read() throws IOException {
            idx++;
            if (idx > mLen)
                return -1;
            return mSrc.charAt(idx - 1);
        }
    }

    public static boolean lexer(CharSequence src, Globals globals, Flag _abort) {
        try {
            //Prototype lex = LuaC.lexer(new CharInputSteam(src), "luaj");
            if(TextUtils.isEmpty(src))
                return true;
            if (BuildConfig.DEBUG)
                Log.i("luaj", "lexer: start");
            Prototype lex = LuaC.lexer(src, "luaj", globals, _abort);
            localMap.clear();
            varList.clear();
            funcList.clear();
            if (BuildConfig.DEBUG)
                Log.i("luaj", "lexer: ");
            lexer(lex);
            if (LexState.erroridx < 0)
                globalist = new ArrayList<>(LexState.globalsList);
            if (BuildConfig.DEBUG)
                Log.i("luaj", "lexer: end");
            return true;
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
        }
        return false;
    }

    public static HashMap<String, ArrayList<Pair>> getLocalMap() {
        return localMap;
    }

    public static ArrayList<Var> getFuncList() {
        return funcList;
    }

    private static void lexer(Prototype p) {
        if (p == null)
            return;
        LocVars[] ls = p.locvars;
        int np = p.numparams;
        Upvaldesc[] us = p.upvalues;
        for (int i = 0; i < us.length; i++) {
            Upvaldesc l = us[i];
            String n = l.name.tojstring();
            varList.add(new Var(n, " :upval", p.startidx, p.endidx));
        }
        StringBuilder buf = new StringBuilder();
        buf.append(" :(");
        for (int i = 0; i < ls.length; i++) {
            LocVars l = ls[i];
            String n = l.varname.tojstring();
            if (i < np) {
                varList.add(new Var(n, " :arg", l.startidx, l.endidx));
                buf.append(n);
                if (i < np - 1)
                    buf.append(",");
            } else {
                varList.add(new Var(n, " :local", l.startidx, l.endidx));
            }
            ArrayList<Pair> a = localMap.get(n);
            if (a == null) {
                a = new ArrayList<>();
                localMap.put(n, a);
            }
            a.add(new Pair(l.startidx, l.endidx));
        }
        buf.append(")");
        if (p.name != null) {
            Var f = new Var(p.name, buf.toString(), 0, 1000000, p.linedefined);
            varList.add(f);
            funcList.add(f);
        }
        Prototype[] ps = p.p;
        for (Prototype l : ps) {
            lexer(l);
        }
    }

    private static ArrayList<String> userWord = new ArrayList<>();

    public static void clearUserWord() {
        userWord.clear();
    }

    public static ArrayList<String> getUserWord() {
        return new ArrayList<>(userWord);
    }

    public static void addUserWord(String s) {
        userWord.add(s);
    }

    public static ArrayList<CharSequence> filterLocal(String name, int idx, ColorScheme colorScheme) {
        ArrayList<CharSequence> ret = new ArrayList<>();
        ArrayList<CharSequence> ca = new ArrayList<>();

        for (int i = varList.size() - 1; i >= 0; i--) {
            Var var = varList.get(i);
            if (var.startidx <= idx && var.endidx >= idx) {
                String n = var.name;
                if (ca.contains(n))
                    continue;
                ca.add(n);
                if (n.toLowerCase().startsWith(name))
                    ret.add(getColorText(n + var.type, colorScheme.getTokenColor(getType(var.type))));
                String p = getSpells(n);
                if (TextUtils.isEmpty(p))
                    continue;
                if (p.startsWith(name))
                    ret.add(getColorText(n + var.type, colorScheme.getTokenColor(getType(var.type))));
            }
        }
        ArrayList<LuaString> ks = globalist;
        for (LuaValue k : ks) {
            String n = k.tojstring();
            if (ca.contains(n))
                continue;
            ca.add(n);
            if (n.toLowerCase().startsWith(name))
                ret.add(getColorText(n + " :global", colorScheme.getTokenColor(Lexer.GLOBAL)));
            String p = getSpells(n);
            if (TextUtils.isEmpty(p))
                continue;
            if (p.startsWith(name))
                ret.add(getColorText(n + " :global", colorScheme.getTokenColor(Lexer.GLOBAL)));
        }
        return ret;
    }

    private static int getType(String type) {
        switch (type) {
            case " :upval":
                return Lexer.UPVAL;
            case " :arg":
            case " :local":
                return Lexer.LOCAL;
            case " :global":
                return Lexer.GLOBAL;
        }
        return 0;
    }

    private static CharSequence getColorText(String text, int color) {
        SpannableString ss = new SpannableString(text);
        ss.setSpan(new ForegroundColorSpan(color), 0, text.length(), 0);
        return ss;
    }


    private static final int GB_SP_DIFF = 160;
    private static final int[] secPosValueList = {1601, 1637, 1833, 2078, 2274, 2302,
            2433, 2594, 2787, 3106, 3212, 3472, 3635, 3722, 3730, 3858, 4027,
            4086, 4390, 4558, 4684, 4925, 5249, 5600};
    private static final char[] firstLetter = {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
            'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'w', 'x',
            'y', 'z'};

    private static String getSpells(String characters) {
        try {
            StringBuilder buffer = new StringBuilder();
            for (int i = 0; i < characters.length(); i++) {
                char ch = characters.charAt(i);
                if (i == 0 && ch < 128) {
                    return null;
                }
                if ((ch >> 7) == 0) {
                    buffer.append(ch);
                } else {
                    char spell = getFirstLetter(ch);
                    if (spell == 0) {
                        continue;
                    }
                    buffer.append(String.valueOf(spell));
                }
            }
            return buffer.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private static char getFirstLetter(char ch) {
        byte[] uniCode = null;
        try {
            uniCode = String.valueOf(ch).getBytes("GBK");
        } catch (UnsupportedEncodingException e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
            return 0;
        }
        if (uniCode[0] < 128 && uniCode[0] > 0) {
            return 0;
        } else {
            return convert(uniCode);
        }
    }

    public static char convert(byte[] bytes) {
        char result = 0;
        int secPosValue = 0;
        int i;
        for (i = 0; i < bytes.length; i++) {
            bytes[i] -= GB_SP_DIFF;
        }
        secPosValue = bytes[0] * 100 + bytes[1];
        for (i = 0; i < 23; i++) {
            if (secPosValue >= secPosValueList[i]
                    && secPosValue < secPosValueList[i + 1]) {
                result = firstLetter[i];
                break;
            }
        }
        return result;
    }


}

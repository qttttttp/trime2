/*
 * Copyright (C) 2015-present, osfans
 * waxaca@163.com https://github.com/osfans
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package com.osfans.trime;

import android.text.TextUtils;
import android.util.Log;
import android.view.KeyEvent;

import com.osfans.trime.core.RimeKeyMap;
import com.osfans.trime.keyboard.ModifierState;
import com.osfans.trime.keyboard.KeyboardView;

import java.io.File;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import com.osfans.trime.core.Rime;

import org.luaj.LuaValue;

/**
 * {@link Key 按鍵}的各種事件（單擊、長按、滑動等）
 */
public class Event {
    private String mRaw;
    private Integer index = 0;
    private String TAG = "Event";
    private int code = 0;
    private int mask = 0;
    private String text;
    private String label;
    private String description;
    private String preview;
    private List<String> states;
    private String command;
    private String option;
    private String select;
    private String toggle;
    private String commit;

    private String shiftLock = "click";
    private boolean functional;
    private boolean repeatable;
    private boolean sticky;

    public static boolean hasModifier(int mask, int modifier) {
        return (mask & modifier) > 0;
    }


    private static Map<String, Integer> masks =
            new HashMap<String, Integer>() {
                {
                    put("Shift", KeyEvent.META_SHIFT_ON);
                    put("Control", KeyEvent.META_CTRL_ON);
                    put("Alt", KeyEvent.META_ALT_ON);
                }
            };

    private final static Map<String, Integer> symbolAliases =
            new HashMap<String, Integer>() {
                {
                    put("#", KeyEvent.KEYCODE_POUND);
                    put("'", KeyEvent.KEYCODE_APOSTROPHE);
                    put("(", KeyEvent.KEYCODE_NUMPAD_LEFT_PAREN);
                    put(")", KeyEvent.KEYCODE_NUMPAD_RIGHT_PAREN);
                    put("*", KeyEvent.KEYCODE_STAR);
                    put("+", KeyEvent.KEYCODE_PLUS);
                    put(",", KeyEvent.KEYCODE_COMMA);
                    put("-", KeyEvent.KEYCODE_MINUS);
                    put(".", KeyEvent.KEYCODE_PERIOD);
                    put("/", KeyEvent.KEYCODE_SLASH);
                    put(";", KeyEvent.KEYCODE_SEMICOLON);
                    put("=", KeyEvent.KEYCODE_EQUALS);
                    put("@", KeyEvent.KEYCODE_AT);
                    put("\\", KeyEvent.KEYCODE_BACKSLASH);
                    put("[", KeyEvent.KEYCODE_LEFT_BRACKET);
                    put("`", KeyEvent.KEYCODE_GRAVE);
                    put("]", KeyEvent.KEYCODE_RIGHT_BRACKET);
                }
            };

    public static String getDisplayLabel(int keyCode) {
        String s = "";
        if (keyCode < Key.getSymbolStart()) { //字母數字
            if (Key.getKcm().isPrintingKey(keyCode)) {
                char c = Key.getKcm().getDisplayLabel(keyCode);
                if (Character.isUpperCase(c)) c = Character.toLowerCase(c);
                s = String.valueOf(c);
            } else {
                s = Key.androidKeys.get(keyCode);
            }
        } else if (keyCode < Key.getSymbols().length() + Key.getSymbolStart()) { //可見符號
            keyCode -= Key.getSymbolStart();
            s = Key.getSymbols().substring(keyCode, keyCode + 1);
        }
        return s;
    }

    public static int[] parseSend(String s) {
        int[] sends = new int[2];
        if (TextUtils.isEmpty(s)) return sends;
        String codes;
        if (!s.contains("+")) codes = s;
        else {
            String[] ss = s.split("\\+");
            int n = ss.length;
            for (int i = 0; i < n - 1; i++)
                if (masks.containsKey(ss[i])) sends[1] |= masks.get(ss[i]);
            codes = ss[n - 1];
        }
        sends[0] = getClickCode(codes);
        return sends;
    }

    public static int getClickCode(String s) {
        if (s == null || s.isEmpty()) {
            return 0;
        }
        // 直接从 Map 获取，时间复杂度 O(1)
        Integer code = CLICK_CODE_CACHE.get(s);
        return (code != null) ? code : -1;
    }

    /*public static int getClickCode(String s) {
        int keyCode = -1;
        if (TextUtils.isEmpty(s)) { //空鍵
            return 0;
        }
        if (Key.androidKeys.contains(s)) { //字母數字
            return Key.androidKeys.indexOf(s);
        }
        if (symbolAliases.containsKey(s)) {
            return symbolAliases.get(s);
        }
        if (Key.getSymbols().contains(s)) { //可見符號
            return Key.getSymbolStart() + Key.getSymbols().indexOf(s);
        }

        return -1;
    }*/
    // 在类级别定义一个静态缓存
    private static final Map<String, Integer> CLICK_CODE_CACHE = new HashMap<>();

    static {
        // 1. 初始化 androidKeys (假设 Key.androidKeys 是 List<String>)
        for (int i = 0; i < Key.androidKeys.size(); i++) {
            CLICK_CODE_CACHE.put(Key.androidKeys.get(i), i);
        }

        // 2. 初始化 symbolAliases (假设它是一个已存在的 Map)
        //CLICK_CODE_CACHE.putAll(symbolAliases);

        // 3. 初始化 Symbols
        /*String symbols = Key.getSymbols();
        int start = Key.getSymbolStart();
        for (int i = 0; i < symbols.length(); i++) {
            // 1. 获取单个字符
            char c = symbols.charAt(i);
            // 2. 转换为 String 作为 key
            String key = String.valueOf(c);

            // 只有当缓存中不存在该 key 时才放入，或者直接放入以覆盖旧优先级
            // 建议：如果 androidKeys 优先级更高，可以用 putIfAbsent
            if (!CLICK_CODE_CACHE.containsKey(key))
                CLICK_CODE_CACHE.put(key, start + i);
        }*/
    }

    public Event(String s) {
        mRaw = s;
        if (s.matches("\\{[^\\{\\}]+\\}")) { //{send|key}
            label = s.substring(1, s.length() - 1);
            int[] sends = parseSend(label); //send
            code = sends[0];
            mask = sends[1];
            if (code >= 0) return;
            s = label; //key
            label = null;
        }
        LuaValue m = Key.presetKeys.get(s);
        if (!m.isnil()) {
            command = m.get("command").optjstring("");
            option = m.get("option").optjstring("");
            select = m.get("select").optjstring("");
            toggle = m.get("toggle").optjstring("");
            label = m.get("label").optjstring("");
            preview = m.get("preview").optjstring("");
            description = m.get("description").optjstring("");
            shiftLock = m.get("shift_lock").optjstring("");
            commit = m.get("commit").optjstring("");
            String send = m.get("send").optjstring("");
            if (TextUtils.isEmpty(send) && !TextUtils.isEmpty(command))
                send = "function"; //command默認發function
            int[] sends = parseSend(send);
            code = sends[0];
            mask = sends[1];
            parseLabel();
            text = m.get("text").optjstring("");
            if (code < 0 && TextUtils.isEmpty(text)){
                if(TextUtils.isEmpty(send))
                    text=s;
                else
                    text = send;
            }
            LuaValue st = m.get("states");
            if (st.istable()) {
                states = st.checktable().stringValues();
            }
            sticky = m.get("sticky").optboolean(false);
            repeatable = m.get("repeatable").optboolean(false);
            functional = m.get("functional").optboolean(true);
        } else if ((code = getClickCode(s)) >= 0) {
            if (getRimeCode(code)==RimeKeyMap.RimeKey_VoidSymbol)
                text = s;
            parseLabel();
        } else if (s.endsWith(".lua")) {
            String send = "function";
            int[] sends = parseSend(send);
            code = sends[0];
            mask = sends[1];
            command = s;
            s = new File(s).getName();
            label = s.substring(0, s.length() - 4);
            option = "";
        } else {
            text = s;
            label = s.replaceAll("\\{[^\\{\\}]+?\\}", "");
        }
    }

    public Event(LuaValue m) {
        command = m.get("command").optjstring("");
        index = m.get("index").optint(0);
        option = m.get("option").optjstring("");
        select = m.get("select").optjstring("");
        toggle = m.get("toggle").optjstring("");
        label = m.get("label").optjstring("");
        preview = m.get("preview").optjstring("");
        description = m.get("description").optjstring("");
        shiftLock = m.get("shift_lock").optjstring("");
        commit = m.get("commit").optjstring("");
        String send = m.get("send").optjstring("");

        if (TextUtils.isEmpty(send) && !TextUtils.isEmpty(command))
            send = "function"; // command默认发function

        int[] sends = parseSend(send);
        code = sends[0];
        mask = sends[1];
        parseLabel();

        text = m.get("text").optjstring("");
        LuaValue st = m.get("states");
        if (st.istable()) {
            states = st.checktable().stringValues();
        }
        sticky = m.get("sticky").optboolean(false);
        repeatable = m.get("repeatable").optboolean(false);
        functional = m.get("functional").optboolean(true);
    }

    public static int[] getRimeEvent(int code, int mask) {
        int i = getRimeCode(code);
        int m = 0;
        if (hasModifier(mask, KeyEvent.META_SHIFT_ON)) m |= Rime.META_SHIFT_ON;
        if (hasModifier(mask, KeyEvent.META_CTRL_ON)) m |= Rime.META_CTRL_ON;
        if (hasModifier(mask, KeyEvent.META_ALT_ON)) m |= Rime.META_ALT_ON;
        if (mask == Rime.META_RELEASE_ON) m |= Rime.META_RELEASE_ON;
        return new int[]{i, m};
    }

    private static int getRimeCode(int code) {
        return RimeKeyMap.keyCodeToVal(code);
    }

    public int getCode() {
        return code;
    }

    public int getIndex() {
        return index;
    }

    public int getMask() {
        return mask;
    }

    public String getCommand() {
        return command;
    }

    public String getOption() {
        return option;
    }

    public String getSelect() {
        return select;
    }

    public boolean isFunctional() {
        return functional;
    }

    public boolean isRepeatable() {
        return repeatable;
    }

    public boolean isSticky() {
        return sticky;
    }

    public String getShiftLock() {
        return shiftLock;
    }


    private String adjustCase(String s) {
        if (TextUtils.isEmpty(s)) return "";
        if (s.length() == 1 && ModifierState.isShifted())
            s = s.toUpperCase(Locale.getDefault());
        //else if (s.length() == 1
        //        //&& mKeyboardView != null
        //        && !Rime.isAsciiMode()
        //        //&& mKeyboardView.isLabelUppercase()
        //) s = s.toUpperCase(Locale.getDefault());
        return s;
    }

    public String getLabel() {
        if (!TextUtils.isEmpty(toggle)&&states!=null) return states.get(Rime.getRimeOption(toggle) ? 1 : 0);
        return adjustCase(label);
    }

    public String getUnToggleLabel() {
        if (!TextUtils.isEmpty(toggle)) return states.get(Rime.getRimeOption(toggle) ? 0 : 1);
        return null;
    }

    public String getText() {
        String s = "";
        if (!TextUtils.isEmpty(text)) s = text;
        else if (ModifierState.isShifted()
                && mask == 0
                && code >= KeyEvent.KEYCODE_A
                && code <= KeyEvent.KEYCODE_Z) s = label;
        return adjustCase(s);
    }

    public String getCommit() {
        return commit;
    }

    public String getPreviewText() {
        if (!TextUtils.isEmpty(preview)) return preview;
        return getLabel();
    }

    public String getToggle() {
        if (!TextUtils.isEmpty(toggle)) return toggle;
        return "ascii_mode";
    }

    private void parseLabel() {
        if (!TextUtils.isEmpty(label)) return;
        int c = code;
        if (c > 0)
            label = getDisplayLabel(c);
        //if (c == KeyEvent.KEYCODE_SPACE) {
        //    label = Rime.getRimeStatus().getSchemaName();
        //    if(TextUtils.isEmpty(label))
        //        label="空格";
        //} else {
        //    if (c > 0)
        //        label = getDisplayLabel(c);
        //}
    }

    public int getRimeCode() {
        return RimeKeyMap.keyCodeToVal(code);
    }

    public String getDescription() {
        if (!TextUtils.isEmpty(description))
            return description;
        if (!TextUtils.isEmpty(toggle)) {
            boolean t = Rime.getRimeOption(toggle);
            return "当前为" + states.get(t ? 1 : 0) + ",切换到" + states.get(t ? 0 : 1);
        }
        return adjustCase(label);
    }

    public String getRawText() {
        return mRaw;
    }

    public void setCommit(String s) {
        commit = s;
    }

    public boolean isToggle() {
        return !TextUtils.isEmpty(toggle);
    }

    public String toString() {
        return TAG+":{label:"+getLabel()+",raw:"+mRaw+"}";
    }
}

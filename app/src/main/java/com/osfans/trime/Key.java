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
import android.view.KeyCharacterMap;
import android.view.KeyEvent;

import com.osfans.trime.core.Rime;
import com.osfans.trime.enums.KeyEventType;
import com.osfans.trime.keyboard.KeyboardView;
import com.osfans.trime.keyboard.ModifierState;
import com.osfans.trime.theme.ThemeManager;

import org.luaj.LuaValue;
import org.luaj.Varargs;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;

/**
 * {@link KeyboardView 鍵盤}中的各個按鍵，包含單擊、長按、滑動等多種{@link Event 事件}
 */
public class Key {
    public static final int[] KEY_STATE_NORMAL_ON = {
            android.R.attr.state_checkable, android.R.attr.state_checked
    };
    public static final int[] KEY_STATE_PRESSED_ON = {
            android.R.attr.state_pressed, android.R.attr.state_checkable, android.R.attr.state_checked
    };
    public static final int[] KEY_STATE_NORMAL_OFF = {android.R.attr.state_checkable};
    public static final int[] KEY_STATE_PRESSED_OFF = {
            android.R.attr.state_pressed, android.R.attr.state_checkable
    };
    public static final int[] KEY_STATE_NORMAL = {};
    public static final int[] KEY_STATE_PRESSED = {android.R.attr.state_pressed};
    public static final int[][] KEY_STATES =
            new int[][]{
                    KEY_STATE_PRESSED_ON,
                    KEY_STATE_PRESSED_OFF,
                    KEY_STATE_NORMAL_ON,
                    KEY_STATE_NORMAL_OFF,
                    KEY_STATE_PRESSED,
                    KEY_STATE_NORMAL
            };
    public static final String[] RIME_KEY_NAMES = {
            "VoidSymbol", "SOFT_LEFT", "SOFT_RIGHT", "HOME", "BACK", "CALL", "ENDCALL",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "asterisk", "numbersign", "Up", "Down", "Left", "Right", "KP_Begin",
            "VOLUME_UP", "VOLUME_DOWN", "POWER", "CAMERA", "Clear",
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            "comma", "period", "Alt_L", "Alt_R", "Shift_L", "Shift_R", "Tab", "space",
            "SYM", "EXPLORER", "ENVELOPE", "Return", "BackSpace",
            "grave", "minus", "equal", "bracketleft", "bracketright", "backslash", "semicolon", "apostrophe", "slash", "at",
            "NUM", "HEADSETHOOK", "FOCUS", "plus", "Menu", "NOTIFICATION", "Find",
            "MEDIA_PLAY_PAUSE", "MEDIA_STOP", "MEDIA_NEXT", "MEDIA_PREVIOUS", "MEDIA_REWIND", "MEDIA_FAST_FORWARD", "MUTE",
            "Page_Up", "Page_Down", "PICTSYMBOLS", "Mode_switch",
            "BUTTON_A", "BUTTON_B", "BUTTON_C", "BUTTON_X", "BUTTON_Y", "BUTTON_Z",
            "BUTTON_L1", "BUTTON_R1", "BUTTON_L2", "BUTTON_R2",
            "BUTTON_THUMBL", "BUTTON_THUMBR", "BUTTON_START", "BUTTON_SELECT", "BUTTON_MODE",
            "Escape", "Delete", "Control_L", "Control_R", "Caps_Lock", "Scroll_Lock", "Meta_L", "Meta_R",
            "function", "Sys_Req", "Pause", "Home", "End", "Insert", "Next",
            "MEDIA_PLAY", "MEDIA_PAUSE", "MEDIA_CLOSE", "MEDIA_EJECT", "MEDIA_RECORD",
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
            "Num_Lock", "KP_0", "KP_1", "KP_2", "KP_3", "KP_4", "KP_5", "KP_6", "KP_7", "KP_8", "KP_9",
            "KP_Divide", "KP_Multiply", "KP_Subtract", "KP_Add", "KP_Decimal", "KP_Separator", "KP_Enter", "KP_Equal",
            "parenleft", "parenright",
            "VOLUME_MUTE", "INFO", "CHANNEL_UP", "CHANNEL_DOWN", "ZOOM_IN", "ZOOM_OUT",
            "TV", "WINDOW", "GUIDE", "DVR", "BOOKMARK", "CAPTIONS", "SETTINGS",
            "TV_POWER", "TV_INPUT", "STB_POWER", "STB_INPUT", "AVR_POWER", "AVR_INPUT",
            "PROG_RED", "PROG_GREEN", "PROG_YELLOW", "PROG_BLUE", "APP_SWITCH",
            "BUTTON_1", "BUTTON_2", "BUTTON_3", "BUTTON_4", "BUTTON_5", "BUTTON_6", "BUTTON_7", "BUTTON_8",
            "BUTTON_9", "BUTTON_10", "BUTTON_11", "BUTTON_12", "BUTTON_13", "BUTTON_14", "BUTTON_15", "BUTTON_16",
            "LANGUAGE_SWITCH", "MANNER_MODE", "3D_MODE", "CONTACTS", "CALENDAR", "MUSIC", "CALCULATOR",
            "Zenkaku_Hankaku", "Eisu_toggle", "Muhenkan", "Henkan", "Hiragana_Katakana", "yen", "RO", "Kana_Lock",
            "ASSIST", "BRIGHTNESS_DOWN", "BRIGHTNESS_UP", "MEDIA_AUDIO_TRACK",
            "SLEEP", "WAKEUP", "PAIRING", "MEDIA_TOP_MENU", "11", "12", "LAST_CHANNEL", "TV_DATA_SERVICE", "VOICE_ASSIST",
            "TV_RADIO_SERVICE", "TV_TELETEXT", "TV_NUMBER_ENTRY", "TV_TERRESTRIAL_ANALOG", "TV_TERRESTRIAL_DIGITAL",
            "TV_SATELLITE", "TV_SATELLITE_BS", "TV_SATELLITE_CS", "TV_SATELLITE_SERVICE", "TV_NETWORK", "TV_ANTENNA_CABLE",
            "TV_INPUT_HDMI_1", "TV_INPUT_HDMI_2", "TV_INPUT_HDMI_3", "TV_INPUT_HDMI_4",
            "TV_INPUT_COMPOSITE_1", "TV_INPUT_COMPOSITE_2", "TV_INPUT_COMPONENT_1", "TV_INPUT_COMPONENT_2", "TV_INPUT_VGA_1",
            "TV_AUDIO_DESCRIPTION", "TV_AUDIO_DESCRIPTION_MIX_UP", "TV_AUDIO_DESCRIPTION_MIX_DOWN",
            "TV_ZOOM_MODE", "TV_CONTENTS_MENU", "TV_MEDIA_CONTEXT_MENU", "TV_TIMER_PROGRAMMING",
            "Help", "NAVIGATE_PREVIOUS", "NAVIGATE_NEXT", "NAVIGATE_IN", "NAVIGATE_OUT",
            "STEM_PRIMARY", "STEM_1", "STEM_2", "STEM_3",
            "Pointer_UpLeft", "Pointer_DownLeft", "Pointer_UpRight", "Pointer_DownRight",
            "MEDIA_SKIP_FORWARD", "MEDIA_SKIP_BACKWARD", "MEDIA_STEP_FORWARD", "MEDIA_STEP_BACKWARD",
            "SOFT_SLEEP", "CUT", "COPY", "PASTE",
            "SYSTEM_NAVIGATION_UP", "SYSTEM_NAVIGATION_DOWN", "SYSTEM_NAVIGATION_LEFT", "SYSTEM_NAVIGATION_RIGHT",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
            "exclam", "quotedbl", "dollar", "percent", "ampersand", "colon", "less", "greater", "question", "asciicircum", "underscore", "braceleft", "bar", "braceright", "asciitilde"
    };
    public static List<String> androidKeys = Arrays.asList(RIME_KEY_NAMES);
    public static LuaValue presetKeys = ThemeManager.getPresetKeys();
    private static final int EVENT_NUM = KeyEventType.values().length;
    private boolean mComposingKey;
    private List popupKeys;
    private boolean speak_key_label;
    public Event[] events = new Event[EVENT_NUM];
    public String[] hints = new String[EVENT_NUM];
    public int edgeFlags;
    private static int symbolStart = androidKeys.contains("A") ? Key.androidKeys.indexOf("A") : 284;
    private static String symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZ~!@#$%^&*()_+[]\\{}|;':\",./<>?";
    private static KeyCharacterMap kcm = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD);
    private Event ascii;
    private Event composing;
    private Event has_menu;
    private Event paging;
    private boolean send_bindings = true;
    private int width;
    private int height;
    private int gap;
    private int row;
    private int column;
    private String label;
    private String hint;
    private String description;
    private int x;
    private int y;
    private boolean pressed;
    private boolean on;
    private String popupCharacters;
    private int popupResId;
    private HashMap<String, Event> mSwipeTapKeys = new HashMap<>();
    private boolean mAbsolute;
    private String mStyle = "";
    private boolean mHasSwipeEvent;
    private Key mAsciiKey;
    private boolean mSwipeRepeatable;
    private boolean mAsciiMode;


    /**
     * Create an empty key with no attributes.
     *
     * @param parent 按鍵所在的{@link KeyboardView 鍵盤}
     */

    /**
     * Create an empty key with no attributes.
     *
     * @param mk 從YAML中解析得到的Map
     */
    public Key(LuaValue mk) {
        String s;
        String[] eventTypes =
                new String[]{
                        "click", "long_click", "swipe_left", "swipe_right", "swipe_up", "swipe_down", "combo"
                };
        String[] hintTypes =
                new String[]{
                        "hint", "hint_long", "hint_left", "hint_right", "hint_up", "hint_down", "combo"
                };
        for (int i = 0; i < EVENT_NUM; i++) {
            String hintType = hintTypes[i];
            LuaValue h = mk.get(hintType);
            if (h.isstring()) {
                hints[i] = h.tojstring();
            }
            String eventType = eventTypes[i];
            //s = mk.get(eventType).optjstring("");
            LuaValue o = mk.get(eventType);
            if (i >= 2 && !mHasSwipeEvent && !o.isnil()) {
                mHasSwipeEvent = true;
            }
            if (o != null && o.istable()) {
                events[i] = new Event(o);
            } else if (o != null && o.isstring()) {
                s = o.toString();
                events[i] = new Event(s);
            } else if (i == KeyEventType.CLICK.ordinal()) {
                if (!mk.get("commit").isnil())
                    events[i] = new Event(mk);
                else
                    events[i] = new Event("");
            }
            /*if (!TextUtils.isEmpty(s))
                events[i] = new Event(s);
            else if (i == KeyEventType.CLICK.ordinal())
                events[i] = new Event("");*/
        }
        s = mk.get("composing").optjstring("");
        if (!TextUtils.isEmpty(s)) composing = new Event(s);

        s = mk.get("has_menu").optjstring("");
        if (!TextUtils.isEmpty(s)) has_menu = new Event(s);

        s = mk.get("paging").optjstring("");
        if (!TextUtils.isEmpty(s)) paging = new Event(s);

        if (composing != null || has_menu != null || paging != null) {
            mComposingKey = true;
        }

        LuaValue a = mk.get("ascii");
        if (a.isstring()) {
            ascii = new Event(a.tojstring());
        } else if (a.istable()) {
            if (!a.get("click").isnil()) {
                mAsciiKey = new Key(a);
                mAsciiKey.setAsciiMode(true);
            } else {
                ascii = new Event(a);
            }
        }
        mStyle = mk.get("style").optjstring(mk.get("click").optjstring("key"));
        label = mk.get("label").optjstring("");
        hint = mk.get("hint").optjstring("");
        description = mk.get("description").optjstring("");
        mSwipeRepeatable = mk.get("swipe_repeatable").toboolean();
        // send_bindings 逻辑转换
        if (!mk.get("send_bindings").isnil()) {
            send_bindings = mk.get("send_bindings").optboolean(false);
        } else if (composing == null && has_menu == null && paging == null) {
            send_bindings = false;
        }


        int c = getCode();
        String l = getLabel();

        speak_key_label = Config.isSpeakKeyLabel();
        LuaValue obj = mk.get("popup");
        if (!obj.isnil()) {

            if (obj.istable()) {
                popupKeys = (List) obj.checktable().stringValues();
                if (TrimeService.getInstance().isLongPressPopup()) {
                    String ll = getLabel();
                    if (ll.length() == 1 && Character.isLetter(ll.charAt(0))) {
                        if (getX() < getWidth()) {
                            popupKeys.add(ll.toUpperCase());
                        } else {
                            popupKeys.add(0, ll.toUpperCase());
                        }
                        if (getX() > TrimeService.getInstance().getWidth() - getWidth() * 1.5) {
                            popupKeys.add(1, ll.toLowerCase());
                        } else {
                            popupKeys.add(ll.toLowerCase());
                        }
                    }
                }
            } else {
                popupCharacters = obj.toString();
            }
            if (TrimeService.getInstance().isLongPressPopup())
                popupResId = 1;
            else
                popupResId = 2;
        } else if (getLongClick() != null && getLongClick().getCode() != KeyEvent.KEYCODE_VOICE_ASSIST && !TextUtils.isEmpty(getLongClick().getRawText())) {
            if (TrimeService.getInstance().isLongPressPopup())
                popupResId = 1;
        }


        if (TrimeService.getInstance().isKeySwipeTap()) {
            LuaValue swipe = mk.get("swipe");
            if (swipe.istable()) {
                LuaValue k = LuaValue.NIL;
                while (true) {
                    Varargs n = swipe.next(k);
                    if ((k = n.arg1()).isnil())
                        break;
                    mSwipeTapKeys.put(k.optjstring(""), new Event(n.arg(2).optjstring("")));
                }
            }
        }

    }

    private void setAsciiMode(boolean b) {
        mAsciiMode = b;
    }

    public Key(String s) {
        events[0] = new Event(s);
        if (s.length() == 1 && Character.isLetter(s.charAt(0)))
            events[0].setCommit(s);
    }

    public Key(Event e) {
        events[0] = e;
    }

    public boolean isComposingKey() {
        return mComposingKey;
    }

    public static List<String> getAndroidKeys() {
        return androidKeys;
    }

    public static LuaValue getPresetKeys() {
        return presetKeys;
    }

    public static int getSymbolStart() {
        return symbolStart;
    }

    public static void setSymbolStart(int symbolStart) {
        Key.symbolStart = symbolStart;
    }

    public static String getSymbols() {
        return symbols;
    }

    public static void setSymbols(String symbols) {
        Key.symbols = symbols;
    }

    public static KeyCharacterMap getKcm() {
        return kcm;
    }

    public static boolean isNumOrAlpha(int keyCode) {
        return (keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9) || (keyCode >= KeyEvent.KEYCODE_A && keyCode <= KeyEvent.KEYCODE_Z);
    }

    public int getWidth() {
        return width;
    }

    public void setWidth(int width) {
        this.width = width;
    }

    public int getHeight() {
        return height;
    }

    public void setHeight(int height) {
        this.height = height;
    }

    public int getGap() {
        return gap;
    }

    public void setGap(int gap) {
        this.gap = gap;
    }

    public int getEdgeFlags() {
        return edgeFlags;
    }

    public void setEdgeFlags(int edgeFlags) {
        this.edgeFlags = edgeFlags;
    }

    public int getRow() {
        return row;
    }

    public void setRow(int row) {
        this.row = row;
    }

    public int getColumn() {
        return column;
    }

    public void setColumn(int column) {
        this.column = column;
    }

    public String getHint() {
        Event event = getEvent();
        if (!TextUtils.isEmpty(hint) && event == getClick() && (ascii == null && !Rime.isAsciiMode()))
            return hint; //中文狀態顯示標籤
        /*String h = event.getUnToggleLabel();
        if(!TextUtils.isEmpty(h))
            return h;*/
        return hint;
    }

    public int getX() {
        return x;
    }

    public void setX(int x) {
        this.x = x;
    }

    public int getY() {
        return y;
    }

    public void setY(int y) {
        this.y = y;
    }

    public boolean isPressed() {
        return pressed;
    }

    public boolean isOn() {
        return on;
    }

    public void setOn(boolean on) {
        this.on = on;
    }

    public String getPopupCharacters() {
        return popupCharacters;
    }

    public List<String> getPopupKeys() {
        if (popupKeys == null && popupResId == 1) {
            popupKeys = new ArrayList();
            if (popupCharacters != null) {
                for (int i = 0; i < popupCharacters.length(); i++) {
                    popupKeys.add(String.valueOf(popupCharacters.charAt(i)));
                }
            } else {
                popupKeys.add(getLongClick().getRawText());
            }
            String ll = getLabel();
            if (ll.length() == 1 && Character.isLetter(ll.charAt(0))) {
                if (getX() < getWidth()) {
                    popupKeys.add(ll.toUpperCase());
                } else {
                    popupKeys.add(0, ll.toUpperCase());
                }
                if (getX() > TrimeService.getInstance().getWidth() - getWidth() * 1.5) {
                    popupKeys.add(1, ll.toLowerCase());
                } else {
                    popupKeys.add(ll.toLowerCase());
                }
            }
            popupResId = 1;
        }
        return popupKeys;
    }

    public int getPopupResId() {
        return popupResId;
    }

    public boolean isNormal(int[] drawableState) {
        return (drawableState == KEY_STATE_NORMAL
                || drawableState == KEY_STATE_NORMAL_ON
                || drawableState == KEY_STATE_NORMAL_OFF);
    }

    /**
     * Informs the key that it has been pressed, in case it needs to change its appearance or state.
     *
     * @see #onReleased(boolean)
     */
    public void onPressed() {
        pressed = !pressed;
    }

    /**
     * Changes the pressed state of the key. If it is a sticky key, it will also change the toggled
     * state of the key if the finger was release inside.
     *
     * @param inside whether the finger was released inside the key
     * @see #onPressed()
     */
    public void onReleased(boolean inside) {
        pressed = !pressed;
        if (getClick().isSticky()) on = !on;
    }

    /**
     * Detects if a point falls inside this key.
     *
     * @param x the x-coordinate of the point
     * @param y the y-coordinate of the point
     * @return whether or not the point falls inside the key. If the key is attached to an edge, it
     * will assume that all points between the key and the edge are considered to be inside the
     * key.
     */
    /*public boolean isInside(int x, int y) {
        boolean leftEdge = (edgeFlags & KeyboardView.EDGE_LEFT) > 0;
        boolean rightEdge = (edgeFlags & KeyboardView.EDGE_RIGHT) > 0;
        boolean topEdge = (edgeFlags & KeyboardView.EDGE_TOP) > 0;
        boolean bottomEdge = (edgeFlags & KeyboardView.EDGE_BOTTOM) > 0;
        if ((x >= this.x || (leftEdge && x <= this.x + this.width))
                && (x < this.x + this.width || (rightEdge && x >= this.x))
                && (y >= this.y || (topEdge && y <= this.y + this.height))
                && (y < this.y + this.height || (bottomEdge && y >= this.y))) {
            if (mAbsolute && key_back_color instanceof LuaBitmapDrawable) {
                return ((LuaBitmapDrawable) key_back_color).isInside(x - this.x, y - this.y);
            }
            return true;
        } else {
            return false;
        }
    }
    */

    /**
     * Returns the square of the distance between the center of the key and the given point.
     *
     * @param x the x-coordinate of the point
     * @param y the y-coordinate of the point
     * @return the square of the distance of the point from the center of the key
     */
    public int squaredDistanceFrom(int x, int y) {
        int xDist = this.x + width / 2 - x;
        int yDist = this.y + height / 2 - y;
        return xDist * xDist + yDist * yDist;
    }

    /**
     * Returns the drawable state for the key, based on the current state and type of the key.
     *
     * @return the drawable state of the key.
     * @see android.graphics.drawable.StateListDrawable#setState(int[])
     */
    public int[] getCurrentDrawableState() {
        int[] states = KEY_STATE_NORMAL;
        boolean isShifted = isShift() && ModifierState.isShifted(); //臨時大寫
        if (isShifted || on) {
            if (pressed) {
                states = KEY_STATE_PRESSED_ON;
            } else {
                states = KEY_STATE_NORMAL_ON;
            }
        } else {
            if (getClick().isSticky() || getClick().isFunctional()) {
                if (pressed) {
                    states = KEY_STATE_PRESSED_OFF;
                } else {
                    states = KEY_STATE_NORMAL_OFF;
                }
            } else {
                if (pressed) {
                    states = KEY_STATE_PRESSED;
                }
            }
        }
        return states;
    }

    public boolean isShift() {
        int c = getEvent().getCode();
        return (c == KeyEvent.KEYCODE_SHIFT_LEFT || c == KeyEvent.KEYCODE_SHIFT_RIGHT);
    }

    public boolean isShiftLock() {
        switch (getClick().getShiftLock()) {
            case "long":
                return false;
            case "click":
                return true;
        }
        return !Rime.isAsciiMode();
    }

    public boolean sendBindings(int type) {
        Event e = null;
        if (type > 0 && type <= EVENT_NUM) e = events[type];
        if (e != null) return true;
        if (ascii != null && Rime.isAsciiMode()) return false;
        if (send_bindings) {
            if (paging != null && Rime.isPaging()) return true;
            if (has_menu != null && Rime.hasMenu()) return true;
            if (composing != null && Rime.getRimeStatus().isComposing()) return true;
        }
        return false;
    }

    public Event getEvent() {
        if (ascii != null && Rime.isAsciiMode()) return ascii;
        if (paging != null && Rime.isPaging()) return paging;
        if (has_menu != null && Rime.hasMenu()) return has_menu;
        if (composing != null && Rime.getRimeStatus().isComposing()) return composing;
        return getClick();
    }

    public Event getClick() {
        return events[KeyEventType.CLICK.ordinal()];
    }

    public Event getLongClick() {
        return events[KeyEventType.LONG_CLICK.ordinal()];
    }

    public boolean hasEvent(int i) {
        return events[i] != null;
    }

    public Event getEvent(int i) {
        Event e = null;
        if (i > 0 && i <= EVENT_NUM) e = events[i];
        if (e != null) return e;
        if (i != 0)
            return null;
        if (ascii != null && Rime.isAsciiMode()) return ascii;
        if (send_bindings) {
            if (paging != null && Rime.isPaging()) return paging;
            if (has_menu != null && Rime.hasMenu()) return has_menu;
            if (composing != null && Rime.isComposing()) return composing;
        }
        return getClick();
    }

    public Event getRawEvent(int i) {
        return events[i];
    }

    public int getCode() {
        return getClick().getCode();
    }

    public int getCode(int type) {
        return getEvent(type).getCode();
    }

    public String getLabel() {
        Event event = getEvent();
        if (event == getClick() /*&& (ascii == null || !Rime.isAsciiMode())*/) {
            if (event.getCode() == KeyEvent.KEYCODE_ENTER && !Rime.isComposing() && "action_labels".equals(event.getLabel())) {
                TrimeService trime = TrimeService.getInstance();
                if (trime != null) {
                    String action = trime.getActionLabel();
                    if (!TextUtils.isEmpty(action))
                        return action;
                }
            }
            if (Rime.isAsciiMode() && !mAsciiMode)
                return event.getLabel();
            if (event.getCode() == KeyEvent.KEYCODE_SPACE) {
                if (!Rime.isAsciiMode()) {
                    if (TextUtils.isEmpty(event.getLabel()) || "space".equals(event.getLabel()) || "schema_name".equals(label)) {
                        String id = Rime.getRimeStatus().getSchemaName();
                        if (!TextUtils.isEmpty(id))
                            return id;
                        else if ("schema_name".equals(label))
                            return event.getLabel();
                    }
                }
            }
            if (!TextUtils.isEmpty(label))
                return label;
        }
        return event.getLabel();
    }

    public String getDescription() {
        Event event = getEvent();
        if (event.getCode() == KeyEvent.KEYCODE_ENTER && !Rime.isComposing() && event == getClick()) {
            TrimeService trime = TrimeService.getInstance();
            if (trime != null) {
                String action = trime.getActionLabel();
                if (!TextUtils.isEmpty(action))
                    return action;
            }
        }
        if (event == getClick() && (ascii == null && !Rime.isAsciiMode())) {
            if (!TextUtils.isEmpty(description))
                return description;
            if (speak_key_label && !TextUtils.isEmpty(label))
                return label;
        }
        return event.getDescription();
    }

    public String getPreviewText(int type) {
        if (type == KeyEventType.CLICK.ordinal()) return getEvent().getPreviewText();
        return getEvent(type).getPreviewText();
    }

    public String getLongClickLabel() {
        Event event = getLongClick();
        if (event == null)
            return null;
        if (hints[1] != null)
            return hints[1];
        return event.getLabel();
    }

    @Override
    public String toString() {
        StringBuilder buf = new StringBuilder();
        buf.append("Key:{")
                .append("label:")
                .append(getLabel())
                .append(",")
                .append("code:")
                .append(getCode())
                .append(",")
                .append("long_click:")
                .append(getLongClick())
                .append(",")
                .append("ascii:")
                .append(ascii)
                .append(",")
                .append(" ")
                .append(getX())
                .append(",")
                .append(getY())
                .append("-")
                .append(getWidth())
                .append(",")
                .append(getHeight())
        ;
        return buf.toString();
    }

    public Event getSwipeTapKeys(String s) {
        return mSwipeTapKeys.get(s);
    }

    public boolean hasSwipeTapKeys() {
        return !mSwipeTapKeys.isEmpty();
    }

    public void setAbsolute(boolean b) {
        mAbsolute = b;
    }

    public boolean isAbsolute() {
        return mAbsolute;
    }

    public String getStyle() {
        return mStyle;
    }

    public boolean hasSwipeEvent() {
        return mHasSwipeEvent;
    }

    public String getHint(int swipe) {
        String h = hints[swipe];
        if (h != null)
            return h;
        Event ev = events[swipe];
        if (ev != null)
            return ev.getLabel();
        return null;
    }

    public Key getAsciiKey() {
        return mAsciiKey;
    }

    public boolean isSwipeRepeatable() {
        return mSwipeRepeatable;
    }
}

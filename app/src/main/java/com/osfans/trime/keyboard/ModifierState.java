/*
 * SPDX-FileCopyrightText: 2015 - 2026 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.keyboard;

import com.osfans.trime.util.Function;

public class ModifierState {
private static boolean shift=false;

    public static boolean isShifted() {
        return shift;
    }

    public static void setShifted(boolean shift) {
        ModifierState.shift = shift;
    }
    private static boolean shiftLock=false;

    public static boolean isShiftLock() {
        return shiftLock;
    }

    public static void setShiftLock(boolean shiftLock) {
        ModifierState.shiftLock = shiftLock;
    }

    private static boolean ctrl=false;

    public static boolean isCtrl() {
        return ctrl;
    }

    public static void setCtrl(boolean ctrl) {
        ModifierState.ctrl = ctrl;
    }

    private static boolean alt=false;
    public static boolean isAlt() {
        return alt;
    }

    public static void setAlt(boolean alt) {
        ModifierState.alt = alt;
    }


}

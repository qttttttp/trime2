package com.osfans.trime.core;

import android.view.KeyEvent;

/**
 * 键位修饰符的集合，作为 KeyModifier 位掩码的包装类。
 * 对应于 Kotlin 的 @JvmInline value class KeyModifiers。
 */
public final class KeyModifiers {
    public final int modifiers;

    // --- Constructors ---

    public KeyModifiers(int modifiers) {
        this.modifiers = modifiers;
    }

    /**
     * 对应 Kotlin 的 vararg 构造函数：constructor(vararg modifiers: KeyModifier)
     */
    public KeyModifiers(KeyModifier... modifiers) {
        this(mergeModifiers(modifiers));
    }

    // --- 核心逻辑 ---

    /**
     * 检查是否包含某个修饰符。
     * 对应 Kotlin 的 fun has(modifier: KeyModifier)
     */
    public boolean has(KeyModifier modifier) {
        return (this.modifiers & modifier.getModifier()) != 0;
    }

    // --- Getter 属性 (对应 Kotlin val properties) ---

    public boolean isAlt() {
        return has(KeyModifier.Alt);
    }

    public boolean isCtrl() {
        return has(KeyModifier.Control);
    }

    public boolean isShift() {
        return has(KeyModifier.Shift);
    }

    public boolean isMeta() {
        return has(KeyModifier.Meta);
    }

    public boolean isNumLock() {
        return has(KeyModifier.Mod2);
    }

    public boolean isCapsLock() {
        return has(KeyModifier.Lock);
    }

    public boolean isRelease() {
        return has(KeyModifier.Release);
    }

    /**
     * 将内部修饰符状态转换为标准的 Android KeyEvent.META_* 状态码。
     * 对应 Kotlin 的 val metaState: Int get()
     */
    public int getMetaState() {
        int metaState = 0;
        // 注意：在 Java 中，使用 |= 进行位或操作
        if (isAlt()) metaState |= KeyEvent.META_ALT_ON | KeyEvent.META_ALT_LEFT_ON;
        if (isCtrl()) metaState |= KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON;
        if (isShift()) metaState |= KeyEvent.META_SHIFT_ON | KeyEvent.META_SHIFT_LEFT_ON;
        if (isMeta()) metaState |= KeyEvent.META_META_ON | KeyEvent.META_META_LEFT_ON;
        if (isNumLock()) metaState |= KeyEvent.META_NUM_LOCK_ON;
        if (isCapsLock()) metaState |= KeyEvent.META_CAPS_LOCK_ON;
        return metaState;
    }

    /**
     * 获取原始的修饰符整数值。
     * 对应 Kotlin 的 fun toInt()
     */
    public int toInt() {
        return modifiers;
    }

    // --- 静态方法/常量 (对应 Kotlin Companion Object) ---

    public static final KeyModifiers Empty = new KeyModifiers(0);
    public static final KeyModifiers Release = new KeyModifiers(KeyModifier.Release);

    /**
     * 对应 Kotlin 的 fun of(v: Int)
     */
    public static KeyModifiers of(int v) {
        return new KeyModifiers(v);
    }

    /**
     * 从 Android KeyEvent 对象创建 KeyModifiers 实例。
     * 对应 Kotlin 的 fun fromKeyEvent(event: KeyEvent)
     */
    public static KeyModifiers fromKeyEvent(KeyEvent event) {
        int states = KeyModifier.None.getModifier();

        // 对应 Kotlin 中对 event 的 apply 块
        if (event.isAltPressed()) states = KeyModifier.add(states, KeyModifier.Alt);
        if (event.isCtrlPressed()) states = KeyModifier.add(states, KeyModifier.Control);
        if (event.isShiftPressed()) states = KeyModifier.add(states, KeyModifier.Shift);
        if (event.isCapsLockOn()) states = KeyModifier.add(states, KeyModifier.Lock);
        if (event.isNumLockOn()) states = KeyModifier.add(states, KeyModifier.Mod2);
        if (event.isMetaPressed()) states = KeyModifier.add(states, KeyModifier.Meta);
        if (event.getAction() == KeyEvent.ACTION_UP) states = KeyModifier.add(states, KeyModifier.Release);

        return new KeyModifiers(states);
    }

    /**
     * Helper：检查位掩码中是否设置了某个标志。
     * 替换 Kotlin 的 hasFlag 库调用。
     */
    private static boolean hasFlag(int state, int flag) {
        return (state & flag) != 0;
    }

    /**
     * 从 Android MetaState (KeyEvent.META_*) 整数创建 KeyModifiers 实例。
     * 对应 Kotlin 的 fun fromMetaState(metaState: Int)
     */
    public static KeyModifiers fromMetaState(int metaState) {
        int states = KeyModifier.None.getModifier();

        // 检查并添加对应的修饰符
        if (hasFlag(metaState, KeyEvent.META_ALT_ON)) states = KeyModifier.add(states, KeyModifier.Alt);
        if (hasFlag(metaState, KeyEvent.META_CTRL_ON)) states = KeyModifier.add(states, KeyModifier.Control);
        if (hasFlag(metaState, KeyEvent.META_SHIFT_ON)) states = KeyModifier.add(states, KeyModifier.Shift);
        if (hasFlag(metaState, KeyEvent.META_NUM_LOCK_ON)) states = KeyModifier.add(states, KeyModifier.Mod2);
        if (hasFlag(metaState, KeyEvent.META_CAPS_LOCK_ON)) states = KeyModifier.add(states, KeyModifier.Lock);
        if (hasFlag(metaState, KeyEvent.META_META_ON)) states = KeyModifier.add(states, KeyModifier.Meta);

        return new KeyModifiers(states);
    }

    /**
     * 合并一组 KeyModifier 到一个整数位掩码。
     * 对应 Kotlin 的 mergeModifiers 函数（使用 fold 实现）。
     */
    public static int mergeModifiers(KeyModifier[] arr) {
        int acc = KeyModifier.None.getModifier();
        for (KeyModifier modifier : arr) {
            acc |= modifier.getModifier();
        }
        return acc;
    }
}

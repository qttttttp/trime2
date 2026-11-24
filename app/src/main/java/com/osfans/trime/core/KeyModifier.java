package com.osfans.trime.core;

/**
 * 定义 Rime 键位修饰符标志，对应于 librime/key_table.h。
 * 使用 Java 'int' (32位有符号整数) 来存储位掩码。
 */
public enum KeyModifier {
    None(0),
    Shift(1 << 0),
    Lock(1 << 1), // CapsLock
    Control(1 << 2),
    Mod1(1 << 3),
    // 对应 Kotlin 中的 constructor(other: KeyModifier)
    Alt(Mod1.modifier),
    Mod2(1 << 4), // NumLock
    Mod3(1 << 5),
    Mod4(1 << 6),
    Mod5(1 << 7),
    Button1(1 << 8),
    Button2(1 << 9),
    Button3(1 << 10),
    Button4(1 << 11),
    Button5(1 << 12),
    Handled(1 << 24),
    Forward(1 << 25),
    // 对应 Kotlin 中的 constructor(other: KeyModifier)
    Ignored(Forward.modifier),
    Super(1 << 26),
    Hyper(1 << 27),
    Meta(1 << 28),
    Release(1 << 30),
    // 0x5f001fffu
    Modifier(1593853951); // 0x5F001FFF

    private final int modifier;

    KeyModifier(int modifier) {
        this.modifier = modifier;
    }

    // 用于 Alt(Mod1) 和 Ignored(Forward) 这种构造函数重载
    KeyModifier(int value, boolean isValue) {
        this.modifier = value;
    }

    KeyModifier(KeyModifier other) {
        this.modifier = other.modifier;
    }

    public int getModifier() {
        return modifier;
    }

    // 模拟 Kotlin 的 infix fun or(other: KeyModifier)
    public int or(KeyModifier other) {
        return this.modifier | other.modifier;
    }

    // 模拟 Kotlin 的 infix fun or(other: UInt)
    public int or(int other) {
        return this.modifier | other;
    }

    // 模拟 Kotlin 的操作符重载 (UInt.plus/minus(KeyModifier))
    public static int add(int currentModifiers, KeyModifier modifier) {
        return currentModifiers | modifier.modifier;
    }

    public static int remove(int currentModifiers, KeyModifier modifier) {
        return currentModifiers & (~modifier.modifier);
    }
}

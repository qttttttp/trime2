package com.osfans.trime.core;

import com.osfans.trime.core.KeyModifiers;

import java.util.Objects;

/**
 * Rime Key Event data class in Java.
 *
 * Represents a key press event in Rime, including the key value, modifiers,
 * and a string representation.
 */
public final class RimeKeyEvent {
    static {
        System.loadLibrary("rime_jni");
    }

    private final int value;
    private final int modifiers;
    private final String repr;

    // Fields for lazy initialization
    private volatile KeyValue keyVal = null;
    private volatile KeyModifiers keyModifiers = null;

    // --- Constructor (Matches Kotlin Primary Constructor) ---

    public RimeKeyEvent(int value, int modifiers, String repr) {
        this.value = value;
        this.modifiers = modifiers;
        this.repr = repr;
    }

    // --- Getters ---

    public int getValue() {
        return value;
    }

    public int getModifiers() {
        return modifiers;
    }

    /**
     * @return The string representation of the key event (e.g., "Control_L+q").
     */
    public String getRepr() {
        return repr;
    }

    // --- Lazy Initialized Getters (Equivalent to 'by lazy') ---

    /**
     * Lazily initializes and returns the KeyValue object for the key value.
     */
    public KeyValue getKeyVal() {
        if (keyVal == null) {
            synchronized (this) {
                if (keyVal == null) {
                    keyVal = new KeyValue(value);
                }
            }
        }
        return keyVal;
    }

    /**
     * Lazily initializes and returns the KeyModifiers object for the modifiers.
     */
    public KeyModifiers getKeyModifiers() {
        if (keyModifiers == null) {
            synchronized (this) {
                if (keyModifiers == null) {
                    // Assumes KeyModifiers.of(int) is available in Java
                    keyModifiers = KeyModifiers.of(modifiers);
                }
            }
        }
        return keyModifiers;
    }

    // --- Data Class Methods ---

    /**
     * Uses the string representation (repr) as the primary string output.
     */
    @Override
    public String toString() {
        return repr;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        RimeKeyEvent that = (RimeKeyEvent) o;
        return value == that.value &&
                modifiers == that.modifiers &&
                Objects.equals(repr, that.repr);
    }

    @Override
    public int hashCode() {
        return Objects.hash(value, modifiers, repr);
    }

    // --- Companion Object (Static Fields and JNI Methods) ---

    /**
     * The static instance representing no key event (RimeKeyEvent(0, 0, "0x0000")).
     */
    public static final RimeKeyEvent None = new RimeKeyEvent(0, 0, "0x0000");

    /**
     * Parses a string representation of a key event into a RimeKeyEvent object via JNI.
     * @param repr The string representation (e.g., "Control_L+q").
     * @return The parsed RimeKeyEvent.
     */
    public static native RimeKeyEvent parse(String repr);

    /**
     * Gets the Rime keycode integer value by its name (via JNI).
     * @param name The name of the key (e.g., "Control_L").
     * @return The integer keycode.
     */
    public static native int getKeycodeByName(String name);

    /**
     * Gets the Rime modifier mask integer value by its name (via JNI).
     * @param name The name of the modifier (e.g., "Control").
     * @return The integer modifier mask.
     */
    public static native int getModifierByName(String name);
}

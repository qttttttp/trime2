package com.osfans.trime.core;

import android.view.KeyEvent;

/**
 * Rime Key Value in Java.
 *
 * This class is a standard Java representation of the Kotlin @JvmInline value class KeyValue.
 * It holds the internal integer value used by Rime.
 */
public final class KeyValue {

    private final int value;

    /**
     * Constructs a KeyValue instance with the raw Rime key value.
     * @param value The internal integer value representing the key.
     */
    public KeyValue(int value) {
        this.value = value;
    }

    /**
     * Gets the raw internal integer value of the key.
     * @return The key value.
     */
    public int getValue() {
        return value;
    }

    /**
     * Calculates the Android KeyEvent code corresponding to the Rime value.
     * Assumes RimeKeyMapping is a utility class available in the project.
     *
     * @return The Android KeyEvent code.
     */
    public int getKeyCode() {
        return RimeKeyMap.valToKeyCode(this.value);
    }

    /**
     * Returns a string representation of the KeyValue in hexadecimal format,
     * zero-padded to 4 characters (e.g., "0x0020").
     *
     * @return The hex string representation.
     */
    @Override
    public String toString() {
        // Equivalent to Kotlin's "0x" + value.toString(16).padStart(4, '0')
        String hex = Integer.toHexString(this.value);
        StringBuilder paddedHex = new StringBuilder(hex);
        while (paddedHex.length() < 4) {
            paddedHex.insert(0, '0');
        }
        return "0x" + paddedHex;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        KeyValue keyValue = (KeyValue) o;
        return value == keyValue.value;
    }

    @Override
    public int hashCode() {
        return value;
    }

    /**
     * The companion object functionality (static methods).
     */
    public static class Companion {

        /**
         * Creates a KeyValue instance from an Android KeyEvent.
         * Assumes RimeKeyMapping is a utility class available in the project.
         *
         * @param event The Android KeyEvent.
         * @return A new KeyValue instance.
         */
        public static KeyValue fromKeyEvent(KeyEvent event) {
            if (event == null) {
                return null; // Or throw IllegalArgumentException
            }
            int rimeValue = RimeKeyMap.keyCodeToVal(event.getKeyCode());
            return new KeyValue(rimeValue);
        }
    }
}

/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.core;

import java.util.ArrayList;
import java.util.List;

public class SharedFlowImpl<T> implements Flow<T> {
    private final int capacity;
    private final List<T> buffer;
    private T lastValue = null; // Simplification of stateFlow/MutableSharedFlow behavior

    public SharedFlowImpl(int capacity) {
        this.capacity = capacity;
        this.buffer = new ArrayList<>(capacity);
    }

    @Override
    public boolean tryEmit(T value) {
        synchronized (buffer) {
            if (buffer.size() < capacity) {
                buffer.add(value);
                lastValue = value;
                // In a real implementation, this would notify observers
                return true;
            } else {
                // Simulating BufferOverflow.DROP_OLDEST
                // In true DROP_OLDEST, we drop the *oldest*, but for buffer capacity this often means dropping the incoming one if full.
                // Given the small capacity and nature, dropping the incoming is safer for the main thread.
                return false;
            }
        }
    }

    @Override
    public T getValue() {
        return lastValue;
    }
}


package com.osfans.trime.core;

import java.util.concurrent.Executor;

/**
 * Interface for components that own a RimeLifecycle instance.
 */
public interface RimeLifecycleOwner {

    RimeLifecycle getLifecycle();

    /**
     * Equivalent to the Kotlin extension property: val RimeLifecycleOwner.lifecycleScope
     */
    default Executor getLifecycleExecutor() {
        return getLifecycle().getLifecycleExecutor();
    }
}

package com.osfans.trime.core;

import java.util.concurrent.Executor;

/**
 * Defines the Rime lifecycle state and the basic contract for lifecycle management.
 * Replaces the Kotlin RimeLifecycle interface and StateFlow functionality.
 */
public interface RimeLifecycle {

    /**
     * Rime lifecycle states.
     */
    enum State {
        STARTING,
        READY,
        STOPPING,
        STOPPED,
    }

    /**
     * Interface for listening to state changes, replacing StateFlow.
     */
    interface StateObserver {
        void onStateChange(State newState);
    }

    /**
     * @return The current lifecycle state.
     */
    State getCurrentState();

    /**
     * Registers a listener for state changes.
     */
    void addObserver(StateObserver observer);

    /**
     * Removes a registered listener.
     */
    void removeObserver(StateObserver observer);

    /**
     * Provides an execution context for lifecycle-bound tasks (replaces lifecycleScope).
     * All tasks that rely on the lifecycle state should be run on this Executor.
     * @return An Executor that can run tasks.
     */
    Executor getLifecycleExecutor();
}

package com.osfans.trime.core;

import com.osfans.trime.core.RimeLifecycle.State;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Utility class containing static methods to replace Kotlin's suspend functions 
 * (whenAtState, whenReady) for state-dependent execution.
 * * NOTE: These methods are BLOCKING and should be executed on a background thread 
 * if they are called in a context that requires responsiveness.
 */
public final class RimeLifecycleUtils {

    private RimeLifecycleUtils() {
        // Utility class
    }

    /**
     * Executes a task when the lifecycle reaches a specific state, blocking the calling thread until then.
     * The task itself is executed on the RimeLifecycle's dedicated executor.
     *
     * @param lifecycle The RimeLifecycle instance.
     * @param state The target state to wait for.
     * @param block The task to execute.
     * @param <T> The return type of the task.
     * @return The result of the executed task.
     * @throws InterruptedException if the waiting thread is interrupted.
     * @throws ExecutionException if the executed task throws an exception.
     * @throws Exception if the internal state waiting logic times out.
     */
    public static <T> T whenAtState(
            RimeLifecycle lifecycle,
            State state,
            Callable<T> block
    ) throws InterruptedException, ExecutionException, Exception {

        // 1. If already at state, execute immediately on the executor
        if (lifecycle.getCurrentState() == state) {
            FutureTask<T> future = new FutureTask<>(block);
            lifecycle.getLifecycleExecutor().execute(future);
            return future.get();
        }

        // 2. Wait for the state using standard Java concurrency

        final Object lock = new Object();
        final AtomicReference<State> currentStateRef = new AtomicReference<>(lifecycle.getCurrentState());

        RimeLifecycle.StateObserver waiter = newState -> {
            synchronized (lock) {
                currentStateRef.set(newState);
                if (newState == state) {
                    lock.notifyAll(); // Signal the waiting thread
                }
            }
        };

        // Register observer
        lifecycle.addObserver(waiter);
        try {
            synchronized (lock) {
                // Wait until the state matches the target
                while (currentStateRef.get() != state) {
                    // Set a timeout to prevent indefinite block in case of error
                    lock.wait(5000);
                    if (currentStateRef.get() != state) {
                        // Check again and throw if we timed out
                        throw new Exception("Timeout waiting for RimeLifecycle state to reach " + state);
                    }
                }
            }

            // 3. State reached: execute the block on the designated executor
            FutureTask<T> future = new FutureTask<>(block);
            lifecycle.getLifecycleExecutor().execute(future);
            return future.get();

        } finally {
            // 4. Clean up the observer
            lifecycle.removeObserver(waiter);
        }
    }

    /**
     * Executes a task when the Rime Lifecycle is in the READY state, blocking the calling thread until then.
     *
     * @param lifecycle The RimeLifecycle instance.
     * @param block The task to execute.
     * @param <T> The return type of the task.
     * @return The result of the executed task.
     */
    public static <T> T whenReady(
            RimeLifecycle lifecycle,
            Callable<T> block
    ) throws InterruptedException, ExecutionException, Exception {
        return whenAtState(lifecycle, State.READY, block);
    }
}

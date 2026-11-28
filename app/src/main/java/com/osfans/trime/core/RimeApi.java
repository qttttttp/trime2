/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.core;

import com.osfans.trime.core.KeyModifiers;
import com.osfans.trime.core.KeyValue;

/**
 * Rime API Interface in Java.
 *
 * NOTE: Coroutine concepts (suspend, SharedFlow) are converted to synchronous methods
 * and general Flow interfaces. You will need to handle threading and Flow implementation
 * in your concrete Java classes.
 */
public interface RimeApi {


    SharedFlowImpl<?> getMessage();

    RimeLifecycle.State getState();

    boolean isReady();

    RimeSchema getSchemaCached();

    RimeProto.Status getStatusCached();

    RimeProto.Context.Composition getCompositionCached();

    RimeProto.Context.Menu getMenuCached();

    // --- Suspend Functions (Converted to Synchronous Methods) ---

    boolean isEmpty();

    void deploy();

    boolean syncUserData();

    /**
     * Sends a key event to Rime.
     * @param value The keycode value.
     * @param modifiers The key modifiers (converted from UInt).
     * @param isVirtual Whether the key is virtual.
     * @return true if the key event was handled by Rime.
     */
    boolean processKey(
            int value,
            long modifiers, // Kotlin UInt converted to long for safety
            boolean isVirtual
    );

    // Overload 1: Default parameters for modifiers and isVirtual
    default boolean processKey(int value) {
        return processKey(value, 0L, true);
    }

    // Overload 2: Default parameter for isVirtual
    default boolean processKey(int value, long modifiers) {
        return processKey(value, modifiers, true);
    }

    boolean processKey(
            KeyValue value,
            KeyModifiers modifiers,
            boolean isVirtual
    );

    // Overload 3: Default parameter for isVirtual
    default boolean processKey(KeyValue value, KeyModifiers modifiers) {
        return processKey(value, modifiers, true);
    }

    boolean simulateKeySequence(String sequence);

    boolean selectCandidate(int idx);

    boolean forgetCandidate(int idx);

    boolean selectPagedCandidate(int idx);

    boolean deletedPagedCandidate(int idx);

    boolean changeCandidatePage(boolean backward);

    void moveCursorPos(int position);

    SchemaItem[] availableSchemata();

    SchemaItem[] enabledSchemata();

    boolean setEnabledSchemata(String[] schemaIds);

    SchemaItem[] selectedSchemata();

    String selectedSchemaId();

    boolean selectSchema(String schemaId);

    RimeSchema currentSchema();

    boolean commitComposition();

    void clearComposition();

    void setRuntimeOption(
            String option,
            boolean value
    );

    boolean getRuntimeOption(String option);

    /**
     * 写入一个字符串属性（property）。
     * 与 librime-lua 的 context:set_property(prop, value) 读写的是同一份存储，
     * 可用于 Java 层与 Lua 脚本之间传递任意字符串数据。
     */
    void setProperty(String prop, String value);

    /**
     * 读取一个字符串属性；不存在时返回空字符串。
     * 对应 librime-lua 的 context:get_property(prop)。
     */
    String getProperty(String prop);

    CandidateItem[] getCandidates(
            int startIndex,
            int limit
    );
}

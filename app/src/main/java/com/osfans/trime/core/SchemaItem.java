/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.core;

import java.util.Objects;

public class SchemaItem {
    private final String id;
    private final String name;

    // Default constructor matching Kotlin's default arguments
    public SchemaItem(String id) {
        this(id, "");
    }

    public SchemaItem(String id, String name) {
        this.id = id;
        this.name = (name != null) ? name : "";
    }

    public String getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        SchemaItem that = (SchemaItem) o;
        return Objects.equals(id, that.id) && Objects.equals(name, that.name);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id, name);
    }

    @Override
    public String toString() {
        return "SchemaItem(id='" + id + "', name='" + name + "')";
    }
}


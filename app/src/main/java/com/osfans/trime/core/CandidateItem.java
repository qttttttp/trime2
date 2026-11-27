/*
 * SPDX-FileCopyrightText: 2015 - 2025 Rime community
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package com.osfans.trime.core;

import java.util.Objects;

public class CandidateItem {
    private final String text;
    private final String comment;
    private int mIndex=-1;

    // Default constructor matching Kotlin's default arguments
    public CandidateItem(String text) {
        this(text, "");
    }

    public CandidateItem(String text, String comment) {
        this.text = text;
        this.comment = (comment != null) ? comment : "";
    }

    public String getText() {
        return text;
    }

    public String getComment() {
        return comment;
    }

    public void setIndex(int idx){
        mIndex=idx;
    }

    public int getIndex(){
        return mIndex;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        CandidateItem that = (CandidateItem) o;
        return Objects.equals(text, that.text) && Objects.equals(comment, that.comment);
    }

    @Override
    public int hashCode() {
        return Objects.hash(text, comment);
    }

    @Override
    public String toString() {
        return text;
    }
}

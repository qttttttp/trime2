package com.osfans.trime.core;

import java.util.Arrays;
import java.util.Objects;

/**
 * Rime protocol data classes, replacing the Kotlin data classes.
 *
 * This class serves as a container for all protocol-related data structures
 * used for communication with the Rime engine.
 */
public final class RimeProto {

    // --- Commit Data Class ---

    public static final class Commit {
        private final String text;

        public Commit(String text) {
            this.text = text;
        }

        public String getText() {
            return text;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            Commit commit = (Commit) o;
            return Objects.equals(text, commit.text);
        }

        @Override
        public int hashCode() {
            return Objects.hash(text);
        }

        @Override
        public String toString() {
            return "Commit(text='" + text + "')";
        }
    }

    // --- Candidate Data Class ---

    public static final class Candidate {
        private final String text;
        private final String comment;
        private final String label;

        public Candidate(String text, String comment, String label) {
            this.text = text;
            this.comment = comment;
            this.label = label;
        }

        public String getText() {
            return text;
        }

        public String getComment() {
            return comment;
        }

        public String getLabel() {
            return label;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            Candidate candidate = (Candidate) o;
            return Objects.equals(text, candidate.text) &&
                    Objects.equals(comment, candidate.comment) &&
                    Objects.equals(label, candidate.label);
        }

        @Override
        public int hashCode() {
            return Objects.hash(text, comment, label);
        }

        @Override
        public String toString() {
            return "Candidate(text='" + text + "', comment='" + comment + "', label='" + label + "')";
        }
    }

    // --- Context Data Class ---

    public static final class Context {
        private final Composition composition;
        private final Menu menu;
        private final String input;
        private final int caretPos;

        // Default constructor matching Kotlin's default arguments
        public Context() {
            this(new Composition(), new Menu(), "", 0);
        }

        public Context(Composition composition, Menu menu, String input, int caretPos) {
            this.composition = composition;
            this.menu = menu;
            this.input = input;
            this.caretPos = caretPos;
        }

        public Composition getComposition() {
            return composition;
        }

        public Menu getMenu() {
            return menu;
        }

        public String getInput() {
            return input;
        }

        public int getCaretPos() {
            return caretPos;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            Context context = (Context) o;
            return caretPos == context.caretPos &&
                    Objects.equals(composition, context.composition) &&
                    Objects.equals(menu, context.menu) &&
                    Objects.equals(input, context.input);
        }

        @Override
        public int hashCode() {
            return Objects.hash(composition, menu, input, caretPos);
        }

        @Override
        public String toString() {
            return "Context(composition=" + composition + ", menu=" + menu + ", input='" + input + "', caretPos=" + caretPos + ")";
        }

        // --- Context.Composition Data Class ---

        public static final class Composition {
            private final int length;
            private final int cursorPos;
            private final int selStart;
            private final int selEnd;
            private final String preedit;
            private final String commitTextPreview;

            // Full constructor matching Kotlin's primary constructor with defaults
            public Composition() {
                this(0, 0, 0, 0, null, null);
            }

            public Composition(int length, int cursorPos, int selStart, int selEnd, String preedit, String commitTextPreview) {
                this.length = length;
                this.cursorPos = cursorPos;
                this.selStart = selStart;
                this.selEnd = selEnd;
                this.preedit = preedit;
                this.commitTextPreview = commitTextPreview;
            }

            // Secondary constructor matching Kotlin's secondary constructor (text conversion)
            public Composition(String text) {
                this(
                        text.length(),
                        text.length(),
                        text.length(),
                        text.length(),
                        text,
                        null // commitTextPreview remains null
                );
            }

            public int getLength() {
                return length;
            }

            public int getCursorPos() {
                return cursorPos;
            }

            public int getSelStart() {
                return selStart;
            }

            public int getSelEnd() {
                return selEnd;
            }

            public String getPreedit() {
                return preedit;
            }

            public String getCommitTextPreview() {
                return commitTextPreview;
            }

            @Override
            public boolean equals(Object o) {
                if (this == o) return true;
                if (o == null || getClass() != o.getClass()) return false;
                Composition that = (Composition) o;
                return length == that.length &&
                        cursorPos == that.cursorPos &&
                        selStart == that.selStart &&
                        selEnd == that.selEnd &&
                        Objects.equals(preedit, that.preedit) &&
                        Objects.equals(commitTextPreview, that.commitTextPreview);
            }

            @Override
            public int hashCode() {
                return Objects.hash(length, cursorPos, selStart, selEnd, preedit, commitTextPreview);
            }

            @Override
            public String toString() {
                return "Composition(length=" + length + ", cursorPos=" + cursorPos + ", selStart=" + selStart + ", selEnd=" + selEnd + ", preedit='" + preedit + "', commitTextPreview='" + commitTextPreview + "')";
            }
        }

        // --- Context.Menu Data Class ---

        public static final class Menu {
            private final int pageSize;
            private final int pageNumber;
            private final boolean isLastPage;
            private final int highlightedCandidateIndex;
            private final Candidate[] candidates;
            private final String selectKeys;
            private final String[] selectLabels;

            // Full constructor matching Kotlin's primary constructor with defaults
            public Menu() {
                this(0, 0, false, 0, new Candidate[0], null, new String[0]);
            }

            public Menu(int pageSize, int pageNumber, boolean isLastPage, int highlightedCandidateIndex, Candidate[] candidates, String selectKeys, String[] selectLabels) {
                this.pageSize = pageSize;
                this.pageNumber = pageNumber;
                this.isLastPage = isLastPage;
                this.highlightedCandidateIndex = highlightedCandidateIndex;
                this.candidates = candidates;
                this.selectKeys = selectKeys;
                this.selectLabels = selectLabels;
            }

            public int getPageSize() {
                return pageSize;
            }

            public int getPageNumber() {
                return pageNumber;
            }

            public boolean isLastPage() {
                return isLastPage;
            }

            public int getHighlightedCandidateIndex() {
                return highlightedCandidateIndex;
            }

            public Candidate[] getCandidates() {
                return candidates;
            }

            public String getSelectKeys() {
                return selectKeys;
            }

            public String[] getSelectLabels() {
                return selectLabels;
            }

            // Custom equals implementation using Arrays.equals for array content comparison
            @Override
            public boolean equals(Object o) {
                if (this == o) return true;
                if (o == null || getClass() != o.getClass()) return false;
                Menu menu = (Menu) o;
                return pageSize == menu.pageSize &&
                        pageNumber == menu.pageNumber &&
                        isLastPage == menu.isLastPage &&
                        highlightedCandidateIndex == menu.highlightedCandidateIndex &&
                        Objects.equals(selectKeys, menu.selectKeys) &&
                        Arrays.equals(candidates, menu.candidates) && // Array content check
                        Arrays.equals(selectLabels, menu.selectLabels); // Array content check
            }

            // Custom hashCode implementation using Arrays.hashCode for array content
            @Override
            public int hashCode() {
                int result = Objects.hash(pageSize, pageNumber, isLastPage, highlightedCandidateIndex, selectKeys);
                result = 31 * result + Arrays.hashCode(candidates);
                result = 31 * result + Arrays.hashCode(selectLabels);
                return result;
            }

            @Override
            public String toString() {
                return "Menu(pageSize=" + pageSize + ", pageNumber=" + pageNumber + ", isLastPage=" + isLastPage + ", highlightedCandidateIndex=" + highlightedCandidateIndex + ", candidates=" + Arrays.toString(candidates) + ", selectKeys='" + selectKeys + "', selectLabels=" + Arrays.toString(selectLabels) + ")";
            }
        }
    }

    // --- Status Data Class ---

    public static final class Status {
        private final String schemaId;
        private final String schemaName;
        private final boolean isDisabled;
        private final boolean isComposing;
        private final boolean isAsciiMode;
        private final boolean isFullShape;
        private final boolean isSimplified;
        private final boolean isTraditional;
        private final boolean isAsciiPunch;

        // Full constructor matching Kotlin's primary constructor with defaults
        public Status() {
            this("", "", true, false, true, false, false, false, true);
        }

        public Status(String schemaId, String schemaName, boolean isDisabled, boolean isComposing, boolean isAsciiMode, boolean isFullShape, boolean isSimplified, boolean isTraditional, boolean isAsciiPunch) {
            this.schemaId = schemaId;
            this.schemaName = schemaName;
            this.isDisabled = isDisabled;
            this.isComposing = isComposing;
            this.isAsciiMode = isAsciiMode;
            this.isFullShape = isFullShape;
            this.isSimplified = isSimplified;
            this.isTraditional = isTraditional;
            this.isAsciiPunch = isAsciiPunch;
        }

        public String getSchemaId() {
            return schemaId;
        }

        public String getSchemaName() {
            return schemaName;
        }

        public boolean isDisabled() {
            return isDisabled;
        }

        public boolean isComposing() {
            return isComposing;
        }

        public boolean isAsciiMode() {
            return isAsciiMode;
        }

        public boolean isFullShape() {
            return isFullShape;
        }

        public boolean isSimplified() {
            return isSimplified;
        }

        public boolean isTraditional() {
            return isTraditional;
        }

        public boolean isAsciiPunch() {
            return isAsciiPunch;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            Status status = (Status) o;
            return isDisabled == status.isDisabled &&
                    isComposing == status.isComposing &&
                    isAsciiMode == status.isAsciiMode &&
                    isFullShape == status.isFullShape &&
                    isSimplified == status.isSimplified &&
                    isTraditional == status.isTraditional &&
                    isAsciiPunch == status.isAsciiPunch &&
                    Objects.equals(schemaId, status.schemaId) &&
                    Objects.equals(schemaName, status.schemaName);
        }

        @Override
        public int hashCode() {
            return Objects.hash(schemaId, schemaName, isDisabled, isComposing, isAsciiMode, isFullShape, isSimplified, isTraditional, isAsciiPunch);
        }

        @Override
        public String toString() {
            return "Status(schemaId='" + schemaId + "', schemaName='" + schemaName + "', isDisabled=" + isDisabled + ", isComposing=" + isComposing + ", isAsciiMode=" + isAsciiMode + ", isFullShape=" + isFullShape + ", isSimplified=" + isSimplified + ", isTraditional=" + isTraditional + ", isAsciiPunch=" + isAsciiPunch + ")";
        }
    }
}

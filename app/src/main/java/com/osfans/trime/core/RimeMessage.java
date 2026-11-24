package com.osfans.trime.core;

import java.util.Arrays;
import java.util.Locale;
import java.util.Objects;

/**
 * Abstract base class for all Rime messages, replacing the Kotlin sealed class.
 *
 * @param <T> The type of data carried by this message.
 */
public abstract class RimeMessage<T> {

    // Abstract field for data (replaces Kotlin's open val data)
    public final T data;

    // Abstract field for messageType
    public abstract MessageType getMessageType();

    public RimeMessage(T data) {
        this.data = data;
    }

    public T getData(){
        return this.data;
    }

    // --- Message Type Enum ---

    public enum MessageType {
        Unknown,
        Schema,
        Option,
        Deploy,
        Commit,
        Composition,
        Menu,
        Status,
        Candidate,
        Key,
    }

    // --- Nested Message Classes (Replacing Kotlin Data Classes) ---

    public static final class UnknownMessage extends RimeMessage<Object[]> {
        public UnknownMessage(Object[] data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Unknown;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            UnknownMessage that = (UnknownMessage) o;
            // Use Arrays.equals for content comparison
            return Arrays.equals(data, that.data);
        }

        @Override
        public int hashCode() {
            // Use Arrays.hashCode for content hash
            return Arrays.hashCode(data);
        }
    }

    public static final class SchemaMessage extends RimeMessage<SchemaItem> {
        public SchemaMessage(SchemaItem data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Schema;
        }

        @Override
        public String toString() {
            return String.format("SchemaMessage(id=%s, name=%s)", data.getId(), data.getName());
        }
    }

    public static final class OptionMessage extends RimeMessage<OptionMessage.Data> {
        public OptionMessage(OptionMessage.Data data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Option;
        }

        public static final class Data {
            private final String option;
            private final boolean value;

            public Data(String option, boolean value) {
                this.option = option;
                this.value = value;
            }

            public String getOption() {
                return option;
            }

            public boolean isValue() {
                return value;
            }

            // Generated equals/hashCode for Data class
            @Override
            public boolean equals(Object o) {
                if (this == o) return true;
                if (o == null || getClass() != o.getClass()) return false;
                Data data = (Data) o;
                return value == data.value && Objects.equals(option, data.option);
            }

            @Override
            public int hashCode() {
                return Objects.hash(option, value);
            }
            @Override
            public String toString() {
                return String.format("OptionMessage.Data(option=%s, value=%b)", getOption(), isValue());
            }
        }

        @Override
        public String toString() {
            return String.format("OptionMessage(option=%s, value=%b)", data.getOption(), data.isValue());
        }
    }

    public static final class DeployMessage extends RimeMessage<DeployMessage.State> {
        public DeployMessage(DeployMessage.State data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Deploy;
        }

        public enum State {
            Start,
            Success,
            Failure,
        }

        @Override
        public String toString() {
            return String.format("DeployMessage(state=%s)", data.name());
        }
    }

    public static final class CommitTextMessage extends RimeMessage<RimeProto.Commit> {
        public CommitTextMessage(RimeProto.Commit data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Commit;
        }
    }

    public static final class CompositionMessage extends RimeMessage<RimeProto.Context.Composition> {
        public CompositionMessage(RimeProto.Context.Composition data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Composition;
        }
    }

    public static final class CandidateMenuMessage extends RimeMessage<RimeProto.Context.Menu> {
        public CandidateMenuMessage(RimeProto.Context.Menu data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Menu;
        }
    }

    public static final class StatusMessage extends RimeMessage<RimeProto.Status> {
        public StatusMessage(RimeProto.Status data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Status;
        }
    }

    public static final class CandidateListMessage extends RimeMessage<CandidateListMessage.Data> {
        public CandidateListMessage(CandidateListMessage.Data data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Candidate;
        }

        public static final class Data {
            private final int total;
            private final CandidateItem[] candidates;

            public Data(int total, CandidateItem[] candidates) {
                this.total = total;
                this.candidates = candidates;
            }

            public int getTotal() {
                return total;
            }

            public CandidateItem[] getCandidates() {
                return candidates;
            }

            @Override
            public String toString() {
                String candidatesStr;
                if (candidates.length > 5) {
                    candidatesStr = Arrays.toString(Arrays.copyOf(candidates, 5)) + ", ...]";
                } else {
                    candidatesStr = Arrays.toString(candidates);
                }
                return String.format("total=%d, candidates=%s", total, candidatesStr);
            }

            // Generated equals/hashCode for Data class using array content
            @Override
            public boolean equals(Object o) {
                if (this == o) return true;
                if (o == null || getClass() != o.getClass()) return false;
                Data data = (Data) o;
                return total == data.total && Arrays.equals(candidates, data.candidates);
            }

            @Override
            public int hashCode() {
                int result = total;
                result = 31 * result + Arrays.hashCode(candidates);
                return result;
            }
        }
    }

    public static final class KeyMessage extends RimeMessage<KeyMessage.Data> {
        public KeyMessage(KeyMessage.Data data) {
            super(data);
        }

        @Override
        public MessageType getMessageType() {
            return MessageType.Key;
        }

        public static final class Data {
            private final KeyValue value;
            private final KeyModifiers modifiers;
            private final boolean isVirtual;

            public Data(KeyValue value, KeyModifiers modifiers, boolean isVirtual) {
                this.value = value;
                this.modifiers = modifiers;
                this.isVirtual = isVirtual;
            }

            public KeyValue getValue() {
                return value;
            }

            public KeyModifiers getModifiers() {
                return modifiers;
            }

            public boolean isVirtual() {
                return isVirtual;
            }

            // Generated equals/hashCode for Data class
            @Override
            public boolean equals(Object o) {
                if (this == o) return true;
                if (o == null || getClass() != o.getClass()) return false;
                Data data = (Data) o;
                return isVirtual == data.isVirtual &&
                        Objects.equals(value, data.value) &&
                        Objects.equals(modifiers, data.modifiers);
            }

            @Override
            public int hashCode() {
                return Objects.hash(value, modifiers, isVirtual);
            }
        }
    }

    // --- Static Factory Methods (Replacing Kotlin Companion Object) ---

    private static final MessageType[] TYPES = MessageType.values();

    /**
     * Factory method to create a RimeMessage from native parameters.
     * This method is typically called from JNI.
     *
     * @param type The ordinal (int) of the MessageType.
     * @param params An array of parameters from the native side.
     * @return The constructed RimeMessage instance.
     * @throws IllegalArgumentException if the type ordinal is invalid.
     */
    public static RimeMessage<?> nativeCreate(
            int type,
            Object[] params
    ) {
        if (type < 0 || type >= TYPES.length) {
            return new UnknownMessage(params);
        }

        switch (TYPES[type]) {
            case Schema:
                String schemaString = (String) params[0];
                String[] parts = schemaString.split("/", 2);
                String id = parts[0];
                String name = parts.length > 1 ? parts[1] : id;
                return new SchemaMessage(new SchemaItem(id, name));

            case Option:
                String value = (String) params[0];
                boolean isSet = !value.startsWith("!");
                String optionName = value.substring(isSet ? 0 : 1); // remove '!' if present
                return new OptionMessage(
                        new OptionMessage.Data(optionName, isSet)
                );

            case Deploy:
                String stateStr = (String) params[0];
                // Java equivalent of Kotlin's replaceFirstChar { it.titlecase() }
                String capitalizedState = stateStr.substring(0, 1).toUpperCase(Locale.ROOT) + stateStr.substring(1);
                return new DeployMessage(DeployMessage.State.valueOf(capitalizedState));

            case Commit:
                return new CommitTextMessage((RimeProto.Commit) params[0]);

            case Composition:
                return new CompositionMessage((RimeProto.Context.Composition) params[0]);

            case Menu:
                return new CandidateMenuMessage((RimeProto.Context.Menu) params[0]);

            case Status:
                return new StatusMessage((RimeProto.Status) params[0]);

            case Candidate:
                return new CandidateListMessage(
                        new CandidateListMessage.Data(
                                (Integer) params[0],
                                (CandidateItem[]) params[1]
                        )
                );

            case Key:
                return new KeyMessage(
                        new KeyMessage.Data(
                                new KeyValue((Integer) params[0]),
                                KeyModifiers.of((Integer) params[1]),
                                (Boolean) params[2]
                        )
                );

            case Unknown:
            default:
                return new UnknownMessage(params);
        }
    }

    /**
     * Factory method to create a RimeMessage from a known MessageType and parameters.
     *
     * @param type The specific message type.
     * @param params An array of parameters matching the required message structure.
     * @return The constructed RimeMessage instance.
     */
    public static RimeMessage<?> create(
            MessageType type,
            Object[] params
    ) {
        return nativeCreate(type.ordinal(), params);
    }
}

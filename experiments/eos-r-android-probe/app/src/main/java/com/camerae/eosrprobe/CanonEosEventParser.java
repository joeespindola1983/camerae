package com.camerae.eosrprobe;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

final class CanonEosEventParser {
    private static final int EVENT_OBJECT_ADDED_EX = 0xC181;
    private static final int EVENT_OBJECT_ADDED_EX_64 = 0xC1A7;
    private static final int RECORD_HEADER_LENGTH = 8;
    private static final int OBJECT_NAME_OFFSET = 0x28;
    private static final int OBJECT_64_NAME_OFFSET = 0x2C;

    private CanonEosEventParser() {
    }

    static CapturedObject findObjectAdded(byte[] data) {
        int offset = 0;
        while (offset + RECORD_HEADER_LENGTH <= data.length) {
            long recordSizeLong = uint32(data, offset);
            long eventCode = uint32(data, offset + 4);
            if (recordSizeLong == 8 && eventCode == 0) {
                return null;
            }
            if (recordSizeLong < RECORD_HEADER_LENGTH
                    || recordSizeLong > Integer.MAX_VALUE
                    || offset + recordSizeLong > data.length) {
                return null;
            }

            int recordSize = (int) recordSizeLong;
            boolean objectAdded = eventCode == EVENT_OBJECT_ADDED_EX;
            boolean objectAdded64 = eventCode == EVENT_OBJECT_ADDED_EX_64;
            int nameOffset = objectAdded64 ? OBJECT_64_NAME_OFFSET : OBJECT_NAME_OFFSET;
            if ((objectAdded || objectAdded64) && recordSize > nameOffset) {
                int handle = (int) uint32(data, offset + 0x08);
                int storageId = (int) uint32(data, offset + 0x0C);
                int format = uint16(data, offset + 0x10);
                long objectSize = uint32(data, offset + 0x1C);
                int parentOffset = objectAdded64 ? 0x24 : 0x20;
                int parent = (int) uint32(data, offset + parentOffset);
                String name = nullTerminatedString(
                        data,
                        offset + nameOffset,
                        offset + recordSize
                );
                return new CapturedObject(
                        handle,
                        storageId,
                        parent,
                        format,
                        objectSize,
                        name
                );
            }
            offset += recordSize;
        }
        return null;
    }

    private static long uint32(byte[] data, int offset) {
        return Integer.toUnsignedLong(ByteBuffer.wrap(data, offset, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .getInt());
    }

    private static int uint16(byte[] data, int offset) {
        return Short.toUnsignedInt(ByteBuffer.wrap(data, offset, 2)
                .order(ByteOrder.LITTLE_ENDIAN)
                .getShort());
    }

    private static String nullTerminatedString(byte[] data, int start, int end) {
        int cursor = start;
        while (cursor < end && data[cursor] != 0) {
            cursor++;
        }
        return new String(data, start, cursor - start, StandardCharsets.UTF_8);
    }

    static final class CapturedObject {
        final int handle;
        final int storageId;
        final int parent;
        final int format;
        final long size;
        final String name;

        CapturedObject(
                int handle,
                int storageId,
                int parent,
                int format,
                long size,
                String name
        ) {
            this.handle = handle;
            this.storageId = storageId;
            this.parent = parent;
            this.format = format;
            this.size = size;
            this.name = name;
        }
    }
}

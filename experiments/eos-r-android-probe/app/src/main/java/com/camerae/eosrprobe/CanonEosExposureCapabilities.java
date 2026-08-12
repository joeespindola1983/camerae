package com.camerae.eosrprobe;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

final class CanonEosExposureCapabilities {
    private static final int EVENT_PROP_VALUE_CHANGED = 0xC189;
    private static final int EVENT_AVAILABLE_LIST_CHANGED = 0xC18A;
    private static final int PROP_AUTO_EXPOSURE_MODE = 0xD105;
    private static final int PROP_AUTO_EXPOSURE_MODE_DIAL = 0xD138;
    private static final int PROP_SHUTTER_SPEED = 0xD102;
    private static final int PROP_ISO_SPEED = 0xD103;
    private static final int PROP_WHITE_BALANCE = 0xD109;
    private static final int RECORD_HEADER_LENGTH = 8;
    private static final int MAX_OPTIONS = 256;

    private final PropertyCapability shutter =
            new PropertyCapability(PROP_SHUTTER_SPEED, "Shutter");
    private final PropertyCapability iso =
            new PropertyCapability(PROP_ISO_SPEED, "ISO");
    private final PropertyCapability whiteBalance =
            new PropertyCapability(PROP_WHITE_BALANCE, "White balance");
    private final PropertyCapability exposureMode =
            new PropertyCapability(PROP_AUTO_EXPOSURE_MODE, "Modo de exposição");
    private final PropertyCapability exposureModeDial =
            new PropertyCapability(PROP_AUTO_EXPOSURE_MODE_DIAL, "Seletor de exposição");

    void accept(byte[] data) {
        int offset = 0;
        while (offset + RECORD_HEADER_LENGTH <= data.length) {
            long recordSizeLong = uint32(data, offset);
            long eventCode = uint32(data, offset + 4);
            if (recordSizeLong == 8 && eventCode == 0) {
                return;
            }
            if (recordSizeLong < RECORD_HEADER_LENGTH
                    || recordSizeLong > Integer.MAX_VALUE
                    || offset + recordSizeLong > data.length) {
                return;
            }

            int recordSize = (int) recordSizeLong;
            if (recordSize >= 12) {
                int propertyCode = (int) uint32(data, offset + 8);
                PropertyCapability property = property(propertyCode);
                if (property != null) {
                    if (eventCode == EVENT_PROP_VALUE_CHANGED && recordSize >= 16) {
                        property.currentValue = (int) uint32(data, offset + 12);
                    } else if (eventCode == EVENT_AVAILABLE_LIST_CHANGED && recordSize >= 20) {
                        int descriptorType = (int) uint32(data, offset + 12);
                        long optionCountLong = uint32(data, offset + 16);
                        if (descriptorType == 3
                                && optionCountLong <= MAX_OPTIONS
                                && optionCountLong * 4L <= recordSize - 20L) {
                            int optionCount = (int) optionCountLong;
                            property.availableValues.clear();
                            for (int index = 0; index < optionCount; index++) {
                                property.availableValues.add(
                                        (int) uint32(data, offset + 20 + index * 4)
                                );
                            }
                        }
                    }
                }
            }
            offset += recordSize;
        }
    }

    boolean isUsable() {
        boolean shutterExpectedToBeLocked = isBulbMode() && shutter.currentValue != null;
        return exposureMode.currentValue != null
                && iso.isConfirmed()
                && whiteBalance.isConfirmed()
                && (shutter.isConfirmed() || shutterExpectedToBeLocked);
    }

    String summary() {
        return "Modo: " + exposureModeLabel(exposureMode.currentValue) + "\n"
                + shutter.summary(isBulbMode()) + "\n"
                + iso.summary(false) + "\n"
                + whiteBalance.summary(false);
    }

    String report() {
        StringBuilder report = new StringBuilder("CONTROLES DE EXPOSIÇÃO EOS R\n");
        report.append("Modo atual: ").append(exposureModeLabel(exposureMode.currentValue))
                .append(" (").append(nullableHex(exposureMode.currentValue)).append(")\n");
        report.append("Seletor atual: ").append(exposureModeLabel(exposureModeDial.currentValue))
                .append(" (").append(nullableHex(exposureModeDial.currentValue)).append(")\n");
        appendPropertyReport(report, shutter);
        appendPropertyReport(report, iso);
        appendPropertyReport(report, whiteBalance);
        report.append("Escrita segura: ISO e white balance, limitada aos valores anunciados")
                .append(" e confirmada por readback\n");
        if (isBulbMode() && shutter.availableValues.isEmpty()) {
            report.append("Diagnóstico shutter: lista indisponível é esperada no modo Bulb; ")
                    .append("a duração deve ser controlada pelo tempo entre FullPress e FullRelease\n");
        }
        return report.toString();
    }

    Snapshot snapshot() {
        return new Snapshot(
                exposureMode.currentValue == null ? -1 : exposureMode.currentValue,
                shutter.currentValue == null ? -1 : shutter.currentValue,
                iso.currentValue == null ? -1 : iso.currentValue,
                whiteBalance.currentValue == null ? -1 : whiteBalance.currentValue,
                options(iso),
                options(whiteBalance)
        );
    }

    boolean isAvailable(int propertyCode, int value) {
        PropertyCapability capability = property(propertyCode);
        return capability != null && capability.availableValues.contains(value);
    }

    int currentValue(int propertyCode) {
        PropertyCapability capability = property(propertyCode);
        return capability == null || capability.currentValue == null
                ? -1
                : capability.currentValue;
    }

    private static List<Option> options(PropertyCapability property) {
        List<Option> options = new ArrayList<>();
        for (int value : property.availableValues) {
            options.add(new Option(value, label(property.code, value)));
        }
        return Collections.unmodifiableList(options);
    }

    private static void appendPropertyReport(
            StringBuilder report,
            PropertyCapability property
    ) {
        report.append(property.name).append(" ").append(hex4(property.code)).append('\n');
        if (property.currentValue == null) {
            report.append("  Atual: não informado\n");
        } else {
            report.append("  Atual: ").append(label(property.code, property.currentValue))
                    .append(" (").append(hex4(property.currentValue)).append(")\n");
        }
        report.append("  Valores anunciados: ").append(property.availableValues.size()).append('\n');
        int index = 0;
        for (int value : property.availableValues) {
            report.append("    [").append(index++).append("] ")
                    .append(label(property.code, value))
                    .append(" (").append(hex4(value)).append(")\n");
        }
    }

    private PropertyCapability property(int code) {
        switch (code) {
            case PROP_SHUTTER_SPEED:
                return shutter;
            case PROP_ISO_SPEED:
                return iso;
            case PROP_WHITE_BALANCE:
                return whiteBalance;
            case PROP_AUTO_EXPOSURE_MODE:
                return exposureMode;
            case PROP_AUTO_EXPOSURE_MODE_DIAL:
                return exposureModeDial;
            default:
                return null;
        }
    }

    private boolean isBulbMode() {
        return exposureMode.currentValue != null && exposureMode.currentValue == 0x0004;
    }

    private static String label(int propertyCode, int value) {
        switch (propertyCode) {
            case PROP_SHUTTER_SPEED:
                return shutterLabel(value);
            case PROP_ISO_SPEED:
                return isoLabel(value);
            case PROP_WHITE_BALANCE:
                return whiteBalanceLabel(value);
            default:
                return hex4(value);
        }
    }

    private static String isoLabel(int value) {
        int[] codes = {
                0x0000, 0x0001, 0x0028, 0x0030, 0x0038, 0x0040, 0x0043, 0x0045,
                0x0048, 0x004B, 0x004D, 0x0050, 0x0053, 0x0055, 0x0058, 0x005B,
                0x005D, 0x0060, 0x0063, 0x0065, 0x0068, 0x006B, 0x006D, 0x0070,
                0x0073, 0x0075, 0x0078, 0x007B, 0x007D, 0x0080, 0x0083, 0x0085,
                0x0088, 0x008B, 0x008D, 0x0090, 0x0093, 0x0095, 0x0098, 0x00A0,
                0x00A8, 0x00B0
        };
        String[] labels = {
                "Auto", "Auto ISO", "6", "12", "25", "50", "64", "80",
                "100", "125", "160", "200", "250", "320", "400", "500",
                "640", "800", "1000", "1250", "1600", "2000", "2500", "3200",
                "4000", "5000", "6400", "8000", "10000", "12800", "16000", "20000",
                "25600", "32000", "40000", "51200", "64000", "80000", "102400",
                "204800", "409600", "819200"
        };
        return lookup(codes, labels, value, "ISO desconhecido");
    }

    private static String shutterLabel(int value) {
        int[] codes = {
                0x0000, 0x0004, 0x000C, 0x0010, 0x0013, 0x0014, 0x0015, 0x0018,
                0x001B, 0x001C, 0x001D, 0x0020, 0x0023, 0x0024, 0x0025, 0x0028,
                0x002B, 0x002C, 0x002D, 0x0030, 0x0033, 0x0034, 0x0035, 0x0038,
                0x003B, 0x003C, 0x003D, 0x0040, 0x0043, 0x0044, 0x0045, 0x0048,
                0x004B, 0x004C, 0x004D, 0x0050, 0x0053, 0x0054, 0x0055, 0x0058,
                0x005B, 0x005C, 0x005D, 0x0060, 0x0063, 0x0064, 0x0065, 0x0068,
                0x006B, 0x006C, 0x006D, 0x0070, 0x0073, 0x0074, 0x0075, 0x0078,
                0x007B, 0x007C, 0x007D, 0x0080, 0x0083, 0x0084, 0x0085, 0x0088,
                0x008B, 0x008C, 0x008D, 0x0090, 0x0093, 0x0094, 0x0095, 0x0098,
                0x009B, 0x009C, 0x009D, 0x00A0, 0x00A8
        };
        String[] labels = {
                "Auto", "Bulb", "Bulb", "30 s", "25 s", "20.3 s", "20 s", "15 s",
                "13 s", "10 s", "10.3 s", "8 s", "6.3 s", "6 s", "5 s", "4 s",
                "3.2 s", "3 s", "2.5 s", "2 s", "1.6 s", "1.5 s", "1.3 s", "1 s",
                "0.8 s", "0.7 s", "0.6 s", "0.5 s", "0.4 s", "0.3 s", "0.3 s", "1/4 s",
                "1/5 s", "1/6 s", "1/6 s", "1/8 s", "1/10 s", "1/10 s", "1/13 s", "1/15 s",
                "1/20 s", "1/20 s", "1/25 s", "1/30 s", "1/40 s", "1/45 s", "1/50 s", "1/60 s",
                "1/80 s", "1/90 s", "1/100 s", "1/125 s", "1/160 s", "1/180 s", "1/200 s", "1/250 s",
                "1/320 s", "1/350 s", "1/400 s", "1/500 s", "1/640 s", "1/750 s", "1/800 s", "1/1000 s",
                "1/1250 s", "1/1500 s", "1/1600 s", "1/2000 s", "1/2500 s", "1/3000 s", "1/3200 s", "1/4000 s",
                "1/5000 s", "1/6000 s", "1/6400 s", "1/8000 s", "1/16000 s"
        };
        return lookup(codes, labels, value, "Shutter desconhecido");
    }

    private static String whiteBalanceLabel(int value) {
        switch (value) {
            case 0:
                return "Auto";
            case 1:
                return "Luz do dia";
            case 2:
                return "Nublado";
            case 3:
                return "Tungstênio";
            case 4:
                return "Fluorescente";
            case 5:
                return "Flash";
            case 6:
                return "Manual";
            case 8:
                return "Sombra";
            case 9:
                return "Temperatura de cor";
            case 10:
                return "Personalizado PC-1";
            case 11:
                return "Personalizado PC-2";
            case 12:
                return "Personalizado PC-3";
            case 15:
                return "Manual 2";
            case 16:
                return "Manual 3";
            case 18:
                return "Manual 4";
            case 19:
                return "Manual 5";
            case 20:
                return "Personalizado PC-4";
            case 21:
                return "Personalizado PC-5";
            case 23:
                return "AWB branco";
            default:
                return "WB desconhecido";
        }
    }

    private static String exposureModeLabel(Integer value) {
        if (value == null) {
            return "não informado";
        }
        switch (value) {
            case 0x0000:
                return "P";
            case 0x0001:
                return "Tv";
            case 0x0002:
                return "Av";
            case 0x0003:
                return "Manual";
            case 0x0004:
                return "Bulb";
            case 0x0008:
                return "Lock";
            case 0x0014:
                return "Vídeo";
            case 0x0016:
                return "Auto";
            case 0x0019:
                return "SCN";
            case 0x0037:
                return "Fv";
            default:
                return "Modo desconhecido";
        }
    }

    private static String lookup(
            int[] codes,
            String[] labels,
            int value,
            String fallback
    ) {
        for (int index = 0; index < codes.length; index++) {
            if (codes[index] == value) {
                return labels[index];
            }
        }
        return fallback;
    }

    private static long uint32(byte[] data, int offset) {
        return Integer.toUnsignedLong(ByteBuffer.wrap(data, offset, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .getInt());
    }

    private static String hex4(int value) {
        return String.format(Locale.US, "0x%04X", value & 0xFFFF);
    }

    private static String nullableHex(Integer value) {
        return value == null ? "<ausente>" : hex4(value);
    }

    private static final class PropertyCapability {
        final int code;
        final String name;
        final Set<Integer> availableValues = new LinkedHashSet<>();
        Integer currentValue;

        PropertyCapability(int code, String name) {
            this.code = code;
            this.name = name;
        }

        boolean isConfirmed() {
            return currentValue != null && !availableValues.isEmpty();
        }

        String summary(boolean expectedLocked) {
            String current = currentValue == null
                    ? "não informado"
                    : label(code, currentValue);
            if (expectedLocked && availableValues.isEmpty()) {
                return name + ": " + current + " • controlado pela duração Bulb";
            }
            return name + ": " + current + " • " + availableValues.size() + " opções";
        }
    }

    static final class Option {
        final int value;
        final String label;

        Option(int value, String label) {
            this.value = value;
            this.label = label;
        }

        @Override
        public String toString() {
            return label;
        }
    }

    static final class Snapshot {
        final int exposureMode;
        final int shutterValue;
        final int isoValue;
        final int whiteBalanceValue;
        final List<Option> isoOptions;
        final List<Option> whiteBalanceOptions;

        Snapshot(
                int exposureMode,
                int shutterValue,
                int isoValue,
                int whiteBalanceValue,
                List<Option> isoOptions,
                List<Option> whiteBalanceOptions
        ) {
            this.exposureMode = exposureMode;
            this.shutterValue = shutterValue;
            this.isoValue = isoValue;
            this.whiteBalanceValue = whiteBalanceValue;
            this.isoOptions = isoOptions;
            this.whiteBalanceOptions = whiteBalanceOptions;
        }

        boolean isBulbMode() {
            return exposureMode == 0x0004;
        }
    }
}

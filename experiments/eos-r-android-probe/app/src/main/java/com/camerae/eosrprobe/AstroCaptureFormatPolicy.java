package com.camerae.eosrprobe;

final class AstroCaptureFormatPolicy {
    private static final String JPG = "JPG";
    private static final String JPG_AND_CR3 = "JPG+CR3";

    private AstroCaptureFormatPolicy() {}

    static String[] selectableFormats() {
        return new String[]{JPG, JPG_AND_CR3};
    }

    static String normalize(String storedFormat) {
        if (JPG_AND_CR3.equals(storedFormat) || "CR3".equals(storedFormat)) {
            return JPG_AND_CR3;
        }
        return JPG;
    }
}

package com.camerae.eosrprobe;

final class ExposureDurationPolicy {
    static final int MIN_SECONDS = 1;
    static final int MAX_SECONDS = 45;

    private ExposureDurationPolicy() {}

    static int clamp(int seconds) {
        return Math.max(MIN_SECONDS, Math.min(MAX_SECONDS, seconds));
    }

    static int[] referenceMarks() {
        return new int[]{0, 5, 10, 15, 20, 25, 30, 35, 40, 45};
    }
}

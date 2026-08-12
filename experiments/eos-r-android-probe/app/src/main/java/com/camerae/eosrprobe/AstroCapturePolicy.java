package com.camerae.eosrprobe;

final class AstroCapturePolicy {
    enum State {
        IDLE,
        STARTING,
        RUNNING,
        PAUSING,
        PAUSED,
        FAILED,
        FINALIZED
    }

    private AstroCapturePolicy() {}

    static boolean shouldHoldWakeLock(State state) {
        return state == State.STARTING || state == State.RUNNING || state == State.PAUSING;
    }

    static boolean shouldRemainForeground(State state) {
        return state != State.IDLE && state != State.FINALIZED;
    }

    static boolean canPause(State state) {
        return state == State.STARTING || state == State.RUNNING;
    }

    static boolean canResume(State state) {
        return state == State.PAUSED || state == State.FAILED;
    }
}

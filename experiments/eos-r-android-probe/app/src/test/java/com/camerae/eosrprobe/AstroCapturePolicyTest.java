package com.camerae.eosrprobe;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class AstroCapturePolicyTest {
    @Test
    public void runningAndPausingKeepCpuAwake() {
        assertTrue(AstroCapturePolicy.shouldHoldWakeLock(AstroCapturePolicy.State.STARTING));
        assertTrue(AstroCapturePolicy.shouldHoldWakeLock(AstroCapturePolicy.State.RUNNING));
        assertTrue(AstroCapturePolicy.shouldHoldWakeLock(AstroCapturePolicy.State.PAUSING));
    }

    @Test
    public void pausedFailedAndFinalizedReleaseCpu() {
        assertFalse(AstroCapturePolicy.shouldHoldWakeLock(AstroCapturePolicy.State.PAUSED));
        assertFalse(AstroCapturePolicy.shouldHoldWakeLock(AstroCapturePolicy.State.FAILED));
        assertFalse(AstroCapturePolicy.shouldHoldWakeLock(AstroCapturePolicy.State.FINALIZED));
    }

    @Test
    public void notificationRemainsUntilSessionIsFinalized() {
        assertTrue(AstroCapturePolicy.shouldRemainForeground(AstroCapturePolicy.State.RUNNING));
        assertTrue(AstroCapturePolicy.shouldRemainForeground(AstroCapturePolicy.State.PAUSED));
        assertTrue(AstroCapturePolicy.shouldRemainForeground(AstroCapturePolicy.State.FAILED));
        assertFalse(AstroCapturePolicy.shouldRemainForeground(AstroCapturePolicy.State.FINALIZED));
    }

    @Test
    public void pauseAndResumeAreOnlyOfferedInValidStates() {
        assertTrue(AstroCapturePolicy.canPause(AstroCapturePolicy.State.RUNNING));
        assertTrue(AstroCapturePolicy.canResume(AstroCapturePolicy.State.PAUSED));
        assertTrue(AstroCapturePolicy.canResume(AstroCapturePolicy.State.FAILED));
        assertFalse(AstroCapturePolicy.canPause(AstroCapturePolicy.State.PAUSING));
        assertFalse(AstroCapturePolicy.canResume(AstroCapturePolicy.State.RUNNING));
    }
}

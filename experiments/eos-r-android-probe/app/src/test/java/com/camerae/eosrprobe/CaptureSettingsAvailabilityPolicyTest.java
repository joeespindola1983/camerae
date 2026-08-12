package com.camerae.eosrprobe;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class CaptureSettingsAvailabilityPolicyTest {
    @Test
    public void cameraMustBePresentAuthorizedAndSupported() {
        assertEquals(
                CaptureSettingsAvailabilityPolicy.State.CAMERA_MISSING,
                CaptureSettingsAvailabilityPolicy.evaluate(false, false, false, false, false)
        );
        assertEquals(
                CaptureSettingsAvailabilityPolicy.State.USB_PERMISSION_REQUIRED,
                CaptureSettingsAvailabilityPolicy.evaluate(true, false, true, false, false)
        );
        assertEquals(
                CaptureSettingsAvailabilityPolicy.State.UNSUPPORTED_CAMERA,
                CaptureSettingsAvailabilityPolicy.evaluate(true, true, false, false, false)
        );
        assertEquals(
                CaptureSettingsAvailabilityPolicy.State.READY,
                CaptureSettingsAvailabilityPolicy.evaluate(true, true, true, false, false)
        );
    }

    @Test
    public void busyAndFinalizedSessionsRemainReadOnly() {
        assertEquals(
                CaptureSettingsAvailabilityPolicy.State.CAMERA_BUSY,
                CaptureSettingsAvailabilityPolicy.evaluate(true, true, true, true, false)
        );
        assertEquals(
                CaptureSettingsAvailabilityPolicy.State.SESSION_FINALIZED,
                CaptureSettingsAvailabilityPolicy.evaluate(true, true, true, false, true)
        );
    }

    @Test
    public void onlyReadyStateEnablesTheWholeCaptureCard() {
        assertTrue(CaptureSettingsAvailabilityPolicy.State.READY.isEnabled());
        assertFalse(CaptureSettingsAvailabilityPolicy.State.CAMERA_MISSING.isEnabled());
        assertFalse(CaptureSettingsAvailabilityPolicy.State.USB_PERMISSION_REQUIRED.isEnabled());
        assertFalse(CaptureSettingsAvailabilityPolicy.State.CAMERA_BUSY.isEnabled());
    }
}

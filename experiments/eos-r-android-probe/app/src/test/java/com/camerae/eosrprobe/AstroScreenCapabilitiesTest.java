package com.camerae.eosrprobe;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class AstroScreenCapabilitiesTest {
    @Test
    public void catalogKeepsBuildIdentificationAndSessionActionsReachable() {
        assertTrue(AstroScreenCapabilities.sessionCatalog().contains(
                AstroScreenCapabilities.Capability.IDENTIFY_APP_VERSION));
        assertTrue(AstroScreenCapabilities.sessionCatalog().contains(
                AstroScreenCapabilities.Capability.CREATE_SESSION));
        assertTrue(AstroScreenCapabilities.sessionCatalog().contains(
                AstroScreenCapabilities.Capability.OPEN_SESSION));
        assertTrue(AstroScreenCapabilities.sessionCatalog().contains(
                AstroScreenCapabilities.Capability.DELETE_SESSION));
    }

    @Test
    public void captureKeepsExposureAndSessionLifecycleReachable() {
        assertTrue(AstroScreenCapabilities.captureSession().contains(
                AstroScreenCapabilities.Capability.ADJUST_EXPOSURE));
        assertTrue(AstroScreenCapabilities.captureSession().contains(
                AstroScreenCapabilities.Capability.START_SESSION));
        assertTrue(AstroScreenCapabilities.captureSession().contains(
                AstroScreenCapabilities.Capability.PAUSE_SESSION));
        assertTrue(AstroScreenCapabilities.captureSession().contains(
                AstroScreenCapabilities.Capability.FINALIZE_SESSION));
        assertTrue(AstroScreenCapabilities.captureSession().contains(
                AstroScreenCapabilities.Capability.SHARE_CAPTURE_LOG));
    }
}

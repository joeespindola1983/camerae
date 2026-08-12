package com.camerae.eosrprobe;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class AstroPreviewEnergyPolicyTest {
    @Test
    public void firstCaptureDoesNotDownloadJpegWithoutAnExplicitRequest() {
        assertFalse(AstroPreviewEnergyPolicy.shouldDownloadNextJpeg(false));
        assertTrue(AstroPreviewEnergyPolicy.shouldDownloadNextJpeg(true));
    }

    @Test
    public void liveViewFrameAndNextCapturePreviewAreNeverAvailableTogether() {
        assertTrue(AstroPreviewEnergyPolicy.canCaptureLiveViewFrame(true, false, false));
        assertFalse(AstroPreviewEnergyPolicy.canRequestNextCaptureJpeg(true, false));

        assertFalse(AstroPreviewEnergyPolicy.canCaptureLiveViewFrame(true, false, true));
        assertTrue(AstroPreviewEnergyPolicy.canRequestNextCaptureJpeg(true, true));
    }

    @Test
    public void cameraAccessAndIdleUsbAreRequiredForLiveView() {
        assertFalse(AstroPreviewEnergyPolicy.canCaptureLiveViewFrame(false, false, false));
        assertFalse(AstroPreviewEnergyPolicy.canCaptureLiveViewFrame(true, true, false));
    }
}

package com.camerae.eosrprobe;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class AstroPreviewEnergyPolicyTest {
    @Test
    public void firstCaptureDownloadsOneJpegForTheSessionThumbnail() {
        assertTrue(AstroPreviewEnergyPolicy.shouldDownloadNextJpeg(0, false));
        assertFalse(AstroPreviewEnergyPolicy.shouldDownloadNextJpeg(1, false));
        assertTrue(AstroPreviewEnergyPolicy.shouldDownloadNextJpeg(8, true));
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

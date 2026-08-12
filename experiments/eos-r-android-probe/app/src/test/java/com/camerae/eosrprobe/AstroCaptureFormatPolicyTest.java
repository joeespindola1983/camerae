package com.camerae.eosrprobe;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class AstroCaptureFormatPolicyTest {
    @Test
    public void selectableFormatsAlwaysIncludeJpegForPreviewAndThumbnail() {
        assertArrayEquals(
                new String[]{"JPG", "JPG+CR3"},
                AstroCaptureFormatPolicy.selectableFormats()
        );
    }

    @Test
    public void legacyRawOnlySessionKeepsRawByAddingJpeg() {
        assertEquals("JPG+CR3", AstroCaptureFormatPolicy.normalize("CR3"));
        assertEquals("JPG", AstroCaptureFormatPolicy.normalize("JPG"));
        assertEquals("JPG+CR3", AstroCaptureFormatPolicy.normalize("JPG+CR3"));
    }

    @Test
    public void unknownOrMissingFormatFallsBackToJpeg() {
        assertEquals("JPG", AstroCaptureFormatPolicy.normalize(null));
        assertEquals("JPG", AstroCaptureFormatPolicy.normalize("RAW+HEIF"));
    }
}

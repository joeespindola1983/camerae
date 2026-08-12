package com.camerae.eosrprobe;

final class AstroPreviewEnergyPolicy {
    private AstroPreviewEnergyPolicy() {}

    static boolean shouldDownloadNextJpeg(boolean explicitlyRequested) {
        return explicitlyRequested;
    }

    static boolean canCaptureLiveViewFrame(
            boolean cameraReady,
            boolean cameraBusy,
            boolean sequenceRunning
    ) {
        return cameraReady && !cameraBusy && !sequenceRunning;
    }

    static boolean canRequestNextCaptureJpeg(boolean cameraReady, boolean sequenceRunning) {
        return cameraReady && sequenceRunning;
    }
}

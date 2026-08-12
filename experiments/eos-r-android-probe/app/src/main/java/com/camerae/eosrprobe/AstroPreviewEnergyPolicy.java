package com.camerae.eosrprobe;

final class AstroPreviewEnergyPolicy {
    private AstroPreviewEnergyPolicy() {}

    static boolean shouldDownloadNextJpeg(int completedCaptures, boolean explicitlyRequested) {
        return completedCaptures == 0 || explicitlyRequested;
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

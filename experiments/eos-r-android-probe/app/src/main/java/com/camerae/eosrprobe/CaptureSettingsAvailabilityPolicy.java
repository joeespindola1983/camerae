package com.camerae.eosrprobe;

final class CaptureSettingsAvailabilityPolicy {
    enum State {
        READY(true),
        CAMERA_MISSING(false),
        USB_PERMISSION_REQUIRED(false),
        UNSUPPORTED_CAMERA(false),
        CAMERA_BUSY(false),
        SESSION_FINALIZED(false);

        private final boolean enabled;

        State(boolean enabled) {
            this.enabled = enabled;
        }

        boolean isEnabled() {
            return enabled;
        }
    }

    private CaptureSettingsAvailabilityPolicy() {}

    static State evaluate(
            boolean cameraPresent,
            boolean usbAuthorized,
            boolean supportedCamera,
            boolean cameraBusy,
            boolean sessionFinalized
    ) {
        if (sessionFinalized) return State.SESSION_FINALIZED;
        if (!cameraPresent) return State.CAMERA_MISSING;
        if (!usbAuthorized) return State.USB_PERMISSION_REQUIRED;
        if (!supportedCamera) return State.UNSUPPORTED_CAMERA;
        if (cameraBusy) return State.CAMERA_BUSY;
        return State.READY;
    }
}

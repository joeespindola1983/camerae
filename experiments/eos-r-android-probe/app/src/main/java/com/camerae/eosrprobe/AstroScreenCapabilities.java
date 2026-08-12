package com.camerae.eosrprobe;

import java.util.EnumSet;
import java.util.Set;

final class AstroScreenCapabilities {
    enum Capability {
        IDENTIFY_APP_VERSION,
        CREATE_SESSION,
        OPEN_SESSION,
        DELETE_SESSION,
        ADJUST_EXPOSURE,
        START_SESSION,
        PAUSE_SESSION,
        FINALIZE_SESSION,
        CAPTURE_LIVE_VIEW_FRAME,
        REQUEST_NEXT_JPEG_PREVIEW,
        SHARE_CAPTURE_LOG
    }

    private AstroScreenCapabilities() {}

    static Set<Capability> sessionCatalog() {
        return EnumSet.of(
                Capability.IDENTIFY_APP_VERSION,
                Capability.CREATE_SESSION,
                Capability.OPEN_SESSION,
                Capability.DELETE_SESSION
        );
    }

    static Set<Capability> captureSession() {
        return EnumSet.of(
                Capability.IDENTIFY_APP_VERSION,
                Capability.ADJUST_EXPOSURE,
                Capability.START_SESSION,
                Capability.PAUSE_SESSION,
                Capability.FINALIZE_SESSION,
                Capability.CAPTURE_LIVE_VIEW_FRAME,
                Capability.REQUEST_NEXT_JPEG_PREVIEW,
                Capability.SHARE_CAPTURE_LOG
        );
    }
}

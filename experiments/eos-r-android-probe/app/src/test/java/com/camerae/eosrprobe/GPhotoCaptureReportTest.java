package com.camerae.eosrprobe;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.File;

import org.junit.Test;

public final class GPhotoCaptureReportTest {
    @Test
    public void keepsRemoteFilesAndQueuesOnlyUndownloadedJpegs() {
        AstroUsbSessionStore.Session session = new AstroUsbSessionStore.Session(
                new File("/tmp/session"),
                "session-test"
        );
        String report = "CAMERA|/store/DCIM/100CANON|IMG_0001.JPG\n"
                + "CAMERA|/store/DCIM/100CANON|IMG_0001.CR3\n"
                + "FILE|/tmp/session/IMG_0001.JPG|image/jpeg\n"
                + "CAMERA|/store/DCIM/100CANON|IMG_0002.JPG\n";

        GPhotoCaptureReport.mergeIntoSession(report, session);

        assertEquals(3, session.cameraFiles.size());
        assertEquals(1, session.pendingJpegs.size());
        assertTrue(session.pendingJpegs.get(0).endsWith("IMG_0002.JPG"));
    }

    @Test
    public void returnsLatestDownloadedJpegForPreview() {
        String report = "FILE|/tmp/session/IMG_0001.JPG|image/jpeg\n"
                + "FILE|/tmp/session/IMG_0001.CR3|image/x-canon-cr3\n"
                + "FILE|/tmp/session/IMG_0002.jpeg|image/jpeg\n";

        assertEquals(
                "/tmp/session/IMG_0002.jpeg",
                GPhotoCaptureReport.latestDownloadedJpeg(report)
        );
    }
}

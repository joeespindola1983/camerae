package com.camerae.eosrprobe;

import java.io.File;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

final class GPhotoCaptureReport {
    private GPhotoCaptureReport() {}

    static void mergeIntoSession(String report, AstroUsbSessionStore.Session session) {
        Set<String> downloadedNames = downloadedFileNames(report);
        for (String line : report.split("\\n")) {
            if (!line.startsWith("CAMERA|")) continue;
            String[] components = line.split("\\|", 3);
            if (components.length < 3) continue;
            String cameraFile = components[1] + "|" + components[2];
            if (!session.cameraFiles.contains(cameraFile)) session.cameraFiles.add(cameraFile);
            if (isJpegName(components[2])
                    && !downloadedNames.contains(components[2])
                    && !session.pendingJpegs.contains(cameraFile)) {
                session.pendingJpegs.add(cameraFile);
            }
        }
    }

    static String latestDownloadedJpeg(String report) {
        String latest = null;
        for (String line : report.split("\\n")) {
            if (!line.startsWith("FILE|")) continue;
            String[] components = line.split("\\|", 3);
            if (components.length < 2 || !isJpegName(components[1])) continue;
            latest = components[1];
        }
        return latest;
    }

    private static Set<String> downloadedFileNames(String report) {
        Set<String> names = new HashSet<>();
        for (String line : report.split("\\n")) {
            if (!line.startsWith("FILE|")) continue;
            String[] components = line.split("\\|", 3);
            if (components.length >= 2) names.add(new File(components[1]).getName());
        }
        return names;
    }

    private static boolean isJpegName(String name) {
        String lower = name.toLowerCase(Locale.US);
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg");
    }
}

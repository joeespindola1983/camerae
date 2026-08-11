package com.camerae.eosrprobe;

import android.hardware.usb.UsbDevice;
import android.util.AtomicFile;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class AstroSequenceManifest {
    private final AtomicFile atomicFile;
    private final JSONObject document;
    private final JSONArray shots;

    private AstroSequenceManifest(AtomicFile atomicFile, JSONObject document, JSONArray shots) {
        this.atomicFile = atomicFile;
        this.document = document;
        this.shots = shots;
    }

    static AstroSequenceManifest create(
            File cameraDownloadDirectory,
            UsbDevice device,
            int photoCount,
            int initialDelaySeconds,
            int intervalSeconds
    ) throws IOException {
        String sequenceId = "sequence_" + new SimpleDateFormat(
                "yyyyMMdd_HHmmss_SSS",
                Locale.US
        ).format(new Date());
        File sequenceDirectory = new File(cameraDownloadDirectory, sequenceId);
        if (!sequenceDirectory.mkdirs() && !sequenceDirectory.isDirectory()) {
            throw new IOException("Não foi possível criar " + sequenceDirectory);
        }

        JSONArray shots = new JSONArray();
        JSONObject root = new JSONObject();
        try {
            root.put("schemaVersion", 1);
            root.put("sequenceId", sequenceId);
            root.put("status", "running");
            root.put("createdAt", isoTimestamp(System.currentTimeMillis()));
            root.put("appVersion", BuildConfig.VERSION_NAME);
            root.put("appBuild", BuildConfig.VERSION_CODE);

            JSONObject camera = new JSONObject();
            camera.put("vendorId", String.format(Locale.US, "0x%04X", device.getVendorId()));
            camera.put("productId", String.format(Locale.US, "0x%04X", device.getProductId()));
            camera.put("manufacturer", nullable(device.getManufacturerName()));
            camera.put("product", nullable(device.getProductName()));
            root.put("camera", camera);

            JSONObject plan = new JSONObject();
            plan.put("photoCount", photoCount);
            plan.put("initialDelaySeconds", initialDelaySeconds);
            plan.put("startIntervalSeconds", intervalSeconds);
            plan.put("scheduleSemantics", "start-to-start; serial; never overlaps");
            root.put("plan", plan);
            root.put("shots", shots);
        } catch (JSONException error) {
            throw new IOException("Não foi possível iniciar o manifesto JSON", error);
        }

        AstroSequenceManifest manifest = new AstroSequenceManifest(
                new AtomicFile(new File(sequenceDirectory, "manifest.json")),
                root,
                shots
        );
        manifest.save();
        return manifest;
    }

    File sequenceDirectory() {
        return atomicFile.getBaseFile().getParentFile();
    }

    String path() {
        return atomicFile.getBaseFile().getAbsolutePath();
    }

    void recordSuccess(
            int captureNumber,
            long scheduledAtMillis,
            long startedAtMillis,
            long completedAtMillis,
            int handle,
            int storageId,
            String cameraFileName,
            long cameraSize,
            File downloadedFile
    ) throws IOException {
        try {
            JSONObject shot = baseShot(
                    captureNumber,
                    scheduledAtMillis,
                    startedAtMillis,
                    completedAtMillis
            );
            shot.put("status", "downloaded");
            shot.put("handle", Integer.toUnsignedString(handle));
            shot.put("storageId", String.format(Locale.US, "0x%08X", storageId));
            shot.put("cameraFileName", cameraFileName);
            shot.put("cameraBytes", cameraSize);
            shot.put("localPath", downloadedFile.getAbsolutePath());
            shot.put("localBytes", downloadedFile.length());
            shot.put("byteCountVerified", cameraSize <= 0 || cameraSize == downloadedFile.length());
            shots.put(shot);
            document.put("completedCount", shots.length());
            document.put("updatedAt", isoTimestamp(completedAtMillis));
            save();
        } catch (JSONException error) {
            throw new IOException("Não foi possível registrar a captura no manifesto", error);
        }
    }

    void recordFailure(
            int captureNumber,
            long scheduledAtMillis,
            long startedAtMillis,
            long completedAtMillis,
            String message
    ) throws IOException {
        try {
            JSONObject shot = baseShot(
                    captureNumber,
                    scheduledAtMillis,
                    startedAtMillis,
                    completedAtMillis
            );
            shot.put("status", "failed");
            shot.put("error", message);
            shots.put(shot);
            document.put("status", "failed");
            document.put("updatedAt", isoTimestamp(completedAtMillis));
            save();
        } catch (JSONException error) {
            throw new IOException("Não foi possível registrar a falha no manifesto", error);
        }
    }

    void finish(String status, int completedCount) throws IOException {
        try {
            document.put("status", status);
            document.put("completedCount", completedCount);
            document.put("finishedAt", isoTimestamp(System.currentTimeMillis()));
            save();
        } catch (JSONException error) {
            throw new IOException("Não foi possível finalizar o manifesto", error);
        }
    }

    private static JSONObject baseShot(
            int captureNumber,
            long scheduledAtMillis,
            long startedAtMillis,
            long completedAtMillis
    ) throws JSONException {
        JSONObject shot = new JSONObject();
        shot.put("index", captureNumber);
        shot.put("scheduledAt", isoTimestamp(scheduledAtMillis));
        shot.put("startedAt", isoTimestamp(startedAtMillis));
        shot.put("completedAt", isoTimestamp(completedAtMillis));
        shot.put("durationMillis", Math.max(0, completedAtMillis - startedAtMillis));
        shot.put("startDelayMillis", startedAtMillis - scheduledAtMillis);
        return shot;
    }

    private void save() throws IOException {
        FileOutputStream output = null;
        try {
            output = atomicFile.startWrite();
            output.write(document.toString(2).getBytes(StandardCharsets.UTF_8));
            atomicFile.finishWrite(output);
        } catch (JSONException | IOException error) {
            if (output != null) {
                atomicFile.failWrite(output);
            }
            if (error instanceof IOException) {
                throw (IOException) error;
            }
            throw new IOException("Não foi possível serializar o manifesto", error);
        }
    }

    private static String isoTimestamp(long timeMillis) {
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)
                .format(new Date(timeMillis));
    }

    private static String nullable(String value) {
        return value == null ? "" : value;
    }
}

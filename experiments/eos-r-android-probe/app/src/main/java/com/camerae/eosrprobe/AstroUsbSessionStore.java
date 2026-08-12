package com.camerae.eosrprobe;

import android.util.AtomicFile;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;

final class AstroUsbSessionStore {
    private static final String MANIFEST_NAME = "session.json";

    static final class Session {
        final File directory;
        final String id;
        String title;
        long createdAtMillis;
        long updatedAtMillis;
        String status;
        int captureCount;
        String iso;
        String whiteBalance;
        String format;
        int bulbSeconds;
        int intervalSeconds;
        final List<String> cameraFiles = new ArrayList<>();
        final List<String> pendingJpegs = new ArrayList<>();

        Session(File directory, String id) {
            this.directory = directory;
            this.id = id;
        }

        File manifestFile() {
            return new File(directory, MANIFEST_NAME);
        }
    }

    private AstroUsbSessionStore() {}

    static Session create(File root) throws IOException {
        if (!root.isDirectory() && !root.mkdirs()) {
            throw new IOException("Não foi possível criar " + root);
        }
        long now = System.currentTimeMillis();
        String id = "session-" + new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
                .format(new Date(now));
        File directory = new File(root, id);
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Não foi possível criar " + directory);
        }
        Session session = new Session(directory, id);
        session.title = "Sessão Astro " + new SimpleDateFormat("dd MMM · HH:mm", Locale.getDefault())
                .format(new Date(now));
        session.createdAtMillis = now;
        session.updatedAtMillis = now;
        session.status = "draft";
        session.iso = "6400";
        session.whiteBalance = "Color Temperature";
        session.format = "JPG";
        session.bulbSeconds = 5;
        session.intervalSeconds = 10;
        save(session);
        return session;
    }

    static List<Session> list(File root) {
        List<Session> sessions = new ArrayList<>();
        File[] directories = root.listFiles(File::isDirectory);
        if (directories == null) return sessions;
        for (File directory : directories) {
            if (!directory.getName().startsWith("session-")) continue;
            try {
                sessions.add(load(directory));
            } catch (IOException ignored) {
                sessions.add(legacySession(directory));
            }
        }
        sessions.sort(Comparator.comparingLong((Session value) -> value.updatedAtMillis).reversed());
        return sessions;
    }

    static Session load(File directory) throws IOException {
        File manifest = new File(directory, MANIFEST_NAME);
        if (!manifest.isFile()) return legacySession(directory);
        try {
            byte[] bytes = new byte[(int) manifest.length()];
            try (FileInputStream input = new FileInputStream(manifest)) {
                int offset = 0;
                while (offset < bytes.length) {
                    int count = input.read(bytes, offset, bytes.length - offset);
                    if (count < 0) break;
                    offset += count;
                }
                if (offset != bytes.length) throw new IOException("Manifesto incompleto");
            }
            JSONObject root = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
            Session session = new Session(directory, root.optString("id", directory.getName()));
            session.title = root.optString("title", directory.getName());
            session.createdAtMillis = root.optLong("createdAtMillis", directory.lastModified());
            session.updatedAtMillis = root.optLong("updatedAtMillis", directory.lastModified());
            session.status = root.optString("status", "paused");
            session.captureCount = root.optInt("captureCount", 0);
            session.iso = root.optString("iso", "6400");
            session.whiteBalance = root.optString("whiteBalance", "Color Temperature");
            session.format = root.optString("format", "JPG");
            session.bulbSeconds = root.optInt("bulbSeconds", 5);
            session.intervalSeconds = root.optInt("intervalSeconds", 10);
            readStrings(root.optJSONArray("cameraFiles"), session.cameraFiles);
            readStrings(root.optJSONArray("pendingJpegs"), session.pendingJpegs);
            return session;
        } catch (JSONException error) {
            throw new IOException("Manifesto de sessão inválido", error);
        }
    }

    static void save(Session session) throws IOException {
        session.updatedAtMillis = System.currentTimeMillis();
        JSONObject root = new JSONObject();
        try {
            root.put("schemaVersion", 1);
            root.put("id", session.id);
            root.put("title", session.title);
            root.put("createdAtMillis", session.createdAtMillis);
            root.put("updatedAtMillis", session.updatedAtMillis);
            root.put("status", session.status);
            root.put("captureCount", session.captureCount);
            root.put("iso", session.iso);
            root.put("whiteBalance", session.whiteBalance);
            root.put("format", session.format);
            root.put("bulbSeconds", session.bulbSeconds);
            root.put("intervalSeconds", session.intervalSeconds);
            root.put("cameraFiles", new JSONArray(session.cameraFiles));
            root.put("pendingJpegs", new JSONArray(session.pendingJpegs));
        } catch (JSONException error) {
            throw new IOException("Não foi possível serializar a sessão", error);
        }
        AtomicFile atomicFile = new AtomicFile(session.manifestFile());
        FileOutputStream output = null;
        try {
            output = atomicFile.startWrite();
            output.write(root.toString(2).getBytes(StandardCharsets.UTF_8));
            atomicFile.finishWrite(output);
        } catch (JSONException | IOException error) {
            if (output != null) atomicFile.failWrite(output);
            throw error instanceof IOException
                    ? (IOException) error
                    : new IOException("Não foi possível salvar a sessão", error);
        }
    }

    static boolean delete(Session session) {
        return deleteTree(session.directory);
    }

    static File latestLocalJpeg(Session session) {
        File[] files = session.directory.listFiles(file -> {
            String lower = file.getName().toLowerCase(Locale.US);
            return file.isFile() && (lower.endsWith(".jpg") || lower.endsWith(".jpeg"));
        });
        if (files == null || files.length == 0) return null;
        java.util.Arrays.sort(files, Comparator.comparingLong(File::lastModified).reversed());
        return files[0];
    }

    private static Session legacySession(File directory) {
        Session session = new Session(directory, directory.getName());
        long time = directory.lastModified();
        session.title = "Sessão Astro " + new SimpleDateFormat("dd MMM · HH:mm", Locale.getDefault())
                .format(new Date(time));
        session.createdAtMillis = time;
        session.updatedAtMillis = time;
        session.status = "finalized";
        session.iso = "—";
        session.whiteBalance = "—";
        session.format = "JPG";
        session.bulbSeconds = 5;
        session.intervalSeconds = 10;
        File[] images = directory.listFiles(file -> {
            String lower = file.getName().toLowerCase(Locale.US);
            return lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".cr3");
        });
        session.captureCount = images == null ? 0 : images.length;
        return session;
    }

    private static void readStrings(JSONArray values, List<String> destination) {
        if (values == null) return;
        for (int index = 0; index < values.length(); index++) {
            String value = values.optString(index, "");
            if (!value.isEmpty()) destination.add(value);
        }
    }

    private static boolean deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) if (!deleteTree(child)) return false;
        }
        return file.delete();
    }
}

package com.camerae.eosrprobe;

import android.content.Context;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class PersistentProbeLog {
    private static final Object LOCK = new Object();
    private static final int MAX_SNAPSHOT_BYTES = 64 * 1024;
    private static File currentFile;
    private static File previousFile;
    private static boolean initialized;

    private PersistentProbeLog() {
    }

    static void initialize(Context context) {
        synchronized (LOCK) {
            if (initialized) {
                return;
            }
            File directory = new File(context.getFilesDir(), "diagnostics");
            if (!directory.mkdirs() && !directory.isDirectory()) {
                return;
            }
            currentFile = new File(directory, "ptp-current.log");
            previousFile = new File(directory, "ptp-previous.log");
            if (currentFile.isFile()) {
                if (previousFile.isFile() && !previousFile.delete()) {
                    return;
                }
                if (!currentFile.renameTo(previousFile)) {
                    return;
                }
            }
            initialized = true;
            appendLocked("SESSION", "Processo iniciado: " + BuildConfig.VERSION_NAME
                    + " (build " + BuildConfig.VERSION_CODE + ")");
        }
    }

    static void append(String category, String message) {
        synchronized (LOCK) {
            if (!initialized || currentFile == null) {
                return;
            }
            appendLocked(category, message);
        }
    }

    static String snapshot() {
        synchronized (LOCK) {
            if (!initialized) {
                return "Diagnóstico persistente indisponível.\n";
            }
            StringBuilder output = new StringBuilder();
            output.append("SESSÃO ANTERIOR (preservada após reinício)\n");
            output.append(readTail(previousFile));
            output.append("\nSESSÃO ATUAL (gravada durante cada comando)\n");
            output.append(readTail(currentFile));
            return output.toString();
        }
    }

    private static void appendLocked(String category, String message) {
        String line = '[' + timestamp() + "] [" + category + "] " + message + '\n';
        try (FileOutputStream output = new FileOutputStream(currentFile, true)) {
            output.write(line.getBytes(StandardCharsets.UTF_8));
        } catch (IOException ignored) {
            // Diagnostics must never interfere with camera cleanup.
        }
    }

    private static String readTail(File file) {
        if (file == null || !file.isFile()) {
            return "<nenhuma sessão preservada>\n";
        }
        long length = file.length();
        int count = (int) Math.min(length, MAX_SNAPSHOT_BYTES);
        byte[] bytes = new byte[count];
        try (FileInputStream input = new FileInputStream(file)) {
            long toSkip = Math.max(0, length - count);
            while (toSkip > 0) {
                long skipped = input.skip(toSkip);
                if (skipped <= 0) {
                    break;
                }
                toSkip -= skipped;
            }
            int offset = 0;
            while (offset < count) {
                int read = input.read(bytes, offset, count - offset);
                if (read < 0) {
                    break;
                }
                offset += read;
            }
            return new String(bytes, 0, offset, StandardCharsets.UTF_8);
        } catch (IOException error) {
            return "<falha ao ler diagnóstico: " + error.getMessage() + ">\n";
        }
    }

    private static String timestamp() {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(new Date());
    }
}

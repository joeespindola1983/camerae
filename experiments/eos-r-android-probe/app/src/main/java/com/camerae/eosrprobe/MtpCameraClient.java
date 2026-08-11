package com.camerae.eosrprobe;

import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.mtp.MtpConstants;
import android.mtp.MtpDevice;
import android.mtp.MtpDeviceInfo;
import android.mtp.MtpObjectInfo;
import android.mtp.MtpStorageInfo;
import android.os.SystemClock;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

final class MtpCameraClient {
    private static final int MAX_OBJECTS = 10_000;
    private static final int MAX_FOLDERS = 1_000;
    private static final int MAX_REPORTED_FILES = 30;
    private static final long NEW_IMAGE_POLL_INTERVAL_MS = 500;

    private MtpCameraClient() {
    }

    static Result inspect(
            UsbManager usbManager,
            UsbDevice usbDevice,
            File downloadDirectory,
            boolean downloadLatest
    ) throws ProbeException {
        UsbDeviceConnection connection = null;
        MtpDevice mtpDevice = null;
        StringBuilder report = new StringBuilder();

        try {
            connection = usbManager.openDevice(usbDevice);
            if (connection == null) {
                throw new ProbeException("UsbManager.openDevice retornou null");
            }

            mtpDevice = new MtpDevice(usbDevice);
            boolean opened = mtpDevice.open(connection);
            connection = null;
            if (!opened) {
                throw new ProbeException("MtpDevice.open falhou");
            }

            report.append("SESSÃO MTP/PTP\n");
            appendDeviceInfo(report, mtpDevice.getDeviceInfo());

            int[] storageIds = mtpDevice.getStorageIds();
            if (storageIds == null) {
                throw new ProbeException("A câmera não retornou a lista de storages");
            }
            report.append("Storages encontrados: ").append(storageIds.length).append("\n\n");

            List<Candidate> candidates = new ArrayList<>();
            int totalObjects = 0;
            int totalFolders = 0;
            for (int storageId : storageIds) {
                MtpStorageInfo storage = mtpDevice.getStorageInfo(storageId);
                appendStorageInfo(report, storageId, storage);
                ScanResult scan = scanStorage(mtpDevice, storageId);
                totalObjects += scan.objectCount;
                totalFolders += scan.folderCount;
                candidates.addAll(scan.candidates);
                report.append("  Pastas percorridas: ").append(scan.folderCount).append('\n');
                report.append("  Arquivos encontrados: ").append(scan.objectCount).append('\n');
                report.append("  Imagens candidatas: ").append(scan.candidates.size()).append("\n\n");
            }

            candidates.sort(Candidate.NEWEST_FIRST);
            report.append("RESUMO DO CARTÃO\n");
            report.append("Pastas: ").append(totalFolders).append('\n');
            report.append("Arquivos: ").append(totalObjects).append('\n');
            report.append("JPG/CR3 encontrados: ").append(candidates.size()).append('\n');
            appendCandidates(report, candidates);

            File downloadedFile = null;
            if (downloadLatest) {
                Candidate candidate = firstDownloadCandidate(candidates);
                if (candidate == null) {
                    throw new ProbeException("Nenhum JPG, JPEG ou CR3 foi encontrado no cartão");
                }
                downloadedFile = importObject(mtpDevice, candidate, downloadDirectory);
                report.append("\nDOWNLOAD\n");
                report.append("Handle: ").append(candidate.handle).append('\n');
                report.append("Origem: ").append(candidate.name).append('\n');
                report.append("Destino: ").append(downloadedFile.getAbsolutePath()).append('\n');
                report.append("Bytes gravados: ").append(downloadedFile.length()).append('\n');
            }
            return new Result(report.toString(), downloadedFile, totalObjects, candidates.size());
        } catch (ProbeException error) {
            throw error;
        } catch (RuntimeException error) {
            throw new ProbeException(error.getClass().getSimpleName() + ": " + error.getMessage(), error);
        } finally {
            if (mtpDevice != null) {
                mtpDevice.close();
            }
            if (connection != null) {
                connection.close();
            }
        }
    }

    static AutoImportResult waitForCapturedObjectAndDownload(
            UsbManager usbManager,
            UsbDevice usbDevice,
            CanonEosEventParser.CapturedObject expected,
            File downloadDirectory,
            long timeoutMs
    ) throws ProbeException {
        long startedAt = SystemClock.elapsedRealtime();
        long deadline = startedAt + timeoutMs;
        int attempts = 0;
        String lastTransientError = null;

        while (SystemClock.elapsedRealtime() <= deadline) {
            attempts++;
            UsbDeviceConnection connection = null;
            MtpDevice mtpDevice = null;
            try {
                connection = usbManager.openDevice(usbDevice);
                if (connection == null) {
                    lastTransientError = "UsbManager.openDevice retornou null";
                } else {
                    mtpDevice = new MtpDevice(usbDevice);
                    boolean opened = mtpDevice.open(connection);
                    connection = null;
                    if (!opened) {
                        lastTransientError = "MtpDevice.open falhou após a sessão PTP";
                    } else {
                        MtpObjectInfo info = mtpDevice.getObjectInfo(expected.handle);
                        if (info == null) {
                            lastTransientError = "handle ainda não visível via MTP";
                        } else if (!isImageCandidate(info)) {
                            throw new ProbeException("Handle capturado não é uma imagem: format="
                                    + hex4(info.getFormat()));
                        } else {
                            Candidate candidate = new Candidate(
                                    expected.handle,
                                    value(info.getName()),
                                    info.getFormat(),
                                    info.getCompressedSizeLong(),
                                    info.getDateCreated(),
                                    info.getDateModified()
                            );
                            File downloaded = importObject(mtpDevice, candidate, downloadDirectory);
                            long elapsed = SystemClock.elapsedRealtime() - startedAt;
                            StringBuilder report = new StringBuilder();
                            report.append("IMPORTAÇÃO PELO EVENTO CANON ObjectAddedEx/64\n");
                            report.append("Tentativas MTP: ").append(attempts).append('\n');
                            report.append("Tempo até importação: ").append(elapsed).append(" ms\n");
                            report.append("Handle do evento: ").append(expected.handle).append('\n');
                            report.append("Nome do evento: ").append(expected.name).append('\n');
                            report.append("Tamanho do evento: ").append(expected.size).append(" bytes\n");
                            report.append("Nome MTP: ").append(candidate.name).append('\n');
                            report.append("Tamanho MTP: ").append(candidate.size).append(" bytes\n");
                            report.append("Destino: ").append(downloaded.getAbsolutePath()).append('\n');
                            report.append("Bytes gravados: ").append(downloaded.length()).append('\n');
                            return new AutoImportResult(
                                    report.toString(),
                                    downloaded,
                                    candidate.name
                            );
                        }
                    }
                }
            } catch (RuntimeException error) {
                lastTransientError = error.getClass().getSimpleName() + ": " + error.getMessage();
            } finally {
                if (mtpDevice != null) {
                    mtpDevice.close();
                }
                if (connection != null) {
                    connection.close();
                }
            }

            long remaining = deadline - SystemClock.elapsedRealtime();
            if (remaining > 0) {
                SystemClock.sleep(Math.min(NEW_IMAGE_POLL_INTERVAL_MS, remaining));
            }
        }
        throw new ProbeException("Timeout aguardando o handle " + expected.handle
                + " após " + timeoutMs + " ms; último estado: " + lastTransientError);
    }

    private static void appendDeviceInfo(StringBuilder report, MtpDeviceInfo info)
            throws ProbeException {
        if (info == null) {
            throw new ProbeException("MtpDeviceInfo indisponível");
        }
        report.append("Fabricante: ").append(value(info.getManufacturer())).append('\n');
        report.append("Modelo: ").append(value(info.getModel())).append('\n');
        report.append("Firmware: ").append(value(info.getVersion())).append('\n');
        report.append("Serial: ").append(value(info.getSerialNumber())).append('\n');
        appendCodes(report, "Operações suportadas", info.getOperationsSupported(), true);
        appendCodes(report, "Eventos suportados", info.getEventsSupported(), false);
        report.append('\n');
    }

    private static void appendCodes(
            StringBuilder report,
            String title,
            int[] codes,
            boolean operation
    ) {
        report.append(title).append(": ");
        if (codes == null || codes.length == 0) {
            report.append("<nenhum>\n");
            return;
        }
        report.append(codes.length).append('\n');
        for (int code : codes) {
            report.append("  ").append(hex4(code));
            String name = operation ? operationName(code) : eventName(code);
            if (name != null) {
                report.append(" ").append(name);
            } else if (code >= 0x9000) {
                report.append(" VENDOR_CANON");
            }
            report.append('\n');
        }
    }

    private static void appendStorageInfo(
            StringBuilder report,
            int storageId,
            MtpStorageInfo storage
    ) {
        report.append("STORAGE ").append(hex8(storageId)).append('\n');
        if (storage == null) {
            report.append("  Info indisponível\n\n");
            return;
        }
        report.append("  Descrição: ").append(value(storage.getDescription())).append('\n');
        report.append("  Volume: ").append(value(storage.getVolumeIdentifier())).append('\n');
        report.append("  Capacidade: ").append(formatBytes(storage.getMaxCapacity())).append('\n');
        report.append("  Livre: ").append(formatBytes(storage.getFreeSpace())).append('\n');
    }

    private static ScanResult scanStorage(MtpDevice device, int storageId) {
        ArrayDeque<Integer> folders = new ArrayDeque<>();
        Set<Integer> visitedFolders = new HashSet<>();
        Set<Integer> visitedObjects = new HashSet<>();
        List<Candidate> candidates = new ArrayList<>();
        folders.add(0);
        int objectCount = 0;
        int folderCount = 0;

        while (!folders.isEmpty()
                && objectCount < MAX_OBJECTS
                && folderCount < MAX_FOLDERS) {
            int parent = folders.removeFirst();
            int[] handles = device.getObjectHandles(storageId, 0, parent);
            if (handles == null) {
                continue;
            }
            for (int handle : handles) {
                if (!visitedObjects.add(handle)) {
                    continue;
                }
                MtpObjectInfo info = device.getObjectInfo(handle);
                if (info == null) {
                    continue;
                }
                if (info.getFormat() == MtpConstants.FORMAT_ASSOCIATION) {
                    if (visitedFolders.add(handle)) {
                        folders.addLast(handle);
                        folderCount++;
                    }
                    continue;
                }

                objectCount++;
                if (isImageCandidate(info)) {
                    candidates.add(new Candidate(
                            handle,
                            value(info.getName()),
                            info.getFormat(),
                            info.getCompressedSizeLong(),
                            info.getDateCreated(),
                            info.getDateModified()
                    ));
                }
                if (objectCount >= MAX_OBJECTS) {
                    break;
                }
            }
        }
        return new ScanResult(objectCount, folderCount, candidates);
    }

    private static boolean isImageCandidate(MtpObjectInfo info) {
        String name = value(info.getName()).toUpperCase(Locale.US);
        return info.getFormat() == MtpConstants.FORMAT_EXIF_JPEG
                || info.getFormat() == MtpConstants.FORMAT_JFIF
                || info.getFormat() == MtpConstants.FORMAT_DNG
                || name.endsWith(".JPG")
                || name.endsWith(".JPEG")
                || name.endsWith(".CR3");
    }

    private static void appendCandidates(StringBuilder report, List<Candidate> candidates) {
        int count = Math.min(candidates.size(), MAX_REPORTED_FILES);
        for (int index = 0; index < count; index++) {
            Candidate item = candidates.get(index);
            report.append("  [").append(index).append("] handle=").append(item.handle)
                    .append(" name=").append(item.name)
                    .append(" format=").append(hex4(item.format))
                    .append(" size=").append(formatBytes(item.size))
                    .append(" modified=").append(formatMtpDate(item.modified))
                    .append('\n');
        }
        if (candidates.size() > count) {
            report.append("  ... ").append(candidates.size() - count)
                    .append(" imagens omitidas do log\n");
        }
    }

    private static Candidate firstDownloadCandidate(List<Candidate> candidates) {
        for (Candidate candidate : candidates) {
            String name = candidate.name.toUpperCase(Locale.US);
            if (name.endsWith(".JPG") || name.endsWith(".JPEG")
                    || candidate.format == MtpConstants.FORMAT_EXIF_JPEG
                    || candidate.format == MtpConstants.FORMAT_JFIF) {
                return candidate;
            }
        }
        return candidates.isEmpty() ? null : candidates.get(0);
    }

    private static File importObject(
            MtpDevice device,
            Candidate candidate,
            File downloadDirectory
    ) throws ProbeException {
        if (!downloadDirectory.exists() && !downloadDirectory.mkdirs()) {
            throw new ProbeException("Não foi possível criar " + downloadDirectory);
        }
        String fileName = sanitize(candidate.name);
        File destination = new File(downloadDirectory, candidate.handle + "_" + fileName);
        if (!device.importFile(candidate.handle, destination.getAbsolutePath())) {
            throw new ProbeException("MtpDevice.importFile falhou para " + candidate.name);
        }
        if (!destination.isFile() || destination.length() == 0) {
            throw new ProbeException("O download terminou sem gerar um arquivo válido");
        }
        if (candidate.size > 0 && destination.length() != candidate.size) {
            throw new ProbeException("Arquivo importado incompleto: " + destination.length()
                    + "/" + candidate.size + " bytes em " + destination.getAbsolutePath());
        }
        return destination;
    }

    private static String sanitize(String name) {
        String cleaned = name.replaceAll("[^A-Za-z0-9._-]", "_");
        return cleaned.isEmpty() ? "camera_object.bin" : cleaned;
    }

    private static String operationName(int code) {
        switch (code) {
            case MtpConstants.OPERATION_GET_DEVICE_INFO:
                return "GET_DEVICE_INFO";
            case MtpConstants.OPERATION_OPEN_SESSION:
                return "OPEN_SESSION";
            case MtpConstants.OPERATION_CLOSE_SESSION:
                return "CLOSE_SESSION";
            case MtpConstants.OPERATION_GET_STORAGE_I_DS:
                return "GET_STORAGE_IDS";
            case MtpConstants.OPERATION_GET_STORAGE_INFO:
                return "GET_STORAGE_INFO";
            case MtpConstants.OPERATION_GET_OBJECT_HANDLES:
                return "GET_OBJECT_HANDLES";
            case MtpConstants.OPERATION_GET_OBJECT_INFO:
                return "GET_OBJECT_INFO";
            case MtpConstants.OPERATION_GET_OBJECT:
                return "GET_OBJECT";
            case MtpConstants.OPERATION_GET_THUMB:
                return "GET_THUMB";
            case MtpConstants.OPERATION_INITIATE_CAPTURE:
                return "INITIATE_CAPTURE";
            case MtpConstants.OPERATION_GET_DEVICE_PROP_DESC:
                return "GET_DEVICE_PROP_DESC";
            case MtpConstants.OPERATION_GET_DEVICE_PROP_VALUE:
                return "GET_DEVICE_PROP_VALUE";
            case MtpConstants.OPERATION_SET_DEVICE_PROP_VALUE:
                return "SET_DEVICE_PROP_VALUE";
            case MtpConstants.OPERATION_GET_PARTIAL_OBJECT:
                return "GET_PARTIAL_OBJECT";
            default:
                return null;
        }
    }

    private static String eventName(int code) {
        switch (code) {
            case 0x4002:
                return "OBJECT_ADDED";
            case 0x4003:
                return "OBJECT_REMOVED";
            case 0x4004:
                return "STORE_ADDED";
            case 0x4005:
                return "STORE_REMOVED";
            case 0x4006:
                return "DEVICE_PROP_CHANGED";
            case 0x400D:
                return "CAPTURE_COMPLETE";
            default:
                return null;
        }
    }

    private static String value(String value) {
        return value == null || value.isEmpty() ? "<indisponível>" : value;
    }

    private static String formatBytes(long bytes) {
        if (bytes < 0) {
            return "<indisponível>";
        }
        if (bytes >= 1024L * 1024L * 1024L) {
            return String.format(Locale.US, "%.2f GiB", bytes / (1024.0 * 1024.0 * 1024.0));
        }
        if (bytes >= 1024L * 1024L) {
            return String.format(Locale.US, "%.2f MiB", bytes / (1024.0 * 1024.0));
        }
        if (bytes >= 1024L) {
            return String.format(Locale.US, "%.2f KiB", bytes / 1024.0);
        }
        return bytes + " B";
    }

    private static String formatMtpDate(long value) {
        if (value <= 0) {
            return "<indisponível>";
        }
        long milliseconds = value < 1_000_000_000_000L ? value * 1000L : value;
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                .format(new Date(milliseconds));
    }

    private static String hex4(int value) {
        return String.format(Locale.US, "0x%04X", value & 0xFFFF);
    }

    private static String hex8(int value) {
        return String.format(Locale.US, "0x%08X", value);
    }

    static final class Result {
        final String report;
        final File downloadedFile;
        final int objectCount;
        final int imageCount;

        Result(String report, File downloadedFile, int objectCount, int imageCount) {
            this.report = report;
            this.downloadedFile = downloadedFile;
            this.objectCount = objectCount;
            this.imageCount = imageCount;
        }
    }

    static final class AutoImportResult {
        final String report;
        final File downloadedFile;
        final String cameraFileName;

        AutoImportResult(String report, File downloadedFile, String cameraFileName) {
            this.report = report;
            this.downloadedFile = downloadedFile;
            this.cameraFileName = cameraFileName;
        }
    }

    static final class ProbeException extends Exception {
        ProbeException(String message) {
            super(message);
        }

        ProbeException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    private static final class ScanResult {
        final int objectCount;
        final int folderCount;
        final List<Candidate> candidates;

        ScanResult(int objectCount, int folderCount, List<Candidate> candidates) {
            this.objectCount = objectCount;
            this.folderCount = folderCount;
            this.candidates = candidates;
        }
    }

    private static final class Candidate {
        static final Comparator<Candidate> NEWEST_FIRST = (left, right) -> {
            int byModified = Long.compare(right.modified, left.modified);
            if (byModified != 0) {
                return byModified;
            }
            int byCreated = Long.compare(right.created, left.created);
            return byCreated != 0 ? byCreated : Integer.compare(right.handle, left.handle);
        };

        final int handle;
        final String name;
        final int format;
        final long size;
        final long created;
        final long modified;

        Candidate(int handle, String name, int format, long size, long created, long modified) {
            this.handle = handle;
            this.name = name;
            this.format = format;
            this.size = size;
            this.created = created;
            this.modified = modified;
        }
    }
}

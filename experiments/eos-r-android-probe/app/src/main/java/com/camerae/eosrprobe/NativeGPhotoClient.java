package com.camerae.eosrprobe;

import android.content.Context;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

final class NativeGPhotoClient {
    static {
        System.loadLibrary("gphoto2_bridge");
    }

    private NativeGPhotoClient() {}

    static String probe(Context context, int fileDescriptor) throws IOException {
        File root = prepareModules(context);
        File camlibs = new File(root, "camlibs");
        File iolibs = new File(root, "iolibs");
        return nativeProbe(fileDescriptor, camlibs.getAbsolutePath(), iolibs.getAbsolutePath());
    }

    static String capture(
            Context context,
            int fileDescriptor,
            File outputDirectory,
            String iso,
            String whiteBalance,
            String format,
            int bulbSeconds,
            boolean downloadJpegPreview
    ) throws IOException {
        File root = prepareModules(context);
        File camlibs = new File(root, "camlibs");
        File iolibs = new File(root, "iolibs");
        if (!outputDirectory.isDirectory() && !outputDirectory.mkdirs()) {
            throw new IOException("Não foi possível criar " + outputDirectory);
        }
        return nativeCapture(
                fileDescriptor,
                camlibs.getAbsolutePath(),
                iolibs.getAbsolutePath(),
                outputDirectory.getAbsolutePath(),
                iso,
                whiteBalance,
                format,
                bulbSeconds,
                downloadJpegPreview
        );
    }

    static String captureLiveViewFrame(
            Context context,
            int fileDescriptor,
            File outputFile
    ) throws IOException {
        File root = prepareModules(context);
        File camlibs = new File(root, "camlibs");
        File iolibs = new File(root, "iolibs");
        File parent = outputFile.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("Não foi possível criar " + parent);
        }
        return nativeCaptureLiveViewFrame(
                fileDescriptor,
                camlibs.getAbsolutePath(),
                iolibs.getAbsolutePath(),
                outputFile.getAbsolutePath()
        );
    }

    static String downloadFiles(
            Context context,
            int fileDescriptor,
            File outputDirectory,
            String cameraFiles
    ) throws IOException {
        File root = prepareModules(context);
        File camlibs = new File(root, "camlibs");
        File iolibs = new File(root, "iolibs");
        if (!outputDirectory.isDirectory() && !outputDirectory.mkdirs()) {
            throw new IOException("Não foi possível criar " + outputDirectory);
        }
        return nativeDownloadFiles(
                fileDescriptor,
                camlibs.getAbsolutePath(),
                iolibs.getAbsolutePath(),
                outputDirectory.getAbsolutePath(),
                cameraFiles
        );
    }

    static String checkFiles(Context context, int fileDescriptor, String cameraFiles)
            throws IOException {
        File root = prepareModules(context);
        File camlibs = new File(root, "camlibs");
        File iolibs = new File(root, "iolibs");
        return nativeCheckFiles(
                fileDescriptor,
                camlibs.getAbsolutePath(),
                iolibs.getAbsolutePath(),
                cameraFiles
        );
    }

    private static File prepareModules(Context context) throws IOException {
        File root = new File(context.getFilesDir(), "gphoto2-modules/2.5.34");
        File camlibs = new File(root, "camlibs");
        File iolibs = new File(root, "iolibs");
        copyAsset(context, "gphoto/camlibs/ptp2.so", new File(camlibs, "ptp2.so"));
        copyAsset(context, "gphoto/iolibs/usb1.so", new File(iolibs, "usb1.so"));
        return root;
    }

    private static void copyAsset(Context context, String assetName, File target) throws IOException {
        File parent = target.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("Não foi possível criar " + parent);
        }
        try (InputStream input = context.getAssets().open(assetName);
             FileOutputStream output = new FileOutputStream(target, false)) {
            byte[] buffer = new byte[32 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            output.getFD().sync();
        }
        if (!target.setReadable(true, true) || !target.setExecutable(true, true)) {
            throw new IOException("Não foi possível preparar o módulo " + target.getName());
        }
    }

    private static native String nativeProbe(
            int fileDescriptor,
            String camlibDirectory,
            String iolibDirectory
    );

    private static native String nativeCapture(
            int fileDescriptor,
            String camlibDirectory,
            String iolibDirectory,
            String outputDirectory,
            String iso,
            String whiteBalance,
            String format,
            int bulbSeconds,
            boolean downloadJpegPreview
    );

    private static native String nativeCaptureLiveViewFrame(
            int fileDescriptor,
            String camlibDirectory,
            String iolibDirectory,
            String outputFile
    );

    private static native String nativeDownloadFiles(
            int fileDescriptor,
            String camlibDirectory,
            String iolibDirectory,
            String outputDirectory,
            String cameraFiles
    );

    private static native String nativeCheckFiles(
            int fileDescriptor,
            String camlibDirectory,
            String iolibDirectory,
            String cameraFiles
    );
}

package com.camerae.eosrprobe;

import android.app.Activity;
import android.app.PendingIntent;
import android.annotation.SuppressLint;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.SystemClock;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@SuppressLint("SetTextI18n")
public final class MainActivity extends Activity {
    static final String ACTION_USB_PERMISSION_RESULT =
            "com.camerae.eosrprobe.action.USB_PERMISSION_RESULT";
    private static final int CANON_VENDOR_ID = 0x04A9;
    private static final long NEW_IMAGE_TIMEOUT_MS = 30_000;
    private static final long PTP_TO_MTP_SETTLE_MS = 1_000;

    private final StringBuilder eventLog = new StringBuilder();
    private final ExecutorService cameraExecutor = Executors.newSingleThreadExecutor();
    private UsbManager usbManager;
    private TextView statusView;
    private TextView logView;
    private Button authorizeButton;
    private Button captureButton;
    private Button inspectMtpButton;
    private Button downloadLatestButton;
    private Button startSequenceButton;
    private Button cancelSequenceButton;
    private Button copyLogButton;
    private Button shareLogButton;
    private EditText sequenceCountInput;
    private EditText sequenceDelayInput;
    private EditText sequenceIntervalInput;
    private TextView sequenceProgressView;
    private ImageView previewView;
    private String mtpReport = "MTP/PTP ainda não consultado.\n";
    private String captureReport = "Captura remota ainda não testada.\n";
    private boolean cameraBusy;
    private volatile boolean sequenceRunning;
    private volatile boolean sequenceCancelRequested;
    private boolean receiverRegistered;

    private final BroadcastReceiver usbReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            UsbDevice device = readUsbDevice(intent);

            if (ACTION_USB_PERMISSION_RESULT.equals(action)) {
                boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
                appendEvent("Permissão USB " + (granted ? "concedida" : "negada")
                        + deviceSuffix(device));
                if (granted && device != null && usbManager.hasPermission(device)) {
                    probeOpenAndClose(device);
                }
                refreshProbe();
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) {
                appendEvent("Dispositivo conectado" + deviceSuffix(device));
                refreshProbe();
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                appendEvent("Dispositivo desconectado" + deviceSuffix(device));
                sequenceCancelRequested = true;
                mtpReport = "MTP/PTP desconectado.\n";
                captureReport = "Captura remota desconectada.\n";
                sequenceProgressView.setText("Sequência interrompida: câmera desconectada");
                previewView.setVisibility(View.GONE);
                refreshProbe();
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        ((TextView) findViewById(R.id.app_version)).setText(getString(
                R.string.version_format,
                BuildConfig.VERSION_NAME,
                BuildConfig.VERSION_CODE
        ));
        statusView = findViewById(R.id.status);
        logView = findViewById(R.id.log);
        authorizeButton = findViewById(R.id.authorize);
        captureButton = findViewById(R.id.capture_test);
        inspectMtpButton = findViewById(R.id.inspect_mtp);
        downloadLatestButton = findViewById(R.id.download_latest);
        startSequenceButton = findViewById(R.id.start_sequence);
        cancelSequenceButton = findViewById(R.id.cancel_sequence);
        copyLogButton = findViewById(R.id.copy_log);
        shareLogButton = findViewById(R.id.share_log);
        sequenceCountInput = findViewById(R.id.sequence_count);
        sequenceDelayInput = findViewById(R.id.sequence_delay);
        sequenceIntervalInput = findViewById(R.id.sequence_interval);
        sequenceProgressView = findViewById(R.id.sequence_progress);
        previewView = findViewById(R.id.preview);

        findViewById(R.id.refresh).setOnClickListener(view -> {
            appendEvent("Varredura manual solicitada");
            refreshProbe();
        });
        authorizeButton.setOnClickListener(view -> requestUsbPermission());
        captureButton.setOnClickListener(view -> runRemoteCapture());
        startSequenceButton.setOnClickListener(view -> startAstroSequence());
        cancelSequenceButton.setOnClickListener(view -> cancelAstroSequence());
        inspectMtpButton.setOnClickListener(view -> runMtpProbe(false));
        downloadLatestButton.setOnClickListener(view -> runMtpProbe(true));
        copyLogButton.setOnClickListener(view -> copyLog());
        shareLogButton.setOnClickListener(view -> shareLog());

        appendEvent("Aplicativo " + BuildConfig.VERSION_NAME + " iniciado em "
                + Build.MANUFACTURER + " " + Build.MODEL
                + ", Android " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")");
        handleLaunchIntent(getIntent());
        refreshProbe();
    }

    @Override
    @SuppressLint("InlinedApi")
    protected void onStart() {
        super.onStart();
        IntentFilter filter = new IntentFilter(ACTION_USB_PERMISSION_RESULT);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED);
        receiverRegistered = true;
        refreshProbe();
    }

    @Override
    protected void onStop() {
        if (receiverRegistered) {
            unregisterReceiver(usbReceiver);
            receiverRegistered = false;
        }
        super.onStop();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleLaunchIntent(intent);
        refreshProbe();
    }

    @Override
    protected void onDestroy() {
        sequenceCancelRequested = true;
        cameraExecutor.shutdownNow();
        super.onDestroy();
    }

    private void handleLaunchIntent(Intent intent) {
        if (intent != null && UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(intent.getAction())) {
            appendEvent("Aberto pelo Android após conexão USB" + deviceSuffix(readUsbDevice(intent)));
        }
    }

    private void refreshProbe() {
        if (usbManager == null) {
            statusView.setText(R.string.status_usb_service_missing);
            authorizeButton.setEnabled(false);
            captureButton.setEnabled(false);
            startSequenceButton.setEnabled(false);
            return;
        }

        boolean hasUsbHost = getPackageManager().hasSystemFeature(PackageManager.FEATURE_USB_HOST);
        UsbDevice selected = selectCamera();
        if (cameraBusy) {
            statusView.setText(R.string.status_reading_camera);
        } else if (!hasUsbHost) {
            statusView.setText(R.string.status_usb_host_missing);
        } else if (selected == null) {
            statusView.setText(R.string.status_waiting);
        } else if (usbManager.hasPermission(selected)) {
            statusView.setText(getString(R.string.status_ready, deviceLabel(selected)));
        } else {
            statusView.setText(getString(R.string.status_permission_required, deviceLabel(selected)));
        }
        boolean cameraReady = selected != null && usbManager.hasPermission(selected);
        authorizeButton.setEnabled(selected != null && !usbManager.hasPermission(selected) && !cameraBusy);
        captureButton.setEnabled(cameraReady && !cameraBusy);
        inspectMtpButton.setEnabled(cameraReady && !cameraBusy);
        downloadLatestButton.setEnabled(cameraReady && !cameraBusy);
        startSequenceButton.setEnabled(cameraReady && !cameraBusy);
        cancelSequenceButton.setEnabled(sequenceRunning && !sequenceCancelRequested);
        sequenceCountInput.setEnabled(!cameraBusy);
        sequenceDelayInput.setEnabled(!cameraBusy);
        sequenceIntervalInput.setEnabled(!cameraBusy);
        copyLogButton.setEnabled(!cameraBusy);
        shareLogButton.setEnabled(!cameraBusy);

        StringBuilder report = new StringBuilder();
        report.append("CAMERAE EOS R USB PROBE\n");
        report.append("Gerado: ").append(timestamp()).append('\n');
        report.append("App: ").append(BuildConfig.VERSION_NAME)
                .append(" (code ").append(BuildConfig.VERSION_CODE).append(")\n");
        report.append("Aparelho: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n');
        report.append("Android: ").append(Build.VERSION.RELEASE)
                .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        report.append("USB Host declarado pelo aparelho: ").append(hasUsbHost).append("\n\n");
        report.append("EVENTOS\n").append(eventLog).append('\n');
        report.append(UsbTopologyFormatter.describe(usbManager));
        report.append('\n').append(captureReport);
        report.append('\n').append(mtpReport);
        logView.setText(report.toString());
    }

    private void runRemoteCapture() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) {
            appendEvent("Captura não iniciada: câmera ausente ou sem permissão USB");
            refreshProbe();
            return;
        }

        cameraBusy = true;
        appendEvent("Iniciando captura e importação automática; use foco manual");
        sequenceProgressView.setText("Captura única em andamento…");
        refreshProbe();
        File destination = downloadDirectory();
        cameraExecutor.execute(() -> {
            try {
                CaptureFlowResult result = performCaptureAndImport(device, destination);
                runOnUiThread(() -> {
                    cameraBusy = false;
                    captureReport = result.captureReport;
                    mtpReport = result.importReport;
                    sequenceProgressView.setText("Captura única concluída: " + result.cameraFileName);
                    appendEvent("Captura e download concluídos: " + result.cameraFileName);
                    showPreview(result.downloadedFile);
                    refreshProbe();
                });
            } catch (CaptureFlowException error) {
                runOnUiThread(() -> {
                    cameraBusy = false;
                    captureReport = error.captureReport;
                    mtpReport = error.importReport;
                    sequenceProgressView.setText("Captura única falhou: " + error.getMessage());
                    appendEvent("Captura/importação falhou: " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private void startAstroSequence() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) {
            appendEvent("Sequência não iniciada: câmera ausente ou sem permissão USB");
            refreshProbe();
            return;
        }

        Integer photoCount = readSequenceValue(sequenceCountInput, 1, 100, "Fotos");
        Integer initialDelaySeconds = readSequenceValue(
                sequenceDelayInput, 0, 3600, "Atraso"
        );
        Integer intervalSeconds = readSequenceValue(
                sequenceIntervalInput, 1, 86400, "Intervalo"
        );
        if (photoCount == null || initialDelaySeconds == null || intervalSeconds == null) {
            return;
        }

        cameraBusy = true;
        sequenceRunning = true;
        sequenceCancelRequested = false;
        appendEvent("Sequência astro iniciada: fotos=" + photoCount
                + " atraso=" + initialDelaySeconds + "s intervalo=" + intervalSeconds + "s");
        sequenceProgressView.setText("Preparando sequência de " + photoCount + " fotos…");
        refreshProbe();

        File destination = downloadDirectory();
        long initialDelayMs = initialDelaySeconds * 1000L;
        long intervalMs = intervalSeconds * 1000L;
        cameraExecutor.execute(() -> {
            long firstCaptureAt = SystemClock.elapsedRealtime() + initialDelayMs;
            int completed = 0;
            for (int index = 0; index < photoCount; index++) {
                long scheduledAt = firstCaptureAt + index * intervalMs;
                if (!waitUntilOrCanceled(scheduledAt)) {
                    break;
                }

                int captureNumber = index + 1;
                runOnUiThread(() -> {
                    sequenceProgressView.setText("Capturando " + captureNumber + "/" + photoCount + "…");
                    refreshProbe();
                });

                CaptureFlowResult result;
                try {
                    result = performCaptureAndImport(device, destination);
                } catch (CaptureFlowException error) {
                    runOnUiThread(() -> finishSequenceWithError(captureNumber, error));
                    return;
                }

                completed++;
                int completedCount = completed;
                runOnUiThread(() -> {
                    captureReport = result.captureReport;
                    mtpReport = result.importReport;
                    sequenceProgressView.setText("Concluídas " + completedCount + "/"
                            + photoCount + " • última: " + result.cameraFileName);
                    appendEvent("Sequência " + completedCount + "/" + photoCount
                            + " concluída: " + result.cameraFileName);
                    showPreview(result.downloadedFile);
                    refreshProbe();
                });
            }

            int finalCompleted = completed;
            boolean canceled = sequenceCancelRequested;
            runOnUiThread(() -> {
                cameraBusy = false;
                sequenceRunning = false;
                sequenceCancelRequested = false;
                if (canceled) {
                    sequenceProgressView.setText("Sequência cancelada: " + finalCompleted
                            + "/" + photoCount + " concluídas");
                    appendEvent("Sequência cancelada após " + finalCompleted + "/"
                            + photoCount + " capturas");
                } else {
                    sequenceProgressView.setText("Sequência concluída: " + finalCompleted
                            + "/" + photoCount);
                    appendEvent("Sequência astro concluída: " + finalCompleted + "/"
                            + photoCount + " capturas baixadas");
                }
                refreshProbe();
            });
        });
    }

    private void cancelAstroSequence() {
        if (!sequenceRunning) {
            return;
        }
        sequenceCancelRequested = true;
        sequenceProgressView.setText("Cancelamento solicitado; aguardando operação atual…");
        appendEvent("Cancelamento da sequência solicitado");
        refreshProbe();
    }

    private CaptureFlowResult performCaptureAndImport(UsbDevice device, File destination)
            throws CaptureFlowException {
        CanonEosRemoteClient.Result capture;
        try {
            capture = CanonEosRemoteClient.capture(usbManager, device);
        } catch (CanonEosRemoteClient.CaptureException error) {
            throw new CaptureFlowException(
                    "captura remota: " + error.getMessage(),
                    error.report,
                    "IMPORTAÇÃO AUTOMÁTICA\nNão iniciada.\n"
            );
        }

        if (capture.capturedObject == null) {
            throw new CaptureFlowException(
                    "a câmera não informou o handle do novo objeto",
                    capture.report,
                    "IMPORTAÇÃO AUTOMÁTICA\nERRO: ObjectAddedEx/64 ausente.\n"
            );
        }

        try {
            SystemClock.sleep(PTP_TO_MTP_SETTLE_MS);
            MtpCameraClient.AutoImportResult imported =
                    MtpCameraClient.waitForCapturedObjectAndDownload(
                            usbManager,
                            device,
                            capture.capturedObject,
                            destination,
                            NEW_IMAGE_TIMEOUT_MS
                    );
            return new CaptureFlowResult(
                    capture.report,
                    imported.report,
                    imported.downloadedFile,
                    imported.cameraFileName
            );
        } catch (MtpCameraClient.ProbeException error) {
            throw new CaptureFlowException(
                    "importação automática: " + error.getMessage(),
                    capture.report,
                    "IMPORTAÇÃO AUTOMÁTICA\nERRO: " + error.getMessage() + "\n"
            );
        }
    }

    private boolean waitUntilOrCanceled(long targetElapsedTime) {
        while (!sequenceCancelRequested) {
            long remaining = targetElapsedTime - SystemClock.elapsedRealtime();
            if (remaining <= 0) {
                return true;
            }
            SystemClock.sleep(Math.min(remaining, 200));
        }
        return false;
    }

    private Integer readSequenceValue(EditText input, int minimum, int maximum, String label) {
        try {
            int value = Integer.parseInt(input.getText().toString().trim());
            if (value < minimum || value > maximum) {
                throw new NumberFormatException();
            }
            return value;
        } catch (NumberFormatException error) {
            Toast.makeText(this, label + " deve estar entre " + minimum + " e " + maximum,
                    Toast.LENGTH_LONG).show();
            return null;
        }
    }

    private void finishSequenceWithError(int captureNumber, CaptureFlowException error) {
        cameraBusy = false;
        sequenceRunning = false;
        sequenceCancelRequested = false;
        captureReport = error.captureReport;
        mtpReport = error.importReport;
        sequenceProgressView.setText("Sequência falhou na foto " + captureNumber + ": "
                + error.getMessage());
        appendEvent("Sequência falhou na foto " + captureNumber + ": " + error.getMessage());
        refreshProbe();
    }

    private void runMtpProbe(boolean downloadLatest) {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) {
            appendEvent("MTP não iniciado: câmera ausente ou sem permissão USB");
            refreshProbe();
            return;
        }

        cameraBusy = true;
        appendEvent(downloadLatest
                ? "Iniciando inventário MTP e download da última imagem"
                : "Iniciando inventário MTP somente leitura");
        refreshProbe();
        File destination = downloadDirectory();

        cameraExecutor.execute(() -> {
            try {
                MtpCameraClient.Result result = MtpCameraClient.inspect(
                        usbManager,
                        device,
                        destination,
                        downloadLatest
                );
                runOnUiThread(() -> {
                    cameraBusy = false;
                    mtpReport = result.report;
                    appendEvent("MTP concluído: " + result.objectCount + " arquivos, "
                            + result.imageCount + " imagens");
                    if (result.downloadedFile != null) {
                        appendEvent("Download concluído: " + result.downloadedFile.getAbsolutePath());
                        showPreview(result.downloadedFile);
                    }
                    refreshProbe();
                });
            } catch (MtpCameraClient.ProbeException error) {
                runOnUiThread(() -> {
                    cameraBusy = false;
                    mtpReport = "SESSÃO MTP/PTP\nERRO: " + error.getMessage() + "\n";
                    appendEvent("MTP falhou: " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private File downloadDirectory() {
        File root = getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        if (root == null) {
            root = getFilesDir();
        }
        return new File(root, "EOSRProbe");
    }

    private void showPreview(File file) {
        String name = file.getName().toUpperCase(Locale.US);
        if (!name.endsWith(".JPG") && !name.endsWith(".JPEG")) {
            previewView.setVisibility(View.GONE);
            return;
        }

        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
        int sampleSize = 1;
        while (bounds.outWidth / sampleSize > 1600 || bounds.outHeight / sampleSize > 1600) {
            sampleSize *= 2;
        }
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = sampleSize;
        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
        if (bitmap == null) {
            previewView.setVisibility(View.GONE);
            appendEvent("JPEG baixado, mas o preview não pôde ser decodificado");
            return;
        }
        previewView.setImageBitmap(bitmap);
        previewView.setVisibility(View.VISIBLE);
    }

    private void requestUsbPermission() {
        UsbDevice device = selectCamera();
        if (device == null) {
            appendEvent("Não há dispositivo USB para autorizar");
            refreshProbe();
            return;
        }
        if (usbManager.hasPermission(device)) {
            appendEvent("A permissão USB já estava concedida" + deviceSuffix(device));
            probeOpenAndClose(device);
            refreshProbe();
            return;
        }

        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags |= PendingIntent.FLAG_MUTABLE;
        }
        Intent permissionIntent = new Intent(this, UsbPermissionReceiver.class);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(this, 0, permissionIntent, flags);
        appendEvent("Solicitando permissão USB" + deviceSuffix(device));
        usbManager.requestPermission(device, pendingIntent);
        refreshProbe();
    }

    private void probeOpenAndClose(UsbDevice device) {
        UsbDeviceConnection connection = null;
        try {
            connection = usbManager.openDevice(device);
            if (connection == null) {
                appendEvent("Falha: UsbManager.openDevice retornou null" + deviceSuffix(device));
            } else {
                appendEvent("Conexão USB aberta; fileDescriptor=" + connection.getFileDescriptor());
            }
        } catch (RuntimeException error) {
            appendEvent("Falha ao abrir USB: " + error.getClass().getSimpleName()
                    + ": " + error.getMessage());
        } finally {
            if (connection != null) {
                connection.close();
                appendEvent("Conexão USB fechada com segurança");
            }
        }
    }

    private UsbDevice selectCamera() {
        UsbDevice fallback = null;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            if (fallback == null) {
                fallback = device;
            }
            if (device.getVendorId() == CANON_VENDOR_ID) {
                return device;
            }
        }
        return fallback;
    }

    private void copyLog() {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("Camerae EOS R USB log", logView.getText()));
        Toast.makeText(this, R.string.log_copied, Toast.LENGTH_SHORT).show();
    }

    private void shareLog() {
        Intent share = new Intent(Intent.ACTION_SEND);
        share.setType("text/plain");
        share.putExtra(Intent.EXTRA_SUBJECT, "Camerae EOS R USB log");
        share.putExtra(Intent.EXTRA_TEXT, logView.getText().toString());
        startActivity(Intent.createChooser(share, getString(R.string.share_log)));
    }

    private void appendEvent(String message) {
        eventLog.append('[').append(timestamp()).append("] ").append(message).append('\n');
    }

    private static String timestamp() {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(new Date());
    }

    private static String deviceSuffix(UsbDevice device) {
        return device == null ? "" : " — " + deviceLabel(device);
    }

    private static String deviceLabel(UsbDevice device) {
        return String.format(Locale.US, "%s [VID=0x%04X PID=0x%04X]",
                device.getDeviceName(), device.getVendorId(), device.getProductId());
    }

    private static final class CaptureFlowResult {
        final String captureReport;
        final String importReport;
        final File downloadedFile;
        final String cameraFileName;

        CaptureFlowResult(
                String captureReport,
                String importReport,
                File downloadedFile,
                String cameraFileName
        ) {
            this.captureReport = captureReport;
            this.importReport = importReport;
            this.downloadedFile = downloadedFile;
            this.cameraFileName = cameraFileName;
        }
    }

    private static final class CaptureFlowException extends Exception {
        final String captureReport;
        final String importReport;

        CaptureFlowException(String message, String captureReport, String importReport) {
            super(message);
            this.captureReport = captureReport;
            this.importReport = importReport;
        }
    }

    @SuppressWarnings("deprecation")
    private static UsbDevice readUsbDevice(Intent intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class);
        }
        return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
    }
}

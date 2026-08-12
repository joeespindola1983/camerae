package com.camerae.eosrprobe;

import android.app.Activity;
import android.app.PendingIntent;
import android.annotation.SuppressLint;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentValues;
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
import android.provider.MediaStore;
import android.view.View;
import android.widget.Button;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.OutputStream;
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
    private static final int CANON_EOS_R_PRODUCT_ID = 0x32DA;
    private static final long NEW_IMAGE_TIMEOUT_MS = 30_000;
    private static final long PTP_TO_MTP_SETTLE_MS = 1_000;

    private final StringBuilder eventLog = new StringBuilder();
    private final ExecutorService cameraExecutor = Executors.newSingleThreadExecutor();
    private UsbManager usbManager;
    private TextView statusView;
    private TextView logView;
    private Button authorizeButton;
    private Button gphotoProbeButton;
    private Button captureButton;
    private Button inspectMtpButton;
    private Button inspectControlsButton;
    private Button applyControlsButton;
    private Button downloadLatestButton;
    private Button startSequenceButton;
    private Button cancelSequenceButton;
    private Button copyLogButton;
    private Button shareLogButton;
    private Button exportJpegButton;
    private EditText sequenceCountInput;
    private EditText sequenceDelayInput;
    private EditText sequenceIntervalInput;
    private EditText bulbDurationInput;
    private Spinner isoSpinner;
    private Spinner whiteBalanceSpinner;
    private Spinner formatSpinner;
    private LinearLayout thumbnailStrip;
    private TextView sequenceProgressView;
    private TextView exposureCapabilitiesView;
    private ImageView previewView;
    private String mtpReport = "MTP/PTP ainda não consultado.\n";
    private String captureReport = "Captura remota ainda não testada.\n";
    private String exposureReport = "Controles de exposição ainda não consultados.\n";
    private String sequenceReport = "Manifesto de sequência ainda não criado.\n";
    private String gphotoReport = "libgphoto2 ainda não consultou a câmera.\n";
    private boolean cameraBusy;
    private boolean gphotoProbeCompleted;
    private UsbDeviceConnection gphotoConnection;
    private File selectedJpeg;
    private volatile boolean sequenceRunning;
    private volatile boolean sequenceCancelRequested;
    private boolean receiverRegistered;
    private CanonEosExposureCapabilities.Snapshot exposureSnapshot;

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
                exposureReport = "Controles de exposição desconectados.\n";
                gphotoReport = "libgphoto2 desconectado; reinicie o app antes de um novo probe.\n";
                gphotoProbeCompleted = false;
                closeGPhotoConnection();
                exposureSnapshot = null;
                clearExposureControls();
                sequenceProgressView.setText("Sequência interrompida: câmera desconectada");
                previewView.setVisibility(View.GONE);
                refreshProbe();
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        PersistentProbeLog.initialize(getApplicationContext());
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
        gphotoProbeButton = findViewById(R.id.gphoto_probe);
        captureButton = findViewById(R.id.capture_test);
        inspectMtpButton = findViewById(R.id.inspect_mtp);
        inspectControlsButton = findViewById(R.id.inspect_controls);
        applyControlsButton = findViewById(R.id.apply_controls);
        downloadLatestButton = findViewById(R.id.download_latest);
        startSequenceButton = findViewById(R.id.start_sequence);
        cancelSequenceButton = findViewById(R.id.cancel_sequence);
        copyLogButton = findViewById(R.id.copy_log);
        shareLogButton = findViewById(R.id.share_log);
        sequenceCountInput = findViewById(R.id.sequence_count);
        sequenceDelayInput = findViewById(R.id.sequence_delay);
        sequenceIntervalInput = findViewById(R.id.sequence_interval);
        bulbDurationInput = findViewById(R.id.bulb_duration);
        isoSpinner = findViewById(R.id.iso_spinner);
        whiteBalanceSpinner = findViewById(R.id.white_balance_spinner);
        formatSpinner = findViewById(R.id.capture_format_spinner);
        exportJpegButton = findViewById(R.id.export_jpeg);
        thumbnailStrip = findViewById(R.id.capture_thumbnails);
        sequenceProgressView = findViewById(R.id.sequence_progress);
        exposureCapabilitiesView = findViewById(R.id.exposure_capabilities);
        previewView = findViewById(R.id.preview);

        findViewById(R.id.refresh).setOnClickListener(view -> {
            appendEvent("Varredura manual solicitada");
            refreshProbe();
        });
        authorizeButton.setOnClickListener(view -> requestUsbPermission());
        gphotoProbeButton.setOnClickListener(view -> runGPhotoProbe());
        captureButton.setOnClickListener(view -> runGPhotoCapture());
        startSequenceButton.setOnClickListener(view -> startGPhotoSequence());
        cancelSequenceButton.setOnClickListener(view -> cancelAstroSequence());
        inspectMtpButton.setOnClickListener(view -> runMtpProbe(false));
        inspectControlsButton.setOnClickListener(view -> inspectExposureCapabilities());
        applyControlsButton.setOnClickListener(view -> applyExposureControls());
        downloadLatestButton.setOnClickListener(view -> runMtpProbe(true));
        copyLogButton.setOnClickListener(view -> copyLog());
        shareLogButton.setOnClickListener(view -> shareLog());
        exportJpegButton.setOnClickListener(view -> exportSelectedJpeg());

        configureAstroControlAdapters();

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
        closeGPhotoConnection();
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
            statusView.setText(isValidatedCaptureDevice(selected)
                    ? getString(R.string.status_ready, deviceLabel(selected))
                    : getString(R.string.status_import_only, deviceLabel(selected)));
        } else {
            statusView.setText(getString(R.string.status_permission_required, deviceLabel(selected)));
        }
        boolean cameraReady = selected != null && usbManager.hasPermission(selected);
        boolean captureValidated = cameraReady && isValidatedCaptureDevice(selected);
        authorizeButton.setEnabled(selected != null && !usbManager.hasPermission(selected) && !cameraBusy);
        gphotoProbeButton.setEnabled(captureValidated && !cameraBusy && !gphotoProbeCompleted);
        captureButton.setEnabled(captureValidated && !cameraBusy);
        inspectMtpButton.setEnabled(cameraReady && !cameraBusy);
        inspectControlsButton.setEnabled(false);
        boolean controlsReady = captureValidated
                && exposureSnapshot != null
                && !exposureSnapshot.isoOptions.isEmpty()
                && !exposureSnapshot.whiteBalanceOptions.isEmpty();
        applyControlsButton.setEnabled(false);
        isoSpinner.setEnabled(captureValidated && !cameraBusy);
        whiteBalanceSpinner.setEnabled(captureValidated && !cameraBusy);
        formatSpinner.setEnabled(captureValidated && !cameraBusy);
        bulbDurationInput.setEnabled(captureValidated && !cameraBusy);
        exportJpegButton.setEnabled(selectedJpeg != null && !cameraBusy);
        downloadLatestButton.setEnabled(cameraReady && !cameraBusy);
        startSequenceButton.setEnabled(captureValidated && !cameraBusy);
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
        report.append("Captura validada para o dispositivo atual: ")
                .append(captureValidated).append("\n\n");
        report.append("EVENTOS\n").append(eventLog).append('\n');
        report.append(UsbTopologyFormatter.describe(usbManager));
        report.append('\n').append(gphotoReport);
        report.append('\n').append(captureReport);
        report.append('\n').append(mtpReport);
        report.append('\n').append(exposureReport);
        report.append('\n').append(sequenceReport);
        report.append("\nDIAGNÓSTICO PERSISTENTE PTP\n")
                .append(PersistentProbeLog.snapshot());
        logView.setText(report.toString());
    }

    private void runGPhotoProbe() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) {
            appendEvent("Probe libgphoto2 cancelado: câmera ausente ou sem permissão USB");
            refreshProbe();
            return;
        }
        if (gphotoProbeCompleted) {
            appendEvent("Probe libgphoto2 já executado neste attach; reconecte a câmera para repetir");
            refreshProbe();
            return;
        }

        cameraBusy = true;
        appendEvent("Iniciando probe libgphoto2 2.5.34 somente leitura");
        refreshProbe();
        cameraExecutor.submit(() -> {
            try {
                if (gphotoConnection == null) gphotoConnection = usbManager.openDevice(device);
                if (gphotoConnection == null) {
                    throw new IOException("UsbManager.openDevice retornou null");
                }
                int fileDescriptor = gphotoConnection.getFileDescriptor();
                PersistentProbeLog.append("GPHOTO2", "Início do probe read-only; fd=" + fileDescriptor);
                String result = NativeGPhotoClient.probe(getApplicationContext(), fileDescriptor);
                PersistentProbeLog.append("GPHOTO2", result);
                runOnUiThread(() -> {
                    gphotoReport = result.endsWith("\n") ? result : result + "\n";
                    gphotoProbeCompleted = true;
                    cameraBusy = false;
                    appendEvent("Probe libgphoto2 finalizado; nenhuma escrita ou captura foi solicitada");
                    refreshProbe();
                });
            } catch (Throwable error) {
                PersistentProbeLog.append("GPHOTO2", "Falha: " + error);
                runOnUiThread(() -> {
                    gphotoReport = "PROBE LIBGPHOTO2 SOMENTE LEITURA\nERRO: "
                            + error.getClass().getSimpleName() + ": " + error.getMessage() + "\n";
                    gphotoProbeCompleted = true;
                    cameraBusy = false;
                    appendEvent("Probe libgphoto2 falhou: " + error.getClass().getSimpleName()
                            + ": " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private void configureAstroControlAdapters() {
        String[] isoValues = {
                "Auto", "100", "125", "160", "200", "250", "320", "400", "500", "640",
                "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000",
                "6400", "8000", "10000", "12800", "16000", "20000", "25600", "32000", "40000"
        };
        String[] whiteBalanceValues = {
                "Auto", "AWB White", "Daylight", "Shadow", "Cloudy", "Tungsten",
                "Fluorescent", "Flash", "Manual", "Color Temperature"
        };
        String[] formatValues = {"JPG", "CR3", "JPG+CR3"};
        isoSpinner.setAdapter(new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_dropdown_item, isoValues));
        whiteBalanceSpinner.setAdapter(new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_dropdown_item, whiteBalanceValues));
        formatSpinner.setAdapter(new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_dropdown_item, formatValues));
        isoSpinner.setSelection(19);
        whiteBalanceSpinner.setSelection(9);
        formatSpinner.setSelection(0);
        exposureCapabilitiesView.setText(
                "Controles via libgphoto2. Primeiro teste recomendado: JPG, Bulb 5 s e foco manual."
        );
    }

    private void runGPhotoCapture() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)
                || !isValidatedCaptureDevice(device)) {
            appendEvent("Captura libgphoto2 cancelada: EOS R ausente ou sem permissão USB");
            refreshProbe();
            return;
        }
        int bulbSeconds;
        try {
            bulbSeconds = Integer.parseInt(bulbDurationInput.getText().toString().trim());
        } catch (NumberFormatException error) {
            Toast.makeText(this, "Informe uma duração Bulb válida", Toast.LENGTH_SHORT).show();
            return;
        }
        if (bulbSeconds < 1 || bulbSeconds > 120) {
            Toast.makeText(this, "Neste MVP, use Bulb entre 1 e 120 segundos", Toast.LENGTH_LONG).show();
            return;
        }

        String iso = String.valueOf(isoSpinner.getSelectedItem());
        String whiteBalance = String.valueOf(whiteBalanceSpinner.getSelectedItem());
        String format = String.valueOf(formatSpinner.getSelectedItem());
        File pictures = getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        if (pictures == null) pictures = getFilesDir();
        File outputDirectory = new File(
                pictures,
                "CameraeAstro/" + new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date())
        );

        cameraBusy = true;
        appendEvent("Captura libgphoto2 iniciada: ISO " + iso + ", WB " + whiteBalance
                + ", " + format + ", Bulb " + bulbSeconds + " s");
        refreshProbe();
        cameraExecutor.submit(() -> {
            try {
                if (gphotoConnection == null) gphotoConnection = usbManager.openDevice(device);
                if (gphotoConnection == null) throw new IOException("UsbManager.openDevice retornou null");
                String result = NativeGPhotoClient.capture(
                        getApplicationContext(),
                        gphotoConnection.getFileDescriptor(),
                        outputDirectory,
                        iso,
                        whiteBalance,
                        format,
                        bulbSeconds
                );
                PersistentProbeLog.append("GPHOTO2-CAPTURE", result);
                runOnUiThread(() -> {
                    captureReport = result.endsWith("\n") ? result : result + "\n";
                    addCapturedFilesFromReport(result);
                    gphotoProbeCompleted = true;
                    cameraBusy = false;
                    int expectedFiles = "JPG+CR3".equals(format) ? 2 : 1;
                    boolean completed = result.contains(
                            "Arquivos baixados: " + expectedFiles + "/" + expectedFiles
                    );
                    appendEvent(completed
                            ? "Captura libgphoto2 concluída com download " + expectedFiles + "/" + expectedFiles
                            : "Captura libgphoto2 falhou; nenhum sucesso foi presumido");
                    refreshProbe();
                });
            } catch (Throwable error) {
                PersistentProbeLog.append("GPHOTO2-CAPTURE", "Falha: " + error);
                runOnUiThread(() -> {
                    captureReport = "CAPTURA LIBGPHOTO2\nERRO: "
                            + error.getClass().getSimpleName() + ": " + error.getMessage() + "\n";
                    cameraBusy = false;
                    appendEvent("Captura libgphoto2 falhou: " + error.getClass().getSimpleName()
                            + ": " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private void addCapturedFilesFromReport(String report) {
        for (String line : report.split("\\n")) {
            if (!line.startsWith("FILE|")) continue;
            String[] components = line.split("\\|", 3);
            if (components.length < 3) continue;
            File file = new File(components[1]);
            String lowerName = file.getName().toLowerCase(Locale.US);
            if (!lowerName.endsWith(".jpg") && !lowerName.endsWith(".jpeg")) continue;
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = 8;
            Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
            if (bitmap == null) continue;
            ImageView thumbnail = new ImageView(this);
            int size = Math.round(88 * getResources().getDisplayMetrics().density);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(size, size);
            params.setMarginEnd(Math.round(8 * getResources().getDisplayMetrics().density));
            thumbnail.setLayoutParams(params);
            thumbnail.setScaleType(ImageView.ScaleType.CENTER_CROP);
            thumbnail.setImageBitmap(bitmap);
            thumbnail.setContentDescription("Captura " + file.getName());
            thumbnail.setOnClickListener(view -> selectJpeg(file));
            thumbnailStrip.addView(thumbnail, 0);
            selectJpeg(file);
        }
    }

    private void selectJpeg(File file) {
        selectedJpeg = file;
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = 4;
        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
        if (bitmap != null) {
            previewView.setImageBitmap(bitmap);
            previewView.setVisibility(View.VISIBLE);
        }
        exportJpegButton.setEnabled(!cameraBusy);
    }

    private void exportSelectedJpeg() {
        File source = selectedJpeg;
        if (source == null || !source.isFile()) {
            Toast.makeText(this, "Selecione um JPG capturado", Toast.LENGTH_SHORT).show();
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Toast.makeText(this, "Exportação deste MVP requer Android 10 ou superior", Toast.LENGTH_LONG).show();
            return;
        }
        cameraExecutor.submit(() -> {
            android.net.Uri uri = null;
            try {
                ContentValues values = new ContentValues();
                values.put(MediaStore.Images.Media.DISPLAY_NAME, source.getName());
                values.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
                values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Camerae");
                values.put(MediaStore.Images.Media.IS_PENDING, 1);
                uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
                if (uri == null) throw new IOException("MediaStore não criou o destino");
                try (FileInputStream input = new FileInputStream(source);
                     OutputStream output = getContentResolver().openOutputStream(uri)) {
                    if (output == null) throw new IOException("MediaStore não abriu o destino");
                    byte[] buffer = new byte[64 * 1024];
                    int count;
                    while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                }
                values.clear();
                values.put(MediaStore.Images.Media.IS_PENDING, 0);
                getContentResolver().update(uri, values, null, null);
                runOnUiThread(() -> {
                    appendEvent("JPG exportado para Fotos/Camerae: " + source.getName());
                    Toast.makeText(this, "JPG exportado para a Galeria", Toast.LENGTH_SHORT).show();
                    refreshProbe();
                });
            } catch (IOException error) {
                if (uri != null) getContentResolver().delete(uri, null, null);
                runOnUiThread(() -> Toast.makeText(
                        this, "Falha ao exportar: " + error.getMessage(), Toast.LENGTH_LONG).show());
            }
        });
    }

    private void closeGPhotoConnection() {
        if (gphotoConnection != null) {
            gphotoConnection.close();
            gphotoConnection = null;
        }
    }

    private void inspectExposureCapabilities() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)
                || !isValidatedCaptureDevice(device)) {
            appendEvent("Controles não consultados: EOS R ausente ou sem permissão USB");
            refreshProbe();
            return;
        }

        cameraBusy = true;
        appendEvent("Lendo capabilities de ISO, white balance e shutter");
        exposureCapabilitiesView.setText("Consultando controles anunciados pela câmera…");
        refreshProbe();
        cameraExecutor.execute(() -> {
            try {
                CanonEosRemoteClient.CapabilityResult result =
                        CanonEosRemoteClient.inspectExposureCapabilities(usbManager, device);
                runOnUiThread(() -> {
                    cameraBusy = false;
                    exposureReport = result.report;
                    exposureSnapshot = result.snapshot;
                    populateExposureControls(result.snapshot);
                    exposureCapabilitiesView.setText(result.summary);
                    appendEvent("Capabilities de exposição confirmadas pela EOS R");
                    refreshProbe();
                });
            } catch (CanonEosRemoteClient.CapabilityException error) {
                runOnUiThread(() -> {
                    cameraBusy = false;
                    exposureReport = error.report;
                    exposureCapabilitiesView.setText("Leitura de controles falhou: "
                            + error.getMessage());
                    appendEvent("Leitura de controles falhou: " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private void applyExposureControls() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)
                || !isValidatedCaptureDevice(device)
                || exposureSnapshot == null) {
            appendEvent("Aplicação de controles bloqueada: leia as capabilities primeiro");
            refreshProbe();
            return;
        }
        CanonEosExposureCapabilities.Option iso = selectedOption(isoSpinner);
        CanonEosExposureCapabilities.Option whiteBalance =
                selectedOption(whiteBalanceSpinner);
        if (iso == null || whiteBalance == null) {
            appendEvent("Aplicação de controles bloqueada: seleção incompleta");
            refreshProbe();
            return;
        }

        cameraBusy = true;
        appendEvent("Aplicando ISO=" + iso.label + " WB=" + whiteBalance.label);
        exposureCapabilitiesView.setText("Aplicando e confirmando controles…");
        refreshProbe();
        cameraExecutor.execute(() -> {
            try {
                CanonEosRemoteClient.CapabilityResult result =
                        CanonEosRemoteClient.applyExposureSettings(
                                usbManager,
                                device,
                                iso.value,
                                whiteBalance.value
                        );
                runOnUiThread(() -> {
                    cameraBusy = false;
                    exposureReport = result.report;
                    exposureSnapshot = result.snapshot;
                    populateExposureControls(result.snapshot);
                    exposureCapabilitiesView.setText(result.summary);
                    appendEvent("Controles confirmados: ISO=" + iso.label
                            + " WB=" + whiteBalance.label);
                    refreshProbe();
                });
            } catch (CanonEosRemoteClient.CapabilityException error) {
                runOnUiThread(() -> {
                    cameraBusy = false;
                    exposureReport = error.report;
                    exposureCapabilitiesView.setText("Aplicação falhou: " + error.getMessage());
                    appendEvent("Aplicação de controles falhou: " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private void populateExposureControls(CanonEosExposureCapabilities.Snapshot snapshot) {
        setSpinnerOptions(isoSpinner, snapshot.isoOptions, snapshot.isoValue);
        setSpinnerOptions(
                whiteBalanceSpinner,
                snapshot.whiteBalanceOptions,
                snapshot.whiteBalanceValue
        );
    }

    private void clearExposureControls() {
        isoSpinner.setEnabled(false);
        whiteBalanceSpinner.setEnabled(false);
        formatSpinner.setEnabled(false);
    }

    private void setSpinnerOptions(
            Spinner spinner,
            java.util.List<CanonEosExposureCapabilities.Option> options,
            int selectedValue
    ) {
        ArrayAdapter<CanonEosExposureCapabilities.Option> adapter = new ArrayAdapter<>(
                this,
                android.R.layout.simple_spinner_item,
                options
        );
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinner.setAdapter(adapter);
        for (int index = 0; index < options.size(); index++) {
            if (options.get(index).value == selectedValue) {
                spinner.setSelection(index);
                break;
            }
        }
    }

    private static CanonEosExposureCapabilities.Option selectedOption(Spinner spinner) {
        Object selected = spinner.getSelectedItem();
        return selected instanceof CanonEosExposureCapabilities.Option
                ? (CanonEosExposureCapabilities.Option) selected
                : null;
    }

    private void runRemoteCapture() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) {
            appendEvent("Captura não iniciada: câmera ausente ou sem permissão USB");
            refreshProbe();
            return;
        }
        if (!isValidatedCaptureDevice(device)) {
            appendEvent("Captura bloqueada: modelo Canon ainda não validado");
            refreshProbe();
            return;
        }

        cameraBusy = true;
        appendEvent("Iniciando captura e importação automática; use foco manual");
        sequenceProgressView.setText("Captura única em andamento…");
        refreshProbe();
        File destination = downloadDirectory();
        long bulbDurationMillis = selectedBulbDurationMillis();
        if (bulbDurationMillis < 0) {
            cameraBusy = false;
            refreshProbe();
            return;
        }
        cameraExecutor.execute(() -> {
            try {
                CaptureFlowResult result = performCaptureAndImport(
                        device,
                        destination,
                        bulbDurationMillis,
                        () -> false
                );
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

    private void startGPhotoSequence() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)
                || !isValidatedCaptureDevice(device)) {
            appendEvent("Sequência libgphoto2 não iniciada: EOS R ausente ou sem permissão USB");
            refreshProbe();
            return;
        }
        Integer photoCount = readSequenceValue(sequenceCountInput, 1, 100, "Fotos");
        Integer initialDelaySeconds = readSequenceValue(sequenceDelayInput, 0, 3600, "Atraso");
        Integer intervalSeconds = readSequenceValue(sequenceIntervalInput, 1, 86400, "Intervalo");
        if (photoCount == null || initialDelaySeconds == null || intervalSeconds == null) return;

        int bulbSeconds;
        try {
            bulbSeconds = Integer.parseInt(bulbDurationInput.getText().toString().trim());
        } catch (NumberFormatException error) {
            Toast.makeText(this, "Informe uma duração Bulb válida", Toast.LENGTH_SHORT).show();
            return;
        }
        if (bulbSeconds < 1 || bulbSeconds > 120) {
            Toast.makeText(this, "Neste MVP, use Bulb entre 1 e 120 segundos", Toast.LENGTH_LONG).show();
            return;
        }
        String iso = String.valueOf(isoSpinner.getSelectedItem());
        String whiteBalance = String.valueOf(whiteBalanceSpinner.getSelectedItem());
        String format = String.valueOf(formatSpinner.getSelectedItem());
        int expectedFilesPerPhoto = "JPG+CR3".equals(format) ? 2 : 1;
        File pictures = getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        if (pictures == null) pictures = getFilesDir();
        File outputDirectory = new File(
                pictures,
                "CameraeAstro/sequence-"
                        + new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date())
        );

        cameraBusy = true;
        sequenceRunning = true;
        sequenceCancelRequested = false;
        sequenceReport = "SEQUÊNCIA LIBGPHOTO2\nEstado: executando\nConcluídas: 0/"
                + photoCount + "\nPasta: " + outputDirectory + "\n";
        sequenceProgressView.setText("Preparando sequência de " + photoCount + " fotos…");
        appendEvent("Sequência libgphoto2 iniciada: " + photoCount + " fotos, atraso "
                + initialDelaySeconds + " s, intervalo " + intervalSeconds + " s, Bulb "
                + bulbSeconds + " s, " + format);
        refreshProbe();

        long initialDelayMs = initialDelaySeconds * 1000L;
        long intervalMs = intervalSeconds * 1000L;
        cameraExecutor.execute(() -> {
            int completed = 0;
            String failure = null;
            long firstCaptureAt = SystemClock.elapsedRealtime() + initialDelayMs;
            try {
                if (gphotoConnection == null) gphotoConnection = usbManager.openDevice(device);
                if (gphotoConnection == null) throw new IOException("UsbManager.openDevice retornou null");
                for (int index = 0; index < photoCount; index++) {
                    long scheduledAt = firstCaptureAt + index * intervalMs;
                    if (!waitUntilOrCanceled(scheduledAt)) break;
                    int captureNumber = index + 1;
                    runOnUiThread(() -> sequenceProgressView.setText(
                            "Expondo " + captureNumber + "/" + photoCount + "…"
                    ));
                    String result = NativeGPhotoClient.capture(
                            getApplicationContext(),
                            gphotoConnection.getFileDescriptor(),
                            outputDirectory,
                            iso,
                            whiteBalance,
                            format,
                            bulbSeconds
                    );
                    PersistentProbeLog.append(
                            "GPHOTO2-SEQUENCE-" + captureNumber,
                            result
                    );
                    String successMarker = "Arquivos baixados: " + expectedFilesPerPhoto
                            + "/" + expectedFilesPerPhoto;
                    if (!result.contains(successMarker)) {
                        failure = "captura " + captureNumber + " não completou " + successMarker;
                        captureReport = result.endsWith("\n") ? result : result + "\n";
                        break;
                    }
                    completed++;
                    int completedNow = completed;
                    runOnUiThread(() -> {
                        captureReport = result.endsWith("\n") ? result : result + "\n";
                        addCapturedFilesFromReport(result);
                        sequenceProgressView.setText(
                                "Baixadas " + completedNow + "/" + photoCount + " fotos"
                        );
                    });
                }
            } catch (Throwable error) {
                failure = error.getClass().getSimpleName() + ": " + error.getMessage();
                PersistentProbeLog.append("GPHOTO2-SEQUENCE", "Falha: " + error);
            }

            int finalCompleted = completed;
            String finalFailure = failure;
            boolean canceled = sequenceCancelRequested;
            runOnUiThread(() -> {
                cameraBusy = false;
                sequenceRunning = false;
                sequenceCancelRequested = false;
                String state = finalFailure != null ? "falhou" : canceled ? "cancelada" : "concluída";
                sequenceProgressView.setText("Sequência " + state + ": " + finalCompleted
                        + "/" + photoCount);
                sequenceReport = "SEQUÊNCIA LIBGPHOTO2\nEstado: " + state
                        + "\nConcluídas: " + finalCompleted + "/" + photoCount
                        + "\nPasta: " + outputDirectory
                        + (finalFailure == null ? "\n" : "\nErro: " + finalFailure + "\n");
                appendEvent("Sequência libgphoto2 " + state + ": " + finalCompleted
                        + "/" + photoCount);
                refreshProbe();
            });
        });
    }

    private void startAstroSequence() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) {
            appendEvent("Sequência não iniciada: câmera ausente ou sem permissão USB");
            refreshProbe();
            return;
        }
        if (!isValidatedCaptureDevice(device)) {
            appendEvent("Sequência bloqueada: modelo Canon ainda não validado");
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
        long bulbDurationMillis = selectedBulbDurationMillis();
        if (bulbDurationMillis < 0) {
            return;
        }

        AstroSequenceManifest manifest;
        try {
            manifest = AstroSequenceManifest.create(
                    downloadDirectory(),
                    device,
                    photoCount,
                    initialDelaySeconds,
                    intervalSeconds,
                    bulbDurationMillis,
                    exposureSnapshot
            );
        } catch (IOException error) {
            sequenceProgressView.setText("Não foi possível criar o manifesto: "
                    + error.getMessage());
            appendEvent("Sequência não iniciada: manifesto falhou: " + error.getMessage());
            refreshProbe();
            return;
        }

        cameraBusy = true;
        sequenceRunning = true;
        sequenceCancelRequested = false;
        appendEvent("Sequência astro iniciada: fotos=" + photoCount
                + " atraso=" + initialDelaySeconds + "s intervalo=" + intervalSeconds + "s"
                + (bulbDurationMillis > 0
                ? " bulb=" + bulbDurationMillis / 1000L + "s"
                : ""));
        sequenceProgressView.setText("Preparando sequência de " + photoCount + " fotos…");
        sequenceReport = manifestReport(manifest.path(), "running", 0, photoCount, null);
        refreshProbe();

        File destination = manifest.sequenceDirectory();
        long initialDelayMs = initialDelaySeconds * 1000L;
        long intervalMs = intervalSeconds * 1000L;
        long sequenceStartedAtMillis = System.currentTimeMillis();
        cameraExecutor.execute(() -> {
            long firstCaptureAt = SystemClock.elapsedRealtime() + initialDelayMs;
            long firstCaptureAtMillis = sequenceStartedAtMillis + initialDelayMs;
            int completed = 0;
            for (int index = 0; index < photoCount; index++) {
                long scheduledAt = firstCaptureAt + index * intervalMs;
                long scheduledAtMillis = firstCaptureAtMillis + index * intervalMs;
                if (!waitUntilOrCanceled(scheduledAt)) {
                    break;
                }

                int captureNumber = index + 1;
                runOnUiThread(() -> {
                    sequenceProgressView.setText("Capturando " + captureNumber + "/" + photoCount + "…");
                    refreshProbe();
                });

                CaptureFlowResult result;
                long captureStartedAtMillis = System.currentTimeMillis();
                try {
                    result = performCaptureAndImport(
                            device,
                            destination,
                            bulbDurationMillis,
                            () -> sequenceCancelRequested
                    );
                } catch (CaptureFlowException error) {
                    long failedAtMillis = System.currentTimeMillis();
                    String manifestError = null;
                    try {
                        manifest.recordFailure(
                                captureNumber,
                                scheduledAtMillis,
                                captureStartedAtMillis,
                                failedAtMillis,
                                error.getMessage()
                        );
                    } catch (IOException manifestFailure) {
                        manifestError = manifestFailure.getMessage();
                    }
                    String finalManifestError = manifestError;
                    runOnUiThread(() -> finishSequenceWithError(
                            captureNumber,
                            error,
                            manifest.path(),
                            finalManifestError
                    ));
                    return;
                }

                long captureCompletedAtMillis = System.currentTimeMillis();
                try {
                    manifest.recordSuccess(
                            captureNumber,
                            scheduledAtMillis,
                            captureStartedAtMillis,
                            captureCompletedAtMillis,
                            result.capturedObject.handle,
                            result.capturedObject.storageId,
                            result.cameraFileName,
                            result.capturedObject.size,
                            result.downloadedFile,
                            result.actualBulbHoldMillis
                    );
                } catch (IOException error) {
                    runOnUiThread(() -> finishSequenceAfterManifestError(
                            captureNumber,
                            result,
                            manifest.path(),
                            error
                    ));
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
                    sequenceReport = manifestReport(
                            manifest.path(), "running", completedCount, photoCount, null
                    );
                    showPreview(result.downloadedFile);
                    refreshProbe();
                });
            }

            int finalCompleted = completed;
            boolean canceled = sequenceCancelRequested;
            String finalStatus = canceled ? "canceled" : "completed";
            try {
                manifest.finish(finalStatus, finalCompleted);
            } catch (IOException error) {
                runOnUiThread(() -> finishSequenceAfterManifestError(
                        finalCompleted,
                        null,
                        manifest.path(),
                        error
                ));
                return;
            }
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
                sequenceReport = manifestReport(
                        manifest.path(), finalStatus, finalCompleted, photoCount, null
                );
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

    private CaptureFlowResult performCaptureAndImport(
            UsbDevice device,
            File destination,
            long bulbDurationMillis,
            java.util.function.BooleanSupplier cancelRequested
    )
            throws CaptureFlowException {
        CanonEosRemoteClient.Result capture;
        try {
            capture = CanonEosRemoteClient.capture(
                    usbManager,
                    device,
                    bulbDurationMillis,
                    cancelRequested
            );
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
                    imported.cameraFileName,
                    capture.capturedObject,
                    capture.actualBulbHoldMillis
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

    private long selectedBulbDurationMillis() {
        if (exposureSnapshot == null || !exposureSnapshot.isBulbMode()) {
            return 0;
        }
        Integer seconds = readSequenceValue(bulbDurationInput, 1, 3600, "Bulb");
        return seconds == null ? -1 : seconds * 1000L;
    }

    private void finishSequenceWithError(
            int captureNumber,
            CaptureFlowException error,
            String manifestPath,
            String manifestError
    ) {
        cameraBusy = false;
        sequenceRunning = false;
        sequenceCancelRequested = false;
        captureReport = error.captureReport;
        mtpReport = error.importReport;
        sequenceProgressView.setText("Sequência falhou na foto " + captureNumber + ": "
                + error.getMessage());
        appendEvent("Sequência falhou na foto " + captureNumber + ": " + error.getMessage());
        sequenceReport = manifestReport(
                manifestPath,
                "failed",
                captureNumber - 1,
                -1,
                manifestError
        );
        refreshProbe();
    }

    private void finishSequenceAfterManifestError(
            int captureNumber,
            CaptureFlowResult result,
            String manifestPath,
            IOException error
    ) {
        cameraBusy = false;
        sequenceRunning = false;
        sequenceCancelRequested = false;
        if (result != null) {
            captureReport = result.captureReport;
            mtpReport = result.importReport;
            showPreview(result.downloadedFile);
        }
        sequenceProgressView.setText("Manifesto falhou após a foto " + captureNumber + ": "
                + error.getMessage());
        appendEvent("Sequência interrompida por falha no manifesto: " + error.getMessage());
        sequenceReport = manifestReport(
                manifestPath,
                "manifest-error",
                captureNumber,
                -1,
                error.getMessage()
        );
        refreshProbe();
    }

    private static String manifestReport(
            String path,
            String status,
            int completed,
            int planned,
            String error
    ) {
        StringBuilder report = new StringBuilder("MANIFESTO DA SEQUÊNCIA\n");
        report.append("Status: ").append(status).append('\n');
        report.append("Concluídas: ").append(completed);
        if (planned >= 0) {
            report.append('/').append(planned);
        }
        report.append('\n');
        report.append("Arquivo: ").append(path).append('\n');
        if (error != null) {
            report.append("Erro: ").append(error).append('\n');
        }
        return report.toString();
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
        PersistentProbeLog.append("APP", message);
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

    private static boolean isValidatedCaptureDevice(UsbDevice device) {
        return device != null
                && device.getVendorId() == CANON_VENDOR_ID
                && device.getProductId() == CANON_EOS_R_PRODUCT_ID;
    }

    private static final class CaptureFlowResult {
        final String captureReport;
        final String importReport;
        final File downloadedFile;
        final String cameraFileName;
        final CanonEosEventParser.CapturedObject capturedObject;
        final long actualBulbHoldMillis;

        CaptureFlowResult(
                String captureReport,
                String importReport,
                File downloadedFile,
                String cameraFileName,
                CanonEosEventParser.CapturedObject capturedObject,
                long actualBulbHoldMillis
        ) {
            this.captureReport = captureReport;
            this.importReport = importReport;
            this.downloadedFile = downloadedFile;
            this.cameraFileName = cameraFileName;
            this.capturedObject = capturedObject;
            this.actualBulbHoldMillis = actualBulbHoldMillis;
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

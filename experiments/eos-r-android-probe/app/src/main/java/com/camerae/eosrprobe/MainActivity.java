package com.camerae.eosrprobe;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
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
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.MediaStore;
import android.view.View;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
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
    private static final int MAX_VISIBLE_THUMBNAILS = 40;

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
    private Button updatePreviewButton;
    private Button downloadSessionJpegsButton;
    private Button finalizeSessionButton;
    private View sessionCatalogScreen;
    private View captureScreen;
    private View captureSettingsControls;
    private TextView catalogCameraStatusView;
    private TextView sessionCountView;
    private TextView sessionsEmptyView;
    private TextView sessionCameraStatusView;
    private LinearLayout sessionListView;
    private EditText sequenceCountInput;
    private EditText sequenceDelayInput;
    private EditText sequenceIntervalInput;
    private SeekBar bulbDurationSlider;
    private TextView bulbDurationValueView;
    private Spinner isoSpinner;
    private Spinner whiteBalanceSpinner;
    private Spinner formatSpinner;
    private LinearLayout thumbnailStrip;
    private TextView sequenceProgressView;
    private TextView acceptedCountView;
    private TextView exposureMetricView;
    private TextView nextCaptureView;
    private TextView exposureCapabilitiesView;
    private TextView captureSettingsAvailabilityView;
    private ImageView previewView;
    private LinearLayout previewPlaceholder;
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
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile boolean captureCountdownActive;
    private int countdownGeneration;
    private boolean hasCaptureLog;
    private volatile boolean previewRefreshRequested;
    private File activeSequenceDirectory;
    private int activeSequenceCompletedCount;
    private final List<String> pendingJpegCameraFiles = new ArrayList<>();
    private final List<String> allCameraFiles = new ArrayList<>();
    private AstroUsbSessionStore.Session activeSession;
    private boolean sessionCameraVerified;
    private boolean receiverRegistered;
    private boolean serviceReceiverRegistered;
    private String lastServicePreviewPath;
    private CanonEosExposureCapabilities.Snapshot exposureSnapshot;

    private final BroadcastReceiver astroServiceReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            applyAstroServiceSnapshot(AstroCaptureService.currentSnapshot());
        }
    };

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
                sessionCameraVerified = false;
                closeGPhotoConnection();
                exposureSnapshot = null;
                clearExposureControls();
                sequenceProgressView.setText("Sequência interrompida: câmera desconectada");
                previewView.setVisibility(View.GONE);
                previewPlaceholder.setVisibility(View.VISIBLE);
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
        sessionCatalogScreen = findViewById(R.id.session_catalog_screen);
        captureScreen = findViewById(R.id.capture_screen);
        captureSettingsControls = findViewById(R.id.capture_settings_controls);
        captureSettingsAvailabilityView = findViewById(R.id.capture_settings_availability);
        catalogCameraStatusView = findViewById(R.id.catalog_camera_status);
        sessionCountView = findViewById(R.id.session_count);
        sessionsEmptyView = findViewById(R.id.sessions_empty);
        sessionListView = findViewById(R.id.session_list);
        String appVersion = getString(
                R.string.version_format,
                BuildConfig.VERSION_NAME,
                BuildConfig.VERSION_CODE
        );
        ((TextView) findViewById(R.id.app_version)).setText(appVersion);
        ((TextView) findViewById(R.id.catalog_app_version)).setText(appVersion);
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
        bulbDurationSlider = findViewById(R.id.bulb_duration);
        bulbDurationValueView = findViewById(R.id.bulb_duration_value);
        isoSpinner = findViewById(R.id.iso_spinner);
        whiteBalanceSpinner = findViewById(R.id.white_balance_spinner);
        formatSpinner = findViewById(R.id.capture_format_spinner);
        exportJpegButton = findViewById(R.id.export_jpeg);
        updatePreviewButton = findViewById(R.id.update_preview);
        downloadSessionJpegsButton = findViewById(R.id.download_session_jpegs);
        finalizeSessionButton = findViewById(R.id.finalize_session);
        sessionCameraStatusView = findViewById(R.id.session_camera_status);
        thumbnailStrip = findViewById(R.id.capture_thumbnails);
        sequenceProgressView = findViewById(R.id.sequence_progress);
        acceptedCountView = findViewById(R.id.accepted_count);
        exposureMetricView = findViewById(R.id.exposure_metric);
        nextCaptureView = findViewById(R.id.next_capture);
        exposureCapabilitiesView = findViewById(R.id.exposure_capabilities);
        previewView = findViewById(R.id.preview);
        previewPlaceholder = findViewById(R.id.preview_placeholder);

        findViewById(R.id.refresh).setOnClickListener(view -> {
            appendEvent("Varredura manual solicitada");
            refreshProbe();
        });
        authorizeButton.setOnClickListener(view -> requestUsbPermission());
        gphotoProbeButton.setOnClickListener(view -> runGPhotoProbe());
        captureButton.setOnClickListener(view -> runGPhotoCapture());
        startSequenceButton.setOnClickListener(view -> {
            if (sequenceRunning) {
                pauseAstroSequence();
            } else {
                startGPhotoSequence();
            }
        });
        cancelSequenceButton.setOnClickListener(view -> cancelAstroSequence());
        inspectMtpButton.setOnClickListener(view -> runMtpProbe(false));
        inspectControlsButton.setOnClickListener(view -> inspectExposureCapabilities());
        applyControlsButton.setOnClickListener(view -> applyExposureControls());
        downloadLatestButton.setOnClickListener(view -> runMtpProbe(true));
        copyLogButton.setOnClickListener(view -> copyLog());
        shareLogButton.setOnClickListener(view -> shareLog());
        exportJpegButton.setOnClickListener(view -> exportSelectedJpeg());
        updatePreviewButton.setOnClickListener(view -> requestNextPreview());
        downloadSessionJpegsButton.setOnClickListener(view -> downloadSessionJpegs());
        finalizeSessionButton.setOnClickListener(view -> finalizeActiveSession());
        findViewById(R.id.create_session).setOnClickListener(view -> createSession());
        findViewById(R.id.back_to_sessions).setOnClickListener(view -> returnToSessionCatalog());
        bulbDurationSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {}
            @Override public void onProgressChanged(SeekBar seekBar, int seconds, boolean fromUser) {
                int duration = ExposureDurationPolicy.clamp(seconds);
                bulbDurationValueView.setText(getString(R.string.seconds_value, duration));
                if (!sequenceRunning) {
                    exposureMetricView.setText(getString(R.string.seconds_value, duration));
                }
            }
        });

        configureAstroControlAdapters();
        showSessionCatalog();

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
        IntentFilter serviceFilter = new IntentFilter(AstroCaptureService.ACTION_STATE_CHANGED);
        registerReceiver(astroServiceReceiver, serviceFilter, Context.RECEIVER_NOT_EXPORTED);
        serviceReceiverRegistered = true;
        applyAstroServiceSnapshot(AstroCaptureService.currentSnapshot());
        refreshProbe();
    }

    @Override
    protected void onStop() {
        if (receiverRegistered) {
            unregisterReceiver(usbReceiver);
            receiverRegistered = false;
        }
        if (serviceReceiverRegistered) {
            unregisterReceiver(astroServiceReceiver);
            serviceReceiverRegistered = false;
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
        countdownGeneration++;
        mainHandler.removeCallbacksAndMessages(null);
        cameraExecutor.shutdownNow();
        closeGPhotoConnection();
        super.onDestroy();
    }

    private void handleLaunchIntent(Intent intent) {
        if (intent != null && UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(intent.getAction())) {
            appendEvent("Aberto pelo Android após conexão USB" + deviceSuffix(readUsbDevice(intent)));
        }
    }

    private File sessionsRoot() {
        File pictures = getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        if (pictures == null) pictures = getFilesDir();
        return new File(pictures, "CameraeAstro");
    }

    private void showSessionCatalog() {
        captureScreen.setVisibility(View.GONE);
        sessionCatalogScreen.setVisibility(View.VISIBLE);
        renderSessionCatalog();
        refreshProbe();
    }

    private void renderSessionCatalog() {
        List<AstroUsbSessionStore.Session> sessions = AstroUsbSessionStore.list(sessionsRoot());
        sessionListView.removeAllViews();
        sessionCountView.setText(getResources().getQuantityString(
                R.plurals.session_count,
                sessions.size(),
                sessions.size()
        ));
        sessionsEmptyView.setVisibility(sessions.isEmpty() ? View.VISIBLE : View.GONE);
        for (AstroUsbSessionStore.Session session : sessions) {
            sessionListView.addView(createSessionCard(session));
        }
    }

    private View createSessionCard(AstroUsbSessionStore.Session session) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(12), dp(12), dp(10), dp(12));
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(8, 13, 36));
        background.setCornerRadius(dp(16));
        background.setStroke(dp(1), Color.rgb(27, 43, 94));
        card.setBackground(background);
        LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(116)
        );
        cardParams.setMargins(0, 0, 0, dp(10));
        card.setLayoutParams(cardParams);

        ImageView thumbnail = new ImageView(this);
        thumbnail.setScaleType(ImageView.ScaleType.CENTER_CROP);
        thumbnail.setBackgroundResource(R.drawable.bg_astro_preview);
        LinearLayout.LayoutParams thumbnailParams = new LinearLayout.LayoutParams(dp(78), dp(92));
        thumbnailParams.setMarginEnd(dp(12));
        thumbnail.setLayoutParams(thumbnailParams);
        File localJpeg = AstroUsbSessionStore.latestLocalJpeg(session);
        if (localJpeg != null) {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = 8;
            thumbnail.setImageBitmap(BitmapFactory.decodeFile(localJpeg.getAbsolutePath(), options));
        }
        card.addView(thumbnail);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_VERTICAL);
        content.setLayoutParams(new LinearLayout.LayoutParams(0, dp(92), 1));
        content.addView(catalogText(session.title, 15, Color.rgb(232, 238, 255), true));
        content.addView(catalogText(
                new SimpleDateFormat("dd MMM yyyy · HH:mm", Locale.getDefault())
                        .format(new Date(session.updatedAtMillis)),
                12, Color.rgb(128, 144, 192), false
        ));
        content.addView(catalogText(
                session.captureCount + " FOTOS · " + session.format + " · "
                        + session.bulbSeconds + " S",
                10, Color.rgb(77, 111, 255), false
        ));
        content.addView(catalogText(sessionStatusLabel(session),
                10, Color.rgb(128, 144, 192), false));
        card.addView(content);

        Button delete = new Button(this);
        delete.setText(R.string.delete_session_short);
        delete.setTextSize(11);
        delete.setTextColor(Color.rgb(255, 93, 93));
        delete.setAllCaps(false);
        delete.setBackgroundResource(R.drawable.bg_astro_pill);
        delete.setLayoutParams(new LinearLayout.LayoutParams(dp(72), dp(44)));
        delete.setOnClickListener(view -> confirmDeleteSession(session));
        card.addView(delete);
        card.setOnClickListener(view -> openSession(session));
        return card;
    }

    private TextView catalogText(String text, int size, int color, boolean strong) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setMaxLines(1);
        view.setEllipsize(android.text.TextUtils.TruncateAt.END);
        if (strong) view.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        return view;
    }

    private String sessionStatusLabel(AstroUsbSessionStore.Session session) {
        if ("capturing".equals(session.status)) return "INTERROMPIDA · PODE CONTINUAR";
        if ("paused".equals(session.status)) return "PAUSADA · PODE CONTINUAR";
        if ("finalized".equals(session.status)) return "FINALIZADA · ABRIR OU IMPORTAR";
        return "PRONTA PARA CAPTURAR";
    }

    private void createSession() {
        try {
            openSession(AstroUsbSessionStore.create(sessionsRoot()));
        } catch (IOException error) {
            Toast.makeText(this, "Falha ao criar sessão: " + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void openSession(AstroUsbSessionStore.Session session) {
        activeSession = session;
        activeSequenceDirectory = session.directory;
        activeSequenceCompletedCount = session.captureCount;
        pendingJpegCameraFiles.clear();
        pendingJpegCameraFiles.addAll(session.pendingJpegs);
        allCameraFiles.clear();
        allCameraFiles.addAll(session.cameraFiles);
        sessionCameraVerified = false;
        thumbnailStrip.removeAllViews();
        previewView.setVisibility(View.GONE);
        previewPlaceholder.setVisibility(View.VISIBLE);
        File localJpeg = AstroUsbSessionStore.latestLocalJpeg(session);
        if (localJpeg != null) {
            addCapturedFilesFromReport("FILE|" + localJpeg.getAbsolutePath() + "|image/jpeg\n");
        }
        selectSpinnerValue(isoSpinner, session.iso);
        selectSpinnerValue(whiteBalanceSpinner, session.whiteBalance);
        selectSpinnerValue(formatSpinner, session.format);
        setBulbDurationSeconds(session.bulbSeconds);
        sequenceIntervalInput.setText(String.valueOf(session.intervalSeconds));
        acceptedCountView.setText(String.valueOf(session.captureCount));
        exposureMetricView.setText(getString(R.string.seconds_value, selectedBulbSeconds()));
        nextCaptureView.setText("—");
        sequenceProgressView.setText(session.captureCount == 0
                ? getString(R.string.sequence_idle)
                : session.captureCount + " capturas registradas");
        sessionCameraStatusView.setText(allCameraFiles.isEmpty()
                ? R.string.session_card_no_remote_files
                : R.string.session_card_waiting_check);
        sessionCatalogScreen.setVisibility(View.GONE);
        captureScreen.setVisibility(View.VISIBLE);
        appendEvent("Sessão aberta: " + session.id + " com " + session.captureCount + " capturas");
        AstroCaptureService.Snapshot snapshot = AstroCaptureService.currentSnapshot();
        if (snapshot.belongsTo(session.directory)) {
            applyAstroServiceSnapshot(snapshot);
        } else {
            refreshProbe();
        }
    }

    private void returnToSessionCatalog() {
        if (sequenceRunning) {
            Toast.makeText(this, R.string.pause_before_leaving, Toast.LENGTH_SHORT).show();
            return;
        }
        persistActiveSession(activeSession != null && "finalized".equals(activeSession.status)
                ? "finalized"
                : activeSequenceCompletedCount > 0 ? "paused" : "draft");
        showSessionCatalog();
    }

    private void finalizeActiveSession() {
        if (activeSession == null || sequenceRunning) return;
        AstroCaptureService.Snapshot snapshot = AstroCaptureService.currentSnapshot();
        if (snapshot.belongsTo(activeSession.directory)
                && AstroCapturePolicy.shouldRemainForeground(snapshot.state)) {
            startService(AstroCaptureService.finalizeIntent(this));
            sequenceProgressView.setText("Finalizando sessão…");
            return;
        }
        persistActiveSession("finalized");
        appendEvent("Sessão finalizada: " + activeSession.id);
        activeSession = null;
        activeSequenceDirectory = null;
        showSessionCatalog();
    }

    private void confirmDeleteSession(AstroUsbSessionStore.Session session) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.delete_session_title)
                .setMessage(R.string.delete_session_message)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.delete_session_confirm, (dialog, which) -> {
                    if (AstroUsbSessionStore.delete(session)) {
                        renderSessionCatalog();
                    } else {
                        Toast.makeText(this, R.string.delete_session_failed, Toast.LENGTH_LONG).show();
                    }
                })
                .show();
    }

    private void persistActiveSession(String status) {
        if (activeSession == null) return;
        activeSession.status = status;
        activeSession.captureCount = activeSequenceCompletedCount;
        activeSession.iso = String.valueOf(isoSpinner.getSelectedItem());
        activeSession.whiteBalance = String.valueOf(whiteBalanceSpinner.getSelectedItem());
        activeSession.format = String.valueOf(formatSpinner.getSelectedItem());
        activeSession.bulbSeconds = selectedBulbSeconds();
        activeSession.intervalSeconds = parseIntOrDefault(sequenceIntervalInput, 10);
        activeSession.cameraFiles.clear();
        activeSession.cameraFiles.addAll(allCameraFiles);
        activeSession.pendingJpegs.clear();
        activeSession.pendingJpegs.addAll(pendingJpegCameraFiles);
        try {
            AstroUsbSessionStore.save(activeSession);
        } catch (IOException error) {
            appendEvent("Falha salvando sessão: " + error.getMessage());
        }
    }

    private void applyAstroServiceSnapshot(AstroCaptureService.Snapshot snapshot) {
        if (activeSession == null || !snapshot.belongsTo(activeSession.directory)) return;

        try {
            activeSession = AstroUsbSessionStore.load(activeSession.directory);
            activeSequenceDirectory = activeSession.directory;
            pendingJpegCameraFiles.clear();
            pendingJpegCameraFiles.addAll(activeSession.pendingJpegs);
            allCameraFiles.clear();
            allCameraFiles.addAll(activeSession.cameraFiles);
        } catch (IOException error) {
            appendEvent("Falha atualizando sessão em segundo plano: " + error.getMessage());
        }

        activeSequenceCompletedCount = snapshot.completedCount;
        sequenceRunning = snapshot.isRunning();
        sequenceCancelRequested = snapshot.state == AstroCapturePolicy.State.PAUSING;
        cameraBusy = snapshot.isOperatingCamera();
        previewRefreshRequested = snapshot.previewRequested;
        acceptedCountView.setText(String.valueOf(snapshot.completedCount));
        exposureMetricView.setText(snapshot.bulbSeconds + " s");
        sequenceProgressView.setText(snapshot.phase);
        nextCaptureView.setText(snapshot.remainingSeconds > 0
                ? snapshot.remainingSeconds + " s"
                : snapshot.state == AstroCapturePolicy.State.PAUSED ? "pausada"
                : snapshot.state == AstroCapturePolicy.State.FAILED ? "falhou"
                : snapshot.state == AstroCapturePolicy.State.FINALIZED ? "finalizada"
                : "processando");
        if (!snapshot.captureReport.isEmpty()) {
            captureReport = snapshot.captureReport;
            hasCaptureLog = true;
        }
        if (snapshot.previewPath != null
                && !snapshot.previewPath.equals(lastServicePreviewPath)) {
            lastServicePreviewPath = snapshot.previewPath;
            addCapturedFilesFromReport("FILE|" + snapshot.previewPath + "|image/jpeg\n");
        }
        sequenceReport = "SESSÃO ASTRO EM SEGUNDO PLANO\nEstado: "
                + snapshot.state.name().toLowerCase(Locale.US)
                + "\nConcluídas: " + snapshot.completedCount
                + "\nPasta: " + snapshot.sessionDirectory + "\n";

        if (snapshot.state == AstroCapturePolicy.State.FINALIZED) {
            appendEvent("Sessão finalizada pelo serviço em segundo plano");
            activeSession = null;
            activeSequenceDirectory = null;
            showSessionCatalog();
            return;
        }
        refreshProbe();
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
                || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }
        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1400);
        Toast.makeText(this, R.string.notification_permission_notice, Toast.LENGTH_LONG).show();
    }

    private static int parseIntOrDefault(EditText input, int fallback) {
        try {
            return Integer.parseInt(input.getText().toString().trim());
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private int selectedBulbSeconds() {
        return ExposureDurationPolicy.clamp(bulbDurationSlider.getProgress());
    }

    private void setBulbDurationSeconds(int seconds) {
        int duration = ExposureDurationPolicy.clamp(seconds);
        bulbDurationSlider.setProgress(duration);
        bulbDurationValueView.setText(getString(R.string.seconds_value, duration));
        if (!sequenceRunning) {
            exposureMetricView.setText(getString(R.string.seconds_value, duration));
        }
    }

    private void selectSpinnerValue(Spinner spinner, String value) {
        if (spinner.getAdapter() == null) return;
        for (int index = 0; index < spinner.getAdapter().getCount(); index++) {
            if (value.equals(String.valueOf(spinner.getAdapter().getItem(index)))) {
                spinner.setSelection(index);
                return;
            }
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void applyCaptureSettingsAvailability(
            CaptureSettingsAvailabilityPolicy.State state
    ) {
        boolean enabled = state.isEnabled();
        captureSettingsControls.setAlpha(enabled ? 1f : 0.38f);
        setViewTreeEnabled(captureSettingsControls, enabled);
        if (enabled) {
            captureSettingsAvailabilityView.setVisibility(View.GONE);
            return;
        }
        int message = switch (state) {
            case USB_PERMISSION_REQUIRED -> R.string.capture_settings_usb_required;
            case UNSUPPORTED_CAMERA -> R.string.capture_settings_unsupported;
            case CAMERA_BUSY -> R.string.capture_settings_busy;
            case SESSION_FINALIZED -> R.string.capture_settings_finalized;
            default -> R.string.capture_settings_camera_required;
        };
        captureSettingsAvailabilityView.setText(message);
        captureSettingsAvailabilityView.setVisibility(View.VISIBLE);
    }

    private static void setViewTreeEnabled(View view, boolean enabled) {
        view.setEnabled(enabled);
        if (!(view instanceof ViewGroup group)) return;
        for (int index = 0; index < group.getChildCount(); index++) {
            setViewTreeEnabled(group.getChildAt(index), enabled);
        }
    }

    private void refreshProbe() {
        if (usbManager == null) {
            statusView.setText(R.string.status_usb_service_missing);
            authorizeButton.setEnabled(false);
            captureButton.setEnabled(false);
            startSequenceButton.setEnabled(false);
            applyCaptureSettingsAvailability(
                    CaptureSettingsAvailabilityPolicy.State.CAMERA_MISSING
            );
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
                    ? getString(R.string.status_ready, cameraDisplayName(selected))
                    : getString(R.string.status_import_only, cameraDisplayName(selected)));
        } else {
            statusView.setText(getString(
                    R.string.status_permission_required,
                    cameraDisplayName(selected)
            ));
        }
        catalogCameraStatusView.setText(statusView.getText());
        boolean cameraPresent = selected != null;
        boolean cameraReady = selected != null && usbManager.hasPermission(selected);
        boolean captureValidated = cameraReady && isValidatedCaptureDevice(selected);
        boolean finalizedSession = activeSession != null
                && "finalized".equals(activeSession.status);
        CaptureSettingsAvailabilityPolicy.State captureSettingsState =
                CaptureSettingsAvailabilityPolicy.evaluate(
                        cameraPresent,
                        cameraReady,
                        selected != null && isValidatedCaptureDevice(selected),
                        cameraBusy,
                        finalizedSession
                );
        applyCaptureSettingsAvailability(captureSettingsState);
        authorizeButton.setEnabled(selected != null && !usbManager.hasPermission(selected) && !cameraBusy);
        gphotoProbeButton.setEnabled(captureValidated && !cameraBusy && !gphotoProbeCompleted);
        captureButton.setEnabled(captureValidated && !cameraBusy);
        inspectMtpButton.setEnabled(cameraReady && !cameraBusy);
        inspectControlsButton.setEnabled(false);
        applyControlsButton.setEnabled(false);
        boolean captureSettingsEnabled = captureSettingsState.isEnabled();
        isoSpinner.setEnabled(captureSettingsEnabled);
        whiteBalanceSpinner.setEnabled(captureSettingsEnabled);
        formatSpinner.setEnabled(captureSettingsEnabled);
        bulbDurationSlider.setEnabled(captureSettingsEnabled);
        exportJpegButton.setEnabled(selectedJpeg != null && !cameraBusy);
        updatePreviewButton.setEnabled(sequenceRunning && !previewRefreshRequested);
        updatePreviewButton.setText(previewRefreshRequested
                ? R.string.preview_waiting
                : R.string.update_preview);
        downloadSessionJpegsButton.setEnabled(
                !cameraBusy && !pendingJpegCameraFiles.isEmpty()
        );
        downloadSessionJpegsButton.setText(getString(
                R.string.download_session_jpegs_count,
                pendingJpegCameraFiles.size()
        ));
        downloadLatestButton.setEnabled(cameraReady && !cameraBusy);
        startSequenceButton.setEnabled(activeSession != null && !finalizedSession
                && captureValidated && (!cameraBusy || sequenceRunning));
        startSequenceButton.setText(finalizedSession
                ? R.string.finalized_session
                : sequenceRunning
                ? (sequenceCancelRequested ? R.string.pausing_sequence : R.string.pause_sequence)
                : (activeSequenceCompletedCount > 0
                ? R.string.resume_sequence
                : R.string.start_sequence));
        finalizeSessionButton.setVisibility(activeSession != null && !finalizedSession
                && activeSequenceCompletedCount > 0 && !sequenceRunning
                ? View.VISIBLE : View.GONE);
        finalizeSessionButton.setEnabled(!cameraBusy && !sequenceRunning);
        cancelSequenceButton.setEnabled(sequenceRunning && !sequenceCancelRequested);
        sequenceCountInput.setEnabled(!cameraBusy);
        sequenceDelayInput.setEnabled(!cameraBusy);
        sequenceIntervalInput.setEnabled(captureSettingsEnabled);
        copyLogButton.setEnabled(!cameraBusy);
        authorizeButton.setVisibility(authorizeButton.isEnabled() ? View.VISIBLE : View.GONE);
        shareLogButton.setEnabled(!cameraBusy && hasCaptureLog);

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
        if (activeSession != null && captureScreen.getVisibility() == View.VISIBLE
                && cameraReady && !cameraBusy && !sessionCameraVerified
                && !allCameraFiles.isEmpty()) {
            sessionCameraVerified = true;
            verifyActiveSessionOnCamera(cameraDisplayName(selected));
        }
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
                this, R.layout.spinner_item_astro, isoValues));
        whiteBalanceSpinner.setAdapter(new ArrayAdapter<>(
                this, R.layout.spinner_item_astro, whiteBalanceValues));
        formatSpinner.setAdapter(new ArrayAdapter<>(
                this, R.layout.spinner_item_astro, formatValues));
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
        int bulbSeconds = selectedBulbSeconds();

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
                        bulbSeconds,
                        true
                );
                PersistentProbeLog.append("GPHOTO2-CAPTURE", result);
                runOnUiThread(() -> {
                    captureReport = result.endsWith("\n") ? result : result + "\n";
                    addCapturedFilesFromReport(result);
                    gphotoProbeCompleted = true;
                    cameraBusy = false;
                    int expectedFiles = "JPG+CR3".equals(format) ? 2 : 1;
                    boolean completed = result.contains(
                            "Arquivos registrados no cartão: " + expectedFiles + "/" + expectedFiles
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
            if (thumbnailStrip.getChildCount() > MAX_VISIBLE_THUMBNAILS) {
                thumbnailStrip.removeViewAt(thumbnailStrip.getChildCount() - 1);
            }
            selectJpeg(file);
        }
    }

    private void collectPendingJpegsFromReport(String report) {
        Set<String> downloadedNames = downloadedFileNames(report);
        for (String line : report.split("\\n")) {
            if (!line.startsWith("CAMERA|")) continue;
            String[] components = line.split("\\|", 3);
            if (components.length < 3 || !isJpegName(components[2])) continue;
            String cameraFile = components[1] + "|" + components[2];
            if (!downloadedNames.contains(components[2])
                    && !pendingJpegCameraFiles.contains(cameraFile)) {
                pendingJpegCameraFiles.add(cameraFile);
            }
        }
    }

    private void collectSessionCameraFiles(String report) {
        for (String line : report.split("\\n")) {
            if (!line.startsWith("CAMERA|")) continue;
            String[] components = line.split("\\|", 3);
            if (components.length < 3) continue;
            String cameraFile = components[1] + "|" + components[2];
            if (!allCameraFiles.contains(cameraFile)) allCameraFiles.add(cameraFile);
        }
        sessionCameraVerified = true;
    }

    private void requestNextPreview() {
        AstroCaptureService.Snapshot snapshot = AstroCaptureService.currentSnapshot();
        if (!sequenceRunning || previewRefreshRequested || activeSession == null
                || !snapshot.belongsTo(activeSession.directory)) return;
        previewRefreshRequested = true;
        startService(AstroCaptureService.refreshPreviewIntent(this));
        updatePreviewButton.setText(R.string.preview_waiting);
        Toast.makeText(this, R.string.preview_waiting_notice, Toast.LENGTH_SHORT).show();
        appendEvent("Atualização da prévia solicitada para a próxima captura");
        refreshProbe();
    }

    private void downloadSessionJpegs() {
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)
                || activeSequenceDirectory == null || pendingJpegCameraFiles.isEmpty()) {
            return;
        }
        List<String> requestedFiles = new ArrayList<>(pendingJpegCameraFiles);
        String encodedFiles = String.join("\n", requestedFiles);
        int requestedCount = requestedFiles.size();
        cameraBusy = true;
        sequenceProgressView.setText("Baixando " + requestedCount + " JPGs do cartão…");
        appendEvent("Importação pós-sessão iniciada: " + requestedCount + " JPGs");
        refreshProbe();
        cameraExecutor.execute(() -> {
            try {
                if (gphotoConnection == null) gphotoConnection = usbManager.openDevice(device);
                if (gphotoConnection == null) throw new IOException("UsbManager.openDevice retornou null");
                String result = NativeGPhotoClient.downloadFiles(
                        getApplicationContext(),
                        gphotoConnection.getFileDescriptor(),
                        activeSequenceDirectory,
                        encodedFiles
                );
                PersistentProbeLog.append("GPHOTO2-IMPORT", result);
                runOnUiThread(() -> {
                    captureReport = result.endsWith("\n") ? result : result + "\n";
                    addCapturedFilesFromReport(result);
                    removeDownloadedCameraFiles(result);
                    cameraBusy = false;
                    int downloadedCount = requestedCount - pendingJpegCameraFiles.size();
                    sequenceProgressView.setText(downloadedCount + " JPGs baixados para o aparelho");
                    appendEvent("Importação pós-sessão concluída: " + downloadedCount
                            + "/" + requestedCount + " JPGs");
                    persistActiveSession(activeSession == null ? "paused" : activeSession.status);
                    refreshProbe();
                });
            } catch (Throwable error) {
                PersistentProbeLog.append("GPHOTO2-IMPORT", "Falha: " + error);
                runOnUiThread(() -> {
                    cameraBusy = false;
                    sequenceProgressView.setText("Falha ao baixar JPGs: " + error.getMessage());
                    appendEvent("Importação pós-sessão falhou: " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private void verifyActiveSessionOnCamera(String cameraLabel) {
        if (activeSession == null || allCameraFiles.isEmpty()) return;
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)) return;
        String encodedFiles = String.join("\n", allCameraFiles);
        int expected = allCameraFiles.size();
        cameraBusy = true;
        sessionCameraStatusView.setText(R.string.session_card_checking);
        appendEvent("Verificando " + expected + " arquivos da sessão no cartão");
        refreshProbe();
        cameraExecutor.execute(() -> {
            try {
                if (gphotoConnection == null) gphotoConnection = usbManager.openDevice(device);
                if (gphotoConnection == null) throw new IOException("UsbManager.openDevice retornou null");
                String result = NativeGPhotoClient.checkFiles(
                        getApplicationContext(),
                        gphotoConnection.getFileDescriptor(),
                        encodedFiles
                );
                PersistentProbeLog.append("GPHOTO2-SESSION-CHECK", result);
                int present = countReportLines(result, "PRESENT|");
                runOnUiThread(() -> {
                    cameraBusy = false;
                    sessionCameraStatusView.setText(getString(
                            R.string.session_card_check_result,
                            present,
                            expected,
                            cameraLabel
                    ));
                    appendEvent("Sessão verificada no cartão: " + present + "/" + expected);
                    refreshProbe();
                });
            } catch (Throwable error) {
                runOnUiThread(() -> {
                    cameraBusy = false;
                    sessionCameraStatusView.setText("Não foi possível verificar o cartão: "
                            + error.getMessage());
                    appendEvent("Verificação da sessão falhou: " + error.getMessage());
                    refreshProbe();
                });
            }
        });
    }

    private static int countReportLines(String report, String prefix) {
        int count = 0;
        for (String line : report.split("\\n")) if (line.startsWith(prefix)) count++;
        return count;
    }

    private void removeDownloadedCameraFiles(String report) {
        Set<String> downloadedNames = downloadedFileNames(report);
        pendingJpegCameraFiles.removeIf(cameraFile -> {
            int separator = cameraFile.lastIndexOf('|');
            return separator >= 0 && downloadedNames.contains(cameraFile.substring(separator + 1));
        });
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

    private void selectJpeg(File file) {
        selectedJpeg = file;
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = 4;
        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
        if (bitmap != null) {
            previewView.setImageBitmap(bitmap);
            previewView.setVisibility(View.VISIBLE);
            previewPlaceholder.setVisibility(View.GONE);
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
        if (sequenceRunning) {
            pauseAstroSequence();
            return;
        }
        if (activeSession == null) {
            Toast.makeText(this, R.string.create_session_first, Toast.LENGTH_SHORT).show();
            showSessionCatalog();
            return;
        }
        UsbDevice device = selectCamera();
        if (device == null || !usbManager.hasPermission(device)
                || !isValidatedCaptureDevice(device)) {
            appendEvent("Sessão não iniciada: EOS R ausente ou sem permissão USB");
            refreshProbe();
            return;
        }
        Integer intervalSeconds = readSequenceValue(sequenceIntervalInput, 1, 86400, "Intervalo");
        if (intervalSeconds == null) return;

        int bulbSeconds = selectedBulbSeconds();
        String iso = String.valueOf(isoSpinner.getSelectedItem());
        String whiteBalance = String.valueOf(whiteBalanceSpinner.getSelectedItem());
        String format = String.valueOf(formatSpinner.getSelectedItem());

        cameraBusy = true;
        sequenceRunning = true;
        sequenceCancelRequested = false;
        sequenceReport = "SESSÃO ASTRO LIBGPHOTO2\nEstado: capturando\nConcluídas: "
                + activeSequenceCompletedCount + "\nPasta: " + activeSequenceDirectory + "\n";
        sequenceProgressView.setText(activeSequenceCompletedCount == 0
                ? "Preparando a primeira captura…"
                : "Retomando após " + activeSequenceCompletedCount + " capturas…");
        acceptedCountView.setText(String.valueOf(activeSequenceCompletedCount));
        exposureMetricView.setText(bulbSeconds + " s");
        nextCaptureView.setText("agora");
        appendEvent("Sessão astro iniciada/retomada: intervalo " + intervalSeconds
                + " s, Bulb " + bulbSeconds + " s, " + format
                + "; modo tela apagada ativo");
        persistActiveSession("capturing");
        closeGPhotoConnection();
        requestNotificationPermissionIfNeeded();
        Intent service = AstroCaptureService.startIntent(
                this,
                activeSequenceDirectory,
                device.getDeviceName(),
                iso,
                whiteBalance,
                format,
                bulbSeconds,
                intervalSeconds
        );
        startForegroundService(service);
        refreshProbe();
    }

    private void pauseAstroSequence() {
        if (!sequenceRunning || sequenceCancelRequested) return;
        sequenceCancelRequested = true;
        startService(AstroCaptureService.pauseIntent(this));
        sequenceProgressView.setText("Pausa solicitada · concluindo a captura atual…");
        if (!captureCountdownActive) nextCaptureView.setText("pausando");
        appendEvent("Pausa da sessão solicitada");
        refreshProbe();
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
        pauseAstroSequence();
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

    private boolean waitUntilOrCanceledWithCountdown(long targetElapsedTime) {
        long displayedSeconds = Long.MIN_VALUE;
        while (!sequenceCancelRequested) {
            long remaining = targetElapsedTime - SystemClock.elapsedRealtime();
            if (remaining <= 0) {
                runOnUiThread(() -> nextCaptureView.setText("agora"));
                return true;
            }
            long seconds = Math.max(1, (remaining + 999) / 1000);
            if (seconds != displayedSeconds) {
                displayedSeconds = seconds;
                long shown = seconds;
                runOnUiThread(() -> nextCaptureView.setText(shown + " s"));
            }
            SystemClock.sleep(Math.min(remaining, 200));
        }
        return false;
    }

    private void startExposureCountdown(int seconds) {
        captureCountdownActive = true;
        int generation = ++countdownGeneration;
        long deadline = SystemClock.elapsedRealtime() + seconds * 1000L;
        Runnable tick = new Runnable() {
            @Override public void run() {
                if (generation != countdownGeneration) return;
                long remaining = deadline - SystemClock.elapsedRealtime();
                if (remaining <= 0) {
                    captureCountdownActive = false;
                    nextCaptureView.setText("processando");
                    return;
                }
                long shownSeconds = Math.max(1, (remaining + 999) / 1000);
                nextCaptureView.setText(shownSeconds + " s");
                mainHandler.postDelayed(this, Math.min(remaining, 200));
            }
        };
        mainHandler.post(tick);
    }

    private void stopActiveCountdown(String replacement) {
        countdownGeneration++;
        captureCountdownActive = false;
        nextCaptureView.setText(replacement);
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
        return selectedBulbSeconds() * 1000L;
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
            previewPlaceholder.setVisibility(View.VISIBLE);
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
            previewPlaceholder.setVisibility(View.VISIBLE);
            appendEvent("JPEG baixado, mas o preview não pôde ser decodificado");
            return;
        }
        previewView.setImageBitmap(bitmap);
        previewView.setVisibility(View.VISIBLE);
        previewPlaceholder.setVisibility(View.GONE);
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

    private static String cameraDisplayName(UsbDevice device) {
        if (isValidatedCaptureDevice(device)) return "Canon EOS R";
        if (device == null) return "Câmera USB";
        String product = device.getProductName();
        String manufacturer = device.getManufacturerName();
        if (product != null && !product.trim().isEmpty()
                && !"Canon Digital Camera".equalsIgnoreCase(product.trim())) {
            return product.trim();
        }
        if (manufacturer != null && !manufacturer.trim().isEmpty()) {
            return manufacturer.trim() + " câmera USB";
        }
        return "Câmera USB";
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

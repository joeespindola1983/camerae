package com.camerae.eosrprobe;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class AstroCaptureService extends Service {
    static final String ACTION_STATE_CHANGED =
            "com.camerae.eosrprobe.action.ASTRO_STATE_CHANGED";
    private static final String ACTION_START =
            "com.camerae.eosrprobe.action.START_ASTRO";
    private static final String ACTION_PAUSE =
            "com.camerae.eosrprobe.action.PAUSE_ASTRO";
    private static final String ACTION_RESUME =
            "com.camerae.eosrprobe.action.RESUME_ASTRO";
    private static final String ACTION_FINALIZE =
            "com.camerae.eosrprobe.action.FINALIZE_ASTRO";
    private static final String ACTION_REFRESH_PREVIEW =
            "com.camerae.eosrprobe.action.REFRESH_ASTRO_PREVIEW";

    private static final String EXTRA_SESSION_DIRECTORY = "sessionDirectory";
    private static final String EXTRA_DEVICE_NAME = "deviceName";
    private static final String EXTRA_ISO = "iso";
    private static final String EXTRA_WHITE_BALANCE = "whiteBalance";
    private static final String EXTRA_FORMAT = "format";
    private static final String EXTRA_BULB_SECONDS = "bulbSeconds";
    private static final String EXTRA_INTERVAL_SECONDS = "intervalSeconds";

    private static final String CHANNEL_ID = "astro_capture_session";
    private static final int NOTIFICATION_ID = 1400;
    private static final int CANON_VENDOR_ID = 0x04A9;

    private static volatile Snapshot latestSnapshot = Snapshot.idle();

    private final ExecutorService captureExecutor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private UsbManager usbManager;
    private NotificationManager notificationManager;
    private PowerManager.WakeLock wakeLock;
    private UsbDeviceConnection connection;
    private AstroUsbSessionStore.Session session;
    private String deviceName;
    private String iso;
    private String whiteBalance;
    private String format;
    private int bulbSeconds;
    private int intervalSeconds;
    private volatile boolean workerRunning;
    private volatile boolean pauseRequested;
    private volatile boolean finalizeAfterPause;
    private volatile boolean previewRequested;
    private volatile int phaseGeneration;
    private volatile AstroCapturePolicy.State state = AstroCapturePolicy.State.IDLE;
    private volatile String phase = "Sessão inativa";
    private volatile int remainingSeconds = -1;
    private volatile String captureReport = "";
    private volatile String previewPath;

    private final BroadcastReceiver detachReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            UsbDevice detached = readUsbDevice(intent);
            if (detached == null || deviceName == null || deviceName.equals(detached.getDeviceName())) {
                pauseRequested = true;
                if (workerRunning) {
                    state = AstroCapturePolicy.State.PAUSING;
                    publish("Câmera desconectada · encerrando operação USB", remainingSeconds);
                } else if (session != null) {
                    state = AstroCapturePolicy.State.PAUSED;
                    persistSession("paused");
                    applyWakeLockPolicy();
                    publish("Câmera desconectada", -1);
                }
            }
        }
    };

    static Intent startIntent(
            Context context,
            File sessionDirectory,
            String deviceName,
            String iso,
            String whiteBalance,
            String format,
            int bulbSeconds,
            int intervalSeconds
    ) {
        return new Intent(context, AstroCaptureService.class)
                .setAction(ACTION_START)
                .putExtra(EXTRA_SESSION_DIRECTORY, sessionDirectory.getAbsolutePath())
                .putExtra(EXTRA_DEVICE_NAME, deviceName)
                .putExtra(EXTRA_ISO, iso)
                .putExtra(EXTRA_WHITE_BALANCE, whiteBalance)
                .putExtra(EXTRA_FORMAT, format)
                .putExtra(EXTRA_BULB_SECONDS, bulbSeconds)
                .putExtra(EXTRA_INTERVAL_SECONDS, intervalSeconds);
    }

    static Intent pauseIntent(Context context) {
        return new Intent(context, AstroCaptureService.class).setAction(ACTION_PAUSE);
    }

    static Intent finalizeIntent(Context context) {
        return new Intent(context, AstroCaptureService.class).setAction(ACTION_FINALIZE);
    }

    static Intent refreshPreviewIntent(Context context) {
        return new Intent(context, AstroCaptureService.class).setAction(ACTION_REFRESH_PREVIEW);
    }

    static Snapshot currentSnapshot() {
        return latestSnapshot;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CameraeAstro:CaptureSession"
        );
        wakeLock.setReferenceCounted(false);
        createNotificationChannel();
        IntentFilter filter = new IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED);
        registerReceiver(detachReceiver, filter, Context.RECEIVER_EXPORTED);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_START.equals(action)) {
            if (!workerRunning) {
                state = AstroCapturePolicy.State.STARTING;
                phase = "Preparando sessão Astro";
                ensureForeground();
                configureAndStart(intent);
            }
        } else if (ACTION_PAUSE.equals(action)) {
            requestPause(false);
        } else if (ACTION_RESUME.equals(action)) {
            resumeSession();
        } else if (ACTION_FINALIZE.equals(action)) {
            requestPause(true);
        } else if (ACTION_REFRESH_PREVIEW.equals(action)) {
            previewRequested = true;
            publish("Prévia solicitada para a próxima captura", remainingSeconds);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        pauseRequested = true;
        cancelPhaseTicker();
        closeConnection();
        releaseWakeLock();
        try {
            unregisterReceiver(detachReceiver);
        } catch (IllegalArgumentException ignored) {
        }
        captureExecutor.shutdownNow();
        super.onDestroy();
    }

    private void configureAndStart(Intent intent) {
        if (workerRunning) return;
        String sessionPath = intent.getStringExtra(EXTRA_SESSION_DIRECTORY);
        if (sessionPath == null) {
            failStartup("Diretório da sessão não informado");
            return;
        }
        File directory = new File(sessionPath);
        try {
            session = AstroUsbSessionStore.load(directory);
        } catch (IOException error) {
            failStartup("Sessão inválida: " + error.getMessage());
            return;
        }
        deviceName = intent.getStringExtra(EXTRA_DEVICE_NAME);
        iso = intent.getStringExtra(EXTRA_ISO);
        whiteBalance = intent.getStringExtra(EXTRA_WHITE_BALANCE);
        format = intent.getStringExtra(EXTRA_FORMAT);
        bulbSeconds = intent.getIntExtra(EXTRA_BULB_SECONDS, session.bulbSeconds);
        intervalSeconds = intent.getIntExtra(EXTRA_INTERVAL_SECONDS, session.intervalSeconds);
        session.iso = iso;
        session.whiteBalance = whiteBalance;
        session.format = format;
        session.bulbSeconds = bulbSeconds;
        session.intervalSeconds = intervalSeconds;
        beginRun();
    }

    private void failStartup(String message) {
        state = AstroCapturePolicy.State.FAILED;
        phase = message;
        publishSnapshot();
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void resumeSession() {
        if (workerRunning || session == null || !AstroCapturePolicy.canResume(state)) return;
        beginRun();
    }

    private void beginRun() {
        pauseRequested = false;
        finalizeAfterPause = false;
        state = AstroCapturePolicy.State.STARTING;
        phase = session.captureCount == 0
                ? "Preparando a primeira captura"
                : "Retomando após " + session.captureCount + " capturas";
        persistSession("capturing");
        workerRunning = true;
        ensureForeground();
        applyWakeLockPolicy();
        publish(phase, 0);
        captureExecutor.execute(this::runCaptureLoop);
    }

    private void runCaptureLoop() {
        int completed = session.captureCount;
        String failure = null;
        long scheduledAt = SystemClock.elapsedRealtime();
        try {
            UsbDevice device = selectCamera();
            if (device == null) throw new IOException("Canon não encontrada no USB");
            if (!usbManager.hasPermission(device)) {
                throw new IOException("permissão USB não está mais disponível");
            }
            connection = usbManager.openDevice(device);
            if (connection == null) throw new IOException("UsbManager.openDevice retornou null");
            if (!pauseRequested) {
                state = AstroCapturePolicy.State.RUNNING;
                applyWakeLockPolicy();
            }

            while (!pauseRequested) {
                if (!waitUntilScheduled(scheduledAt)) break;
                int captureNumber = completed + 1;
                boolean downloadPreview = AstroPreviewEnergyPolicy.shouldDownloadNextJpeg(
                        completed,
                        previewRequested
                );
                previewRequested = false;
                startPhaseTicker("Expondo a foto " + captureNumber, bulbSeconds);
                String result = NativeGPhotoClient.capture(
                        getApplicationContext(),
                        connection.getFileDescriptor(),
                        session.directory,
                        iso,
                        whiteBalance,
                        format,
                        bulbSeconds,
                        downloadPreview
                );
                cancelPhaseTicker();
                captureReport = result.endsWith("\n") ? result : result + "\n";
                PersistentProbeLog.append("GPHOTO2-BACKGROUND-" + captureNumber, result);
                int expectedFiles = "JPG+CR3".equals(format) ? 2 : 1;
                String successMarker = "Arquivos registrados no cartão: "
                        + expectedFiles + "/" + expectedFiles;
                if (!result.contains(successMarker)) {
                    failure = "captura " + captureNumber + " não completou " + successMarker;
                    break;
                }
                completed++;
                session.captureCount = completed;
                GPhotoCaptureReport.mergeIntoSession(result, session);
                String downloadedPreview = GPhotoCaptureReport.latestDownloadedJpeg(result);
                if (downloadedPreview != null) previewPath = downloadedPreview;
                persistSession("capturing");
                publish(completed + " capturas no cartão", intervalSeconds);
                scheduledAt = Math.max(
                        scheduledAt + intervalSeconds * 1000L,
                        SystemClock.elapsedRealtime()
                );
            }
        } catch (Throwable error) {
            failure = error.getClass().getSimpleName() + ": " + error.getMessage();
            PersistentProbeLog.append("GPHOTO2-BACKGROUND", "Falha: " + error);
        } finally {
            cancelPhaseTicker();
            closeConnection();
            workerRunning = false;
        }

        if (finalizeAfterPause) {
            finalizeNow();
        } else if (failure != null) {
            state = AstroCapturePolicy.State.FAILED;
            persistSession("failed");
            applyWakeLockPolicy();
            publish("Sessão falhou após " + completed + " capturas: " + failure, -1);
        } else {
            state = AstroCapturePolicy.State.PAUSED;
            persistSession("paused");
            applyWakeLockPolicy();
            publish("Sessão pausada após " + completed + " capturas", -1);
        }
    }

    private boolean waitUntilScheduled(long scheduledAt) {
        long lastShown = Long.MIN_VALUE;
        while (!pauseRequested) {
            long remainingMillis = scheduledAt - SystemClock.elapsedRealtime();
            if (remainingMillis <= 0) return true;
            int shown = (int) Math.max(1, (remainingMillis + 999L) / 1000L);
            if (shown != lastShown) {
                lastShown = shown;
                publish("Próxima captura", shown);
            }
            SystemClock.sleep(Math.min(remainingMillis, 200L));
        }
        return false;
    }

    private void requestPause(boolean finalize) {
        if (finalize) finalizeAfterPause = true;
        if (!workerRunning) {
            if (finalize) finalizeNow();
            return;
        }
        if (!AstroCapturePolicy.canPause(state) && state != AstroCapturePolicy.State.PAUSING) return;
        pauseRequested = true;
        state = AstroCapturePolicy.State.PAUSING;
        applyWakeLockPolicy();
        publish(finalize
                ? "Finalizando após a captura atual"
                : "Pausando após a captura atual", remainingSeconds);
    }

    private void finalizeNow() {
        if (session != null) persistSession("finalized");
        state = AstroCapturePolicy.State.FINALIZED;
        phase = "Sessão finalizada";
        remainingSeconds = -1;
        applyWakeLockPolicy();
        publishSnapshot();
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void persistSession(String status) {
        if (session == null) return;
        session.status = status;
        try {
            AstroUsbSessionStore.save(session);
        } catch (IOException error) {
            PersistentProbeLog.append("ASTRO-SERVICE", "Falha salvando sessão: " + error);
        }
    }

    private UsbDevice selectCamera() {
        UsbDevice canon = null;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            if (deviceName != null && deviceName.equals(device.getDeviceName())) return device;
            if (device.getVendorId() == CANON_VENDOR_ID) canon = device;
        }
        return canon;
    }

    private void publish(String newPhase, int newRemainingSeconds) {
        phase = newPhase;
        remainingSeconds = newRemainingSeconds;
        publishSnapshot();
        if (AstroCapturePolicy.shouldRemainForeground(state)) {
            notificationManager.notify(NOTIFICATION_ID, buildNotification());
        }
    }

    private void publishSnapshot() {
        latestSnapshot = new Snapshot(
                session == null ? null : session.directory.getAbsolutePath(),
                state,
                session == null ? 0 : session.captureCount,
                phase,
                remainingSeconds,
                captureReport,
                previewPath,
                previewRequested,
                session == null ? 0 : session.bulbSeconds
        );
        sendBroadcast(new Intent(ACTION_STATE_CHANGED).setPackage(getPackageName()));
    }

    private void startPhaseTicker(String label, int durationSeconds) {
        int generation = ++phaseGeneration;
        long deadline = SystemClock.elapsedRealtime() + durationSeconds * 1000L;
        Runnable tick = new Runnable() {
            @Override
            public void run() {
                if (generation != phaseGeneration) return;
                long remainingMillis = deadline - SystemClock.elapsedRealtime();
                if (remainingMillis <= 0) {
                    publish(pauseRequested ? "Pausando · processando captura" : "Processando captura", -1);
                    return;
                }
                int shown = (int) Math.max(1, (remainingMillis + 999L) / 1000L);
                publish(pauseRequested ? "Pausando após a captura atual" : label, shown);
                mainHandler.postDelayed(this, Math.min(remainingMillis, 1000L));
            }
        };
        mainHandler.post(tick);
    }

    private void cancelPhaseTicker() {
        phaseGeneration++;
    }

    @SuppressLint("WakelockTimeout")
    private void applyWakeLockPolicy() {
        if (AstroCapturePolicy.shouldHoldWakeLock(state)) {
            if (!wakeLock.isHeld()) wakeLock.acquire();
        } else {
            releaseWakeLock();
        }
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
    }

    private void closeConnection() {
        if (connection != null) {
            connection.close();
            connection = null;
        }
    }

    private void ensureForeground() {
        Notification notification = buildNotification();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            );
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private Notification buildNotification() {
        PendingIntent openApp = PendingIntent.getActivity(
                this,
                1,
                new Intent(this, MainActivity.class)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        Notification.Builder builder = new Notification.Builder(this, CHANNEL_ID);
        builder.setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(getString(R.string.astro_notification_title))
                .setContentText(notificationText())
                .setContentIntent(openApp)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setShowWhen(false);

        if (AstroCapturePolicy.canPause(state)) {
            builder.addAction(new Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    getString(R.string.pause_sequence),
                    serviceAction(ACTION_PAUSE, 2)
            ).build());
        } else if (AstroCapturePolicy.canResume(state)) {
            builder.addAction(new Notification.Action.Builder(
                    android.R.drawable.ic_media_play,
                    getString(R.string.resume_sequence),
                    serviceAction(ACTION_RESUME, 3)
            ).build());
        }
        builder.addAction(new Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.finalize_session),
                serviceAction(ACTION_FINALIZE, 4)
        ).build());
        return builder.build();
    }

    private PendingIntent serviceAction(String action, int requestCode) {
        return PendingIntent.getService(
                this,
                requestCode,
                new Intent(this, AstroCaptureService.class).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private String notificationText() {
        String count = session == null ? "" : session.captureCount + " fotos · ";
        String countdown = remainingSeconds > 0 ? " · " + remainingSeconds + " s" : "";
        return count + phase + countdown;
    }

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                getString(R.string.astro_notification_channel),
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription(getString(R.string.astro_notification_channel_description));
        notificationManager.createNotificationChannel(channel);
    }

    @SuppressWarnings("deprecation")
    private static UsbDevice readUsbDevice(Intent intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class);
        }
        return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
    }

    static final class Snapshot {
        final String sessionDirectory;
        final AstroCapturePolicy.State state;
        final int completedCount;
        final String phase;
        final int remainingSeconds;
        final String captureReport;
        final String previewPath;
        final boolean previewRequested;
        final int bulbSeconds;

        Snapshot(
                String sessionDirectory,
                AstroCapturePolicy.State state,
                int completedCount,
                String phase,
                int remainingSeconds,
                String captureReport,
                String previewPath,
                boolean previewRequested,
                int bulbSeconds
        ) {
            this.sessionDirectory = sessionDirectory;
            this.state = state;
            this.completedCount = completedCount;
            this.phase = phase;
            this.remainingSeconds = remainingSeconds;
            this.captureReport = captureReport;
            this.previewPath = previewPath;
            this.previewRequested = previewRequested;
            this.bulbSeconds = bulbSeconds;
        }

        static Snapshot idle() {
            return new Snapshot(
                    null,
                    AstroCapturePolicy.State.IDLE,
                    0,
                    "Sessão inativa",
                    -1,
                    "",
                    null,
                    false,
                    0
            );
        }

        boolean belongsTo(File directory) {
            return directory != null && sessionDirectory != null
                    && sessionDirectory.equals(directory.getAbsolutePath());
        }

        boolean isOperatingCamera() {
            return state == AstroCapturePolicy.State.STARTING
                    || state == AstroCapturePolicy.State.RUNNING
                    || state == AstroCapturePolicy.State.PAUSING;
        }

        boolean isRunning() {
            return state == AstroCapturePolicy.State.STARTING
                    || state == AstroCapturePolicy.State.RUNNING
                    || state == AstroCapturePolicy.State.PAUSING;
        }
    }
}

package com.camerae.eosrprobe;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Bundle;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public final class MainActivity extends Activity {
    static final String ACTION_USB_PERMISSION_RESULT =
            "com.camerae.eosrprobe.action.USB_PERMISSION_RESULT";
    private static final int CANON_VENDOR_ID = 0x04A9;

    private final StringBuilder eventLog = new StringBuilder();
    private UsbManager usbManager;
    private TextView statusView;
    private TextView logView;
    private Button authorizeButton;
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
                refreshProbe();
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        statusView = findViewById(R.id.status);
        logView = findViewById(R.id.log);
        authorizeButton = findViewById(R.id.authorize);

        findViewById(R.id.refresh).setOnClickListener(view -> {
            appendEvent("Varredura manual solicitada");
            refreshProbe();
        });
        authorizeButton.setOnClickListener(view -> requestUsbPermission());
        findViewById(R.id.copy_log).setOnClickListener(view -> copyLog());
        findViewById(R.id.share_log).setOnClickListener(view -> shareLog());

        appendEvent("Aplicativo iniciado em " + Build.MANUFACTURER + " " + Build.MODEL
                + ", Android " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")");
        handleLaunchIntent(getIntent());
        refreshProbe();
    }

    @Override
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

    private void handleLaunchIntent(Intent intent) {
        if (intent != null && UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(intent.getAction())) {
            appendEvent("Aberto pelo Android após conexão USB" + deviceSuffix(readUsbDevice(intent)));
        }
    }

    private void refreshProbe() {
        if (usbManager == null) {
            statusView.setText(R.string.status_usb_service_missing);
            authorizeButton.setEnabled(false);
            return;
        }

        boolean hasUsbHost = getPackageManager().hasSystemFeature(PackageManager.FEATURE_USB_HOST);
        UsbDevice selected = selectCamera();
        if (!hasUsbHost) {
            statusView.setText(R.string.status_usb_host_missing);
        } else if (selected == null) {
            statusView.setText(R.string.status_waiting);
        } else if (usbManager.hasPermission(selected)) {
            statusView.setText(getString(R.string.status_ready, deviceLabel(selected)));
        } else {
            statusView.setText(getString(R.string.status_permission_required, deviceLabel(selected)));
        }
        authorizeButton.setEnabled(selected != null && !usbManager.hasPermission(selected));

        StringBuilder report = new StringBuilder();
        report.append("CAMERAE EOS R USB PROBE\n");
        report.append("Gerado: ").append(timestamp()).append('\n');
        report.append("Aparelho: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n');
        report.append("Android: ").append(Build.VERSION.RELEASE)
                .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        report.append("USB Host declarado pelo aparelho: ").append(hasUsbHost).append("\n\n");
        report.append("EVENTOS\n").append(eventLog).append('\n');
        report.append(UsbTopologyFormatter.describe(usbManager));
        logView.setText(report.toString());
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

    @SuppressWarnings("deprecation")
    private static UsbDevice readUsbDevice(Intent intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class);
        }
        return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
    }
}

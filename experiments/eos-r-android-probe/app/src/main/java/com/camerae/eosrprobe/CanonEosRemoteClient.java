package com.camerae.eosrprobe;

import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.SystemClock;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.function.BooleanSupplier;

final class CanonEosRemoteClient {
    private static final int OPEN_SESSION_ID = 1;
    private static final int EOS_SET_REMOTE_MODE = 0x9114;
    private static final int EOS_SET_EVENT_MODE = 0x9115;
    private static final int EOS_SET_DEVICE_PROP_VALUE_EX = 0x9110;
    private static final int EOS_GET_EVENT = 0x9116;
    private static final int EOS_REMOTE_RELEASE_ON = 0x9128;
    private static final int EOS_REMOTE_RELEASE_OFF = 0x9129;
    private static final long OBJECT_EVENT_TIMEOUT_MS = 15_000;
    private static final long OBJECT_EVENT_POLL_MS = 500;
    private static final int READINESS_ATTEMPTS = 6;
    private static final int CAPABILITY_POLLS = 3;
    private static final int SETTING_READBACK_POLLS = 6;
    private static final int PROP_ISO_SPEED = 0xD103;
    private static final int PROP_WHITE_BALANCE = 0xD109;

    private CanonEosRemoteClient() {
    }

    static Result capture(UsbManager usbManager, UsbDevice device) throws CaptureException {
        return capture(usbManager, device, 0, () -> false);
    }

    static Result capture(
            UsbManager usbManager,
            UsbDevice device,
            long requestedBulbHoldMillis,
            BooleanSupplier cancelRequested
    ) throws CaptureException {
        StringBuilder report = new StringBuilder();
        report.append("CAPTURA REMOTA CANON EOS\n");
        report.append("Início: ").append(timestamp()).append('\n');
        report.append("Destino PTP não alterado; esperado: configuração atual da câmera/cartão\n");
        report.append("Pré-condição do teste: lente/câmera em foco manual\n");

        PtpUsbTransport transport = null;
        boolean halfPressed = false;
        boolean fullPressed = false;
        boolean captureCommandCompleted = false;
        CanonEosEventParser.CapturedObject capturedObject = null;
        String failureMessage = null;
        Throwable failureCause = null;
        long actualBulbHoldMillis = 0;
        try {
            transport = openReadyTransport(usbManager, device, report);
            transport.openSession(OPEN_SESSION_ID);
            transport.command("EOS_SetRemoteMode", EOS_SET_REMOTE_MODE, 1);
            transport.command("EOS_SetEventMode", EOS_SET_EVENT_MODE, 1);
            drainEvents(transport, report, "eventos iniciais");

            transport.command("EOS_HalfPress", EOS_REMOTE_RELEASE_ON, 1, 0);
            halfPressed = true;
            drainEvents(transport, report, "após meio-pressionamento");

            transport.command("EOS_FullPress", EOS_REMOTE_RELEASE_ON, 2, 0);
            fullPressed = true;
            if (requestedBulbHoldMillis > 0) {
                long holdStartedAt = SystemClock.elapsedRealtime();
                report.append("Exposição Bulb solicitada: ")
                        .append(requestedBulbHoldMillis).append(" ms\n");
                boolean canceledDuringHold = false;
                while (true) {
                    if (cancelRequested.getAsBoolean()) {
                        canceledDuringHold = true;
                        break;
                    }
                    long remaining = requestedBulbHoldMillis
                            - (SystemClock.elapsedRealtime() - holdStartedAt);
                    if (remaining <= 0) {
                        break;
                    }
                    SystemClock.sleep(Math.min(remaining, 100));
                }
                actualBulbHoldMillis = SystemClock.elapsedRealtime() - holdStartedAt;
                report.append("Exposição Bulb mantida por: ")
                        .append(actualBulbHoldMillis).append(" ms")
                        .append(canceledDuringHold ? " (cancelada)" : "")
                        .append('\n');
            }
            transport.command("EOS_FullRelease", EOS_REMOTE_RELEASE_OFF, 2);
            fullPressed = false;
            captureCommandCompleted = true;

            capturedObject = drainEvents(transport, report, "após disparo");
            transport.command("EOS_HalfRelease", EOS_REMOTE_RELEASE_OFF, 1);
            halfPressed = false;
            CanonEosEventParser.CapturedObject releaseObject =
                    drainEvents(transport, report, "após liberação");
            if (capturedObject == null) {
                capturedObject = releaseObject;
            }
            if (capturedObject == null) {
                capturedObject = waitForObjectAdded(transport, report);
            }
            report.append("Resultado: sequência de disparo aceita pela câmera\n");
            if (capturedObject == null) {
                report.append("Resultado do objeto: evento ObjectAddedEx/64 não recebido no prazo\n");
            } else {
                report.append("Resultado do objeto: handle=").append(capturedObject.handle)
                        .append(" name=").append(capturedObject.name)
                        .append(" size=").append(capturedObject.size).append(" bytes\n");
            }
        } catch (PtpUsbTransport.TransportException error) {
            failureMessage = error.getMessage();
            failureCause = error;
            report.append("ERRO: ").append(failureMessage).append('\n');
        } catch (RuntimeException error) {
            failureMessage = error.getClass().getSimpleName() + ": " + error.getMessage();
            failureCause = error;
            report.append("ERRO: ").append(failureMessage).append('\n');
        } finally {
            if (transport != null) {
                if (fullPressed) {
                    releaseQuietly(transport, report, "full", 2);
                }
                if (halfPressed) {
                    releaseQuietly(transport, report, "half", 1);
                }
                restoreCameraUiQuietly(transport, report);
                try {
                    transport.close();
                } catch (RuntimeException error) {
                    report.append("Limpeza: fechamento USB falhou: ")
                            .append(error.getMessage()).append('\n');
                    if (failureCause == null) {
                        failureMessage = "Falha ao fechar a conexão USB: " + error.getMessage();
                        failureCause = error;
                    }
                }
            }
            report.append("Fim: ").append(timestamp()).append('\n');
        }
        if (failureCause != null) {
            throw new CaptureException(failureMessage, report.toString(), failureCause);
        }
        return new Result(
                report.toString(),
                captureCommandCompleted,
                capturedObject,
                actualBulbHoldMillis
        );
    }

    static CapabilityResult inspectExposureCapabilities(
            UsbManager usbManager,
            UsbDevice device
    ) throws CapabilityException {
        StringBuilder report = new StringBuilder();
        report.append("DESCOBERTA DE CONTROLES CANON EOS\n");
        report.append("Início: ").append(timestamp()).append('\n');
        PtpUsbTransport transport = null;
        CanonEosExposureCapabilities capabilities = new CanonEosExposureCapabilities();
        String failureMessage = null;
        Throwable failureCause = null;
        try {
            transport = openReadyTransport(usbManager, device, report);
            initializeRemoteSession(transport);
            readCapabilities(transport, capabilities, report);
            report.append('\n').append(capabilities.report());
            if (!capabilities.isUsable()) {
                throw new PtpUsbTransport.TransportException(
                        "a câmera não anunciou capabilities suficientes para o modo atual"
                );
            }
        } catch (PtpUsbTransport.TransportException | RuntimeException error) {
            failureMessage = error.getMessage();
            failureCause = error;
            report.append("ERRO: ").append(error.getMessage()).append('\n');
        } finally {
            if (transport != null) {
                restoreCameraUiQuietly(transport, report);
                closeTransportQuietly(transport, report);
            }
            report.append("Fim: ").append(timestamp()).append('\n');
        }
        if (failureCause != null) {
            throw new CapabilityException(failureMessage, report.toString(), failureCause);
        }
        return new CapabilityResult(
                report.toString(),
                capabilities.summary(),
                capabilities.snapshot()
        );
    }

    static CapabilityResult applyExposureSettings(
            UsbManager usbManager,
            UsbDevice device,
            int isoValue,
            int whiteBalanceValue
    ) throws CapabilityException {
        StringBuilder report = new StringBuilder();
        report.append("APLICAÇÃO DE CONTROLES CANON EOS\n");
        report.append("Início: ").append(timestamp()).append('\n');
        PtpUsbTransport transport = null;
        CanonEosExposureCapabilities capabilities = new CanonEosExposureCapabilities();
        String failureMessage = null;
        Throwable failureCause = null;
        try {
            transport = openReadyTransport(usbManager, device, report);
            initializeRemoteSession(transport);
            readCapabilities(transport, capabilities, report);
            requireAvailable(capabilities, "ISO", PROP_ISO_SPEED, isoValue);
            requireAvailable(
                    capabilities,
                    "white balance",
                    PROP_WHITE_BALANCE,
                    whiteBalanceValue
            );
            setPropertyAndVerify(
                    transport,
                    capabilities,
                    report,
                    "ISO",
                    PROP_ISO_SPEED,
                    isoValue,
                    2
            );
            setPropertyAndVerify(
                    transport,
                    capabilities,
                    report,
                    "WhiteBalance",
                    PROP_WHITE_BALANCE,
                    whiteBalanceValue,
                    1
            );
            report.append('\n').append(capabilities.report());
        } catch (PtpUsbTransport.TransportException | RuntimeException error) {
            failureMessage = error.getMessage();
            failureCause = error;
            report.append("ERRO: ").append(error.getMessage()).append('\n');
        } finally {
            if (transport != null) {
                restoreCameraUiQuietly(transport, report);
                closeTransportQuietly(transport, report);
            }
            report.append("Fim: ").append(timestamp()).append('\n');
        }
        if (failureCause != null) {
            throw new CapabilityException(failureMessage, report.toString(), failureCause);
        }
        return new CapabilityResult(
                report.toString(),
                capabilities.summary(),
                capabilities.snapshot()
        );
    }

    private static void initializeRemoteSession(PtpUsbTransport transport)
            throws PtpUsbTransport.TransportException {
        transport.openSession(OPEN_SESSION_ID);
        transport.command("EOS_SetRemoteMode", EOS_SET_REMOTE_MODE, 1);
        transport.command("EOS_SetEventMode", EOS_SET_EVENT_MODE, 1);
    }

    private static void restoreCameraUiQuietly(
            PtpUsbTransport transport,
            StringBuilder report
    ) {
        if (!transport.isSessionOpen()) {
            return;
        }
        report.append("Limpeza Canon: restaurando display e controles físicos\n");
        cleanupCommandQuietly(
                transport,
                report,
                "RemoteMode=0",
                EOS_SET_REMOTE_MODE,
                0
        );
        cleanupCommandQuietly(
                transport,
                report,
                "RemoteMode=1 (reativar display)",
                EOS_SET_REMOTE_MODE,
                1
        );
        cleanupCommandQuietly(
                transport,
                report,
                "EventMode=0",
                EOS_SET_EVENT_MODE,
                0
        );
    }

    private static void cleanupCommandQuietly(
            PtpUsbTransport transport,
            StringBuilder report,
            String name,
            int operationCode,
            int parameter
    ) {
        try {
            transport.commandForCleanup("EOS_Cleanup " + name, operationCode, parameter);
            report.append("Limpeza Canon: ").append(name).append(" concluído\n");
        } catch (PtpUsbTransport.TransportException error) {
            report.append("Limpeza Canon: ").append(name).append(" falhou: ")
                    .append(error.getMessage()).append('\n');
        }
    }

    private static void closeTransportQuietly(
            PtpUsbTransport transport,
            StringBuilder report
    ) {
        try {
            transport.close();
        } catch (RuntimeException error) {
            report.append("Limpeza: fechamento USB falhou: ")
                    .append(error.getMessage()).append('\n');
        }
    }

    private static void readCapabilities(
            PtpUsbTransport transport,
            CanonEosExposureCapabilities capabilities,
            StringBuilder report
    ) throws PtpUsbTransport.TransportException {
        for (int poll = 1; poll <= CAPABILITY_POLLS; poll++) {
            byte[] events = transport.commandWithData("EOS_GetEvent", EOS_GET_EVENT);
            capabilities.accept(events);
            report.append("Capabilities poll ").append(poll).append(": ")
                    .append(events.length).append(" bytes\n");
            if (capabilities.isUsable()) {
                break;
            }
            SystemClock.sleep(200);
        }
    }

    private static void requireAvailable(
            CanonEosExposureCapabilities capabilities,
            String name,
            int propertyCode,
            int value
    ) throws PtpUsbTransport.TransportException {
        if (!capabilities.isAvailable(propertyCode, value)) {
            throw new PtpUsbTransport.TransportException(
                    name + " " + hex4(value) + " não foi anunciado pela câmera"
            );
        }
    }

    private static void setPropertyAndVerify(
            PtpUsbTransport transport,
            CanonEosExposureCapabilities capabilities,
            StringBuilder report,
            String name,
            int propertyCode,
            int value,
            int valueBytes
    ) throws PtpUsbTransport.TransportException {
        int current = capabilities.currentValue(propertyCode);
        if (current == value) {
            report.append(name).append(": já estava em ").append(hex4(value)).append('\n');
            return;
        }

        ByteBuffer payload = ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN);
        payload.putInt(12);
        payload.putInt(propertyCode);
        if (valueBytes == 1) {
            payload.put((byte) value);
        } else if (valueBytes == 2) {
            payload.putShort((short) value);
        } else {
            throw new PtpUsbTransport.TransportException(
                    name + ": largura de valor não suportada " + valueBytes
            );
        }
        transport.commandWithDataOut(
                "EOS_SetDevicePropValueEx " + name,
                EOS_SET_DEVICE_PROP_VALUE_EX,
                payload.array()
        );

        for (int poll = 1; poll <= SETTING_READBACK_POLLS; poll++) {
            SystemClock.sleep(100);
            byte[] events = transport.commandWithData("EOS_GetEvent", EOS_GET_EVENT);
            capabilities.accept(events);
            report.append(name).append(" readback #").append(poll).append(": ")
                    .append(events.length).append(" bytes\n");
            if (capabilities.currentValue(propertyCode) == value) {
                report.append(name).append(": confirmado em ").append(hex4(value)).append('\n');
                return;
            }
        }
        throw new PtpUsbTransport.TransportException(
                name + " não confirmou o valor " + hex4(value)
        );
    }

    private static PtpUsbTransport openReadyTransport(
            UsbManager usbManager,
            UsbDevice device,
            StringBuilder report
    ) throws PtpUsbTransport.TransportException {
        PtpUsbTransport.TransportException lastError = null;
        for (int attempt = 1; attempt <= READINESS_ATTEMPTS; attempt++) {
            PtpUsbTransport candidate = null;
            try {
                candidate = new PtpUsbTransport(usbManager, device, report);
                candidate.probeDeviceInfoBeforeSession();
                report.append("Readiness PTP: tentativa ").append(attempt).append(" aceita\n");
                return candidate;
            } catch (PtpUsbTransport.TransportException error) {
                lastError = error;
                report.append("Readiness PTP: tentativa ").append(attempt)
                        .append(" falhou: ").append(error.getMessage()).append('\n');
                if (candidate != null) {
                    candidate.close();
                }
                if (attempt < READINESS_ATTEMPTS) {
                    SystemClock.sleep(attempt * 500L);
                }
            }
        }
        throw new PtpUsbTransport.TransportException(
                "câmera não ficou pronta após " + READINESS_ATTEMPTS
                        + " tentativas; último erro: "
                        + (lastError == null ? "desconhecido" : lastError.getMessage())
        );
    }

    private static CanonEosEventParser.CapturedObject drainEvents(
            PtpUsbTransport transport,
            StringBuilder report,
            String phase
    ) throws PtpUsbTransport.TransportException {
        byte[] data = transport.commandWithData("EOS_GetEvent", EOS_GET_EVENT);
        report.append("GetEvent ").append(phase).append(": ")
                .append(data.length).append(" bytes\n");
        return CanonEosEventParser.findObjectAdded(data);
    }

    private static CanonEosEventParser.CapturedObject waitForObjectAdded(
            PtpUsbTransport transport,
            StringBuilder report
    ) throws PtpUsbTransport.TransportException {
        long startedAt = SystemClock.elapsedRealtime();
        int polls = 0;
        while (SystemClock.elapsedRealtime() - startedAt < OBJECT_EVENT_TIMEOUT_MS) {
            SystemClock.sleep(OBJECT_EVENT_POLL_MS);
            polls++;
            CanonEosEventParser.CapturedObject captured =
                    drainEvents(transport, report, "aguardando ObjectAddedEx/64 #" + polls);
            if (captured != null) {
                report.append("ObjectAddedEx/64 recebido após ")
                        .append(SystemClock.elapsedRealtime() - startedAt)
                        .append(" ms em ").append(polls).append(" consultas\n");
                return captured;
            }
        }
        return null;
    }

    private static void releaseQuietly(
            PtpUsbTransport transport,
            StringBuilder report,
            String label,
            int button
    ) {
        try {
            transport.command("EOS_SafetyRelease", EOS_REMOTE_RELEASE_OFF, button);
            report.append("Limpeza: ").append(label).append(" release concluído\n");
        } catch (PtpUsbTransport.TransportException error) {
            report.append("Limpeza: ").append(label).append(" release falhou: ")
                    .append(error.getMessage()).append('\n');
        }
    }

    private static String timestamp() {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(new Date());
    }

    private static String hex4(int value) {
        return String.format(Locale.US, "0x%04X", value & 0xFFFF);
    }

    static final class Result {
        final String report;
        final boolean captureCommandCompleted;
        final CanonEosEventParser.CapturedObject capturedObject;
        final long actualBulbHoldMillis;

        Result(
                String report,
                boolean captureCommandCompleted,
                CanonEosEventParser.CapturedObject capturedObject,
                long actualBulbHoldMillis
        ) {
            this.report = report;
            this.captureCommandCompleted = captureCommandCompleted;
            this.capturedObject = capturedObject;
            this.actualBulbHoldMillis = actualBulbHoldMillis;
        }
    }

    static final class CaptureException extends Exception {
        final String report;

        CaptureException(String message, String report, Throwable cause) {
            super(message, cause);
            this.report = report;
        }
    }

    static final class CapabilityResult {
        final String report;
        final String summary;
        final CanonEosExposureCapabilities.Snapshot snapshot;

        CapabilityResult(
                String report,
                String summary,
                CanonEosExposureCapabilities.Snapshot snapshot
        ) {
            this.report = report;
            this.summary = summary;
            this.snapshot = snapshot;
        }
    }

    static final class CapabilityException extends Exception {
        final String report;

        CapabilityException(String message, String report, Throwable cause) {
            super(message, cause);
            this.report = report;
        }
    }
}

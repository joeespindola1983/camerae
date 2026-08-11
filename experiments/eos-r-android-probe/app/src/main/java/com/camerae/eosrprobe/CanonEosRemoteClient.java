package com.camerae.eosrprobe;

import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.SystemClock;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class CanonEosRemoteClient {
    private static final int OPEN_SESSION_ID = 1;
    private static final int EOS_SET_REMOTE_MODE = 0x9114;
    private static final int EOS_SET_EVENT_MODE = 0x9115;
    private static final int EOS_GET_EVENT = 0x9116;
    private static final int EOS_REMOTE_RELEASE_ON = 0x9128;
    private static final int EOS_REMOTE_RELEASE_OFF = 0x9129;
    private static final long OBJECT_EVENT_TIMEOUT_MS = 15_000;
    private static final long OBJECT_EVENT_POLL_MS = 500;

    private CanonEosRemoteClient() {
    }

    static Result capture(UsbManager usbManager, UsbDevice device) throws CaptureException {
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
        try {
            transport = new PtpUsbTransport(usbManager, device, report);
            transport.openSession(OPEN_SESSION_ID);
            transport.command("EOS_SetRemoteMode", EOS_SET_REMOTE_MODE, 1);
            transport.command("EOS_SetEventMode", EOS_SET_EVENT_MODE, 1);
            drainEvents(transport, report, "eventos iniciais");

            transport.command("EOS_HalfPress", EOS_REMOTE_RELEASE_ON, 1, 0);
            halfPressed = true;
            drainEvents(transport, report, "após meio-pressionamento");

            transport.command("EOS_FullPress", EOS_REMOTE_RELEASE_ON, 2, 0);
            fullPressed = true;
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
                report.append("Resultado do objeto: evento ObjectAddedEx não recebido no prazo\n");
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
        return new Result(report.toString(), captureCommandCompleted, capturedObject);
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
                    drainEvents(transport, report, "aguardando ObjectAddedEx #" + polls);
            if (captured != null) {
                report.append("ObjectAddedEx recebido após ")
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

    static final class Result {
        final String report;
        final boolean captureCommandCompleted;
        final CanonEosEventParser.CapturedObject capturedObject;

        Result(
                String report,
                boolean captureCommandCompleted,
                CanonEosEventParser.CapturedObject capturedObject
        ) {
            this.report = report;
            this.captureCommandCompleted = captureCommandCompleted;
            this.capturedObject = capturedObject;
        }
    }

    static final class CaptureException extends Exception {
        final String report;

        CaptureException(String message, String report, Throwable cause) {
            super(message, cause);
            this.report = report;
        }
    }
}

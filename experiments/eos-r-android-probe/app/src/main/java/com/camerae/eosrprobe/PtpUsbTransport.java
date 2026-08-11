package com.camerae.eosrprobe;

import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Locale;

final class PtpUsbTransport implements AutoCloseable {
    static final int RESPONSE_OK = 0x2001;

    private static final int CONTAINER_COMMAND = 1;
    private static final int CONTAINER_DATA = 2;
    private static final int CONTAINER_RESPONSE = 3;
    private static final int HEADER_LENGTH = 12;
    private static final int MAX_CONTAINER_LENGTH = 2 * 1024 * 1024;
    private static final int USB_TIMEOUT_MS = 15_000;

    private final UsbDeviceConnection connection;
    private final UsbInterface ptpInterface;
    private final UsbEndpoint bulkIn;
    private final UsbEndpoint bulkOut;
    private final StringBuilder report;
    private int nextTransactionId;
    private boolean sessionOpen;

    PtpUsbTransport(
            UsbManager usbManager,
            UsbDevice device,
            StringBuilder report
    ) throws TransportException {
        this.report = report;
        ptpInterface = findPtpInterface(device);
        if (ptpInterface == null) {
            throw new TransportException("Interface PTP 6/1/1 não encontrada");
        }
        bulkIn = findEndpoint(ptpInterface, UsbConstants.USB_DIR_IN);
        bulkOut = findEndpoint(ptpInterface, UsbConstants.USB_DIR_OUT);
        if (bulkIn == null || bulkOut == null) {
            throw new TransportException("Endpoints bulk IN/OUT da interface PTP não encontrados");
        }

        connection = usbManager.openDevice(device);
        if (connection == null) {
            throw new TransportException("UsbManager.openDevice retornou null");
        }
        if (!connection.claimInterface(ptpInterface, true)) {
            connection.close();
            throw new TransportException("Não foi possível reivindicar a interface PTP");
        }
        append("USB interface=%d bulkOut=0x%02X bulkIn=0x%02X",
                ptpInterface.getId(), bulkOut.getAddress(), bulkIn.getAddress());
    }

    void openSession(int sessionId) throws TransportException {
        if (sessionOpen) {
            return;
        }
        Response response = transactNoData(0x1002, 0, sessionId);
        requireOk("OpenSession", response);
        sessionOpen = true;
        nextTransactionId = 1;
    }

    void probeDeviceInfoBeforeSession() throws TransportException {
        if (sessionOpen) {
            throw new TransportException("GetDeviceInfo de readiness exige sessão fechada");
        }
        byte[] deviceInfo = commandWithData("GetDeviceInfo", 0x1001);
        nextTransactionId = 0;
        if (deviceInfo.length < 12) {
            throw new TransportException("GetDeviceInfo retornou somente "
                    + deviceInfo.length + " bytes");
        }
        append("Readiness PTP confirmada por GetDeviceInfo: %d bytes", deviceInfo.length);
    }

    void command(String name, int operationCode, int... parameters)
            throws TransportException {
        int transactionId = nextTransactionId++;
        Response response = transactNoData(operationCode, transactionId, parameters);
        requireOk(name, response);
    }

    byte[] commandWithData(String name, int operationCode, int... parameters)
            throws TransportException {
        int transactionId = nextTransactionId++;
        writeCommand(operationCode, transactionId, parameters);
        Container first = readContainer();
        if (first.transactionId != transactionId) {
            throw new TransportException(name + ": transactionId inesperado "
                    + first.transactionId + ", esperado " + transactionId);
        }

        byte[] data = new byte[0];
        Container responseContainer = first;
        if (first.type == CONTAINER_DATA) {
            if (first.code != operationCode) {
                throw new TransportException(name + ": data code inesperado " + hex4(first.code));
            }
            data = first.payload;
            append("<- DATA %s tx=%d bytes=%d prefix=%s",
                    hex4(operationCode), transactionId, data.length, hexPrefix(data));
            responseContainer = readContainer();
        }
        Response response = parseResponse(name, responseContainer, transactionId);
        requireOk(name, response);
        return data;
    }

    void closeSessionQuietly() {
        if (!sessionOpen) {
            return;
        }
        try {
            int transactionId = nextTransactionId++;
            Response response = transactNoData(0x1003, transactionId);
            append("CloseSession: %s", responseName(response.code));
        } catch (TransportException error) {
            append("CloseSession falhou durante limpeza: %s", error.getMessage());
        } finally {
            sessionOpen = false;
        }
    }

    @Override
    public void close() {
        closeSessionQuietly();
        connection.releaseInterface(ptpInterface);
        connection.close();
        append("Interface PTP liberada e conexão USB fechada");
    }

    private Response transactNoData(int operationCode, int transactionId, int... parameters)
            throws TransportException {
        writeCommand(operationCode, transactionId, parameters);
        return parseResponse(
                hex4(operationCode),
                readContainer(),
                transactionId
        );
    }

    private void writeCommand(int operationCode, int transactionId, int... parameters)
            throws TransportException {
        if (parameters.length > 5) {
            throw new TransportException("Container PTP aceita no máximo 5 parâmetros");
        }
        ByteBuffer bytes = ByteBuffer.allocate(HEADER_LENGTH + parameters.length * 4)
                .order(ByteOrder.LITTLE_ENDIAN);
        bytes.putInt(bytes.capacity());
        bytes.putShort((short) CONTAINER_COMMAND);
        bytes.putShort((short) operationCode);
        bytes.putInt(transactionId);
        for (int parameter : parameters) {
            bytes.putInt(parameter);
        }

        int written = connection.bulkTransfer(
                bulkOut,
                bytes.array(),
                bytes.capacity(),
                USB_TIMEOUT_MS
        );
        if (written != bytes.capacity()) {
            throw new TransportException("Falha no bulk OUT de " + hex4(operationCode)
                    + ": " + written + "/" + bytes.capacity() + " bytes");
        }
        append("-> CMD %s tx=%d params=%s",
                hex4(operationCode), transactionId, formatParameters(parameters));
    }

    private Container readContainer() throws TransportException {
        byte[] bytes = new byte[MAX_CONTAINER_LENGTH];
        int received = connection.bulkTransfer(
                bulkIn,
                bytes,
                bytes.length,
                USB_TIMEOUT_MS
        );
        if (received < HEADER_LENGTH) {
            throw new TransportException("Bulk IN inválido: " + received + " bytes");
        }

        ByteBuffer header = ByteBuffer.wrap(bytes, 0, received).order(ByteOrder.LITTLE_ENDIAN);
        long declaredLong = Integer.toUnsignedLong(header.getInt());
        if (declaredLong < HEADER_LENGTH || declaredLong > MAX_CONTAINER_LENGTH) {
            throw new TransportException("Comprimento de container PTP inválido: " + declaredLong);
        }
        int declared = (int) declaredLong;
        while (received < declared) {
            int chunk = connection.bulkTransfer(
                    bulkIn,
                    bytes,
                    received,
                    declared - received,
                    USB_TIMEOUT_MS
            );
            if (chunk <= 0) {
                throw new TransportException("Container PTP truncado: "
                        + received + "/" + declared + " bytes");
            }
            received += chunk;
        }

        int type = Short.toUnsignedInt(header.getShort());
        int code = Short.toUnsignedInt(header.getShort());
        int transactionId = header.getInt();
        byte[] payload = new byte[declared - HEADER_LENGTH];
        System.arraycopy(bytes, HEADER_LENGTH, payload, 0, payload.length);
        return new Container(type, code, transactionId, payload);
    }

    private Response parseResponse(String name, Container container, int expectedTransactionId)
            throws TransportException {
        if (container.type != CONTAINER_RESPONSE) {
            throw new TransportException(name + ": esperado RESPONSE, recebido container type="
                    + container.type);
        }
        if (container.transactionId != expectedTransactionId) {
            throw new TransportException(name + ": response transactionId="
                    + container.transactionId + ", esperado=" + expectedTransactionId);
        }
        append("<- RESP %s tx=%d %s",
                hex4(container.code), expectedTransactionId, responseName(container.code));
        return new Response(container.code);
    }

    private void requireOk(String name, Response response) throws TransportException {
        if (response.code != RESPONSE_OK) {
            throw new TransportException(name + " retornou " + responseName(response.code)
                    + " " + hex4(response.code));
        }
    }

    private static UsbInterface findPtpInterface(UsbDevice device) {
        UsbInterface classMatch = null;
        for (int index = 0; index < device.getInterfaceCount(); index++) {
            UsbInterface candidate = device.getInterface(index);
            if (candidate.getInterfaceClass() == UsbConstants.USB_CLASS_STILL_IMAGE) {
                if (candidate.getInterfaceSubclass() == 1
                        && candidate.getInterfaceProtocol() == 1) {
                    return candidate;
                }
                classMatch = candidate;
            }
        }
        return classMatch;
    }

    private static UsbEndpoint findEndpoint(UsbInterface usbInterface, int direction) {
        for (int index = 0; index < usbInterface.getEndpointCount(); index++) {
            UsbEndpoint endpoint = usbInterface.getEndpoint(index);
            if (endpoint.getType() == UsbConstants.USB_ENDPOINT_XFER_BULK
                    && endpoint.getDirection() == direction) {
                return endpoint;
            }
        }
        return null;
    }

    private static String formatParameters(int[] parameters) {
        if (parameters.length == 0) {
            return "[]";
        }
        StringBuilder formatted = new StringBuilder("[");
        for (int index = 0; index < parameters.length; index++) {
            if (index > 0) {
                formatted.append(", ");
            }
            formatted.append(hex8(parameters[index]));
        }
        return formatted.append(']').toString();
    }

    private static String hexPrefix(byte[] bytes) {
        if (bytes.length == 0) {
            return "<empty>";
        }
        int count = Math.min(bytes.length, 32);
        StringBuilder text = new StringBuilder();
        for (int index = 0; index < count; index++) {
            if (index > 0) {
                text.append(' ');
            }
            text.append(String.format(Locale.US, "%02X", bytes[index] & 0xFF));
        }
        if (bytes.length > count) {
            text.append(" …");
        }
        return text.toString();
    }

    private static String responseName(int code) {
        switch (code) {
            case 0x2001:
                return "OK";
            case 0x2002:
                return "GeneralError";
            case 0x2005:
                return "OperationNotSupported";
            case 0x2019:
                return "DeviceBusy";
            case 0x201E:
                return "SessionAlreadyOpen";
            case 0x2003:
                return "SessionNotOpen";
            default:
                return "Response";
        }
    }

    private static String hex4(int value) {
        return String.format(Locale.US, "0x%04X", value & 0xFFFF);
    }

    private static String hex8(int value) {
        return String.format(Locale.US, "0x%08X", value);
    }

    private void append(String format, Object... arguments) {
        report.append(String.format(Locale.US, format, arguments)).append('\n');
    }

    private static final class Container {
        final int type;
        final int code;
        final int transactionId;
        final byte[] payload;

        Container(int type, int code, int transactionId, byte[] payload) {
            this.type = type;
            this.code = code;
            this.transactionId = transactionId;
            this.payload = payload;
        }
    }

    private static final class Response {
        final int code;

        Response(int code) {
            this.code = code;
        }
    }

    static final class TransportException extends Exception {
        TransportException(String message) {
            super(message);
        }
    }
}

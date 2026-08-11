package com.camerae.eosrprobe;

import android.hardware.usb.UsbConfiguration;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

final class UsbTopologyFormatter {
    private UsbTopologyFormatter() {
    }

    static String describe(UsbManager usbManager) {
        StringBuilder output = new StringBuilder("TOPOLOGIA USB\n");
        List<UsbDevice> devices = new ArrayList<>(usbManager.getDeviceList().values());
        devices.sort(Comparator.comparing(UsbDevice::getDeviceName));
        output.append("Dispositivos encontrados: ").append(devices.size()).append("\n\n");

        for (int deviceIndex = 0; deviceIndex < devices.size(); deviceIndex++) {
            appendDevice(output, usbManager, devices.get(deviceIndex), deviceIndex);
        }
        if (devices.isEmpty()) {
            output.append("Nenhum dispositivo USB conectado.\n");
        }
        return output.toString();
    }

    private static void appendDevice(
            StringBuilder output,
            UsbManager usbManager,
            UsbDevice device,
            int deviceIndex
    ) {
        boolean permitted = usbManager.hasPermission(device);
        output.append("DEVICE[").append(deviceIndex).append("]\n");
        output.append("  name: ").append(device.getDeviceName()).append('\n');
        output.append("  vendorId: ").append(hex4(device.getVendorId()))
                .append(" (").append(device.getVendorId()).append(")\n");
        output.append("  productId: ").append(hex4(device.getProductId()))
                .append(" (").append(device.getProductId()).append(")\n");
        output.append("  deviceId: ").append(device.getDeviceId()).append('\n');
        output.append("  class/subclass/protocol: ")
                .append(device.getDeviceClass()).append('/')
                .append(device.getDeviceSubclass()).append('/')
                .append(device.getDeviceProtocol()).append('\n');
        output.append("  version: ").append(safe(() -> device.getVersion())).append('\n');
        output.append("  manufacturer: ").append(safe(() -> device.getManufacturerName())).append('\n');
        output.append("  product: ").append(safe(() -> device.getProductName())).append('\n');
        output.append("  serial: ").append(safe(() -> device.getSerialNumber())).append('\n');
        output.append("  permission: ").append(permitted).append('\n');
        output.append("  configurations: ").append(device.getConfigurationCount()).append('\n');

        for (int configurationIndex = 0;
             configurationIndex < device.getConfigurationCount();
             configurationIndex++) {
            UsbConfiguration configuration = device.getConfiguration(configurationIndex);
            output.append("  CONFIG[").append(configurationIndex).append("]")
                    .append(" id=").append(configuration.getId())
                    .append(" name=").append(safe(configuration::getName))
                    .append(" maxPower=").append(configuration.getMaxPower()).append("mA")
                    .append(" selfPowered=").append(configuration.isSelfPowered())
                    .append(" remoteWakeup=").append(configuration.isRemoteWakeup())
                    .append(" interfaces=").append(configuration.getInterfaceCount())
                    .append('\n');

            for (int interfaceIndex = 0;
                 interfaceIndex < configuration.getInterfaceCount();
                 interfaceIndex++) {
                appendInterface(output, configuration.getInterface(interfaceIndex), interfaceIndex);
            }
        }
        output.append('\n');
    }

    private static void appendInterface(
            StringBuilder output,
            UsbInterface usbInterface,
            int interfaceIndex
    ) {
        output.append("    INTERFACE[").append(interfaceIndex).append("]")
                .append(" id=").append(usbInterface.getId())
                .append(" alt=").append(usbInterface.getAlternateSetting())
                .append(" name=").append(safe(usbInterface::getName))
                .append(" class/subclass/protocol=")
                .append(usbInterface.getInterfaceClass()).append('/')
                .append(usbInterface.getInterfaceSubclass()).append('/')
                .append(usbInterface.getInterfaceProtocol())
                .append(" endpoints=").append(usbInterface.getEndpointCount())
                .append('\n');

        for (int endpointIndex = 0;
             endpointIndex < usbInterface.getEndpointCount();
             endpointIndex++) {
            UsbEndpoint endpoint = usbInterface.getEndpoint(endpointIndex);
            output.append("      ENDPOINT[").append(endpointIndex).append("]")
                    .append(" address=").append(hex2(endpoint.getAddress()))
                    .append(" number=").append(endpoint.getEndpointNumber())
                    .append(" direction=").append(directionName(endpoint.getDirection()))
                    .append(" type=").append(typeName(endpoint.getType()))
                    .append(" attributes=").append(hex2(endpoint.getAttributes()))
                    .append(" maxPacketSize=").append(endpoint.getMaxPacketSize())
                    .append(" interval=").append(endpoint.getInterval())
                    .append('\n');
        }
    }

    private static String directionName(int direction) {
        return direction == UsbConstants.USB_DIR_IN ? "IN" : "OUT";
    }

    private static String typeName(int type) {
        switch (type) {
            case UsbConstants.USB_ENDPOINT_XFER_CONTROL:
                return "CONTROL";
            case UsbConstants.USB_ENDPOINT_XFER_ISOC:
                return "ISOCHRONOUS";
            case UsbConstants.USB_ENDPOINT_XFER_BULK:
                return "BULK";
            case UsbConstants.USB_ENDPOINT_XFER_INT:
                return "INTERRUPT";
            default:
                return "UNKNOWN(" + type + ")";
        }
    }

    private static String hex2(int value) {
        return String.format(Locale.US, "0x%02X", value);
    }

    private static String hex4(int value) {
        return String.format(Locale.US, "0x%04X", value);
    }

    private static String safe(ValueReader reader) {
        try {
            String value = reader.read();
            return value == null || value.isEmpty() ? "<indisponível>" : value;
        } catch (RuntimeException error) {
            return "<" + error.getClass().getSimpleName() + ">";
        }
    }

    private interface ValueReader {
        String read();
    }
}

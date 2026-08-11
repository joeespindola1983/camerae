package com.camerae.eosrprobe;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Explicit PendingIntent target required by recent Android versions. The
 * receiver relays the result only to this package while the activity is alive.
 */
public final class UsbPermissionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent result = new Intent(MainActivity.ACTION_USB_PERMISSION_RESULT)
                .setPackage(context.getPackageName());
        if (intent.getExtras() != null) {
            result.putExtras(intent.getExtras());
        }
        context.sendBroadcast(result);
    }
}

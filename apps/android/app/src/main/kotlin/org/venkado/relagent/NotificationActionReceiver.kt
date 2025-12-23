package org.venkado.relagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Handles notification action button clicks.
 * Communicates with Flutter via MethodChannel to stop recording/playback.
 */
class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NotificationActionReceiver"
        var methodChannel: MethodChannel? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received action: ${intent.action}")

        if (intent.action == "${context.packageName}.STOP") {
            Log.d(TAG, "Stop action triggered - going silent")
            methodChannel?.invokeMethod("stop", null)
        }
    }
}

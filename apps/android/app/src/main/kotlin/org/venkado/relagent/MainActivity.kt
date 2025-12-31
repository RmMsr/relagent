package org.venkado.relagent

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.relagent.background_service"
    private val NOTIFICATION_ACTION_CHANNEL = "com.relagent.notification_actions"
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    private val BLUETOOTH_PERMISSION_REQUEST_CODE = 1002
    private val COMBINED_PERMISSIONS_REQUEST_CODE = 1003

    // Store pending service start request while waiting for permission
    private var pendingServiceStart: PendingServiceStart? = null

    private data class PendingServiceStart(
        val mode: String,
        val durationMinutes: Long
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup reverse MethodChannel for notification actions (Native -> Flutter)
        val notificationActionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_ACTION_CHANNEL
        )
        NotificationActionReceiver.methodChannel = notificationActionChannel

        // MethodChannel for commands (Flutter -> Native)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            android.util.Log.d("MainActivity", "MethodChannel call: ${call.method}")
            when (call.method) {
                "startService" -> {
                    val mode = call.argument<String>("mode") ?: "idle"
                    // Handle both Int and Long from Dart
                    val durationMinutes = (call.argument<Number>("durationMinutes")?.toLong()) ?: -1L
                    android.util.Log.d("MainActivity", "Starting service with mode: $mode, duration: $durationMinutes")
                    startAudioService(mode, durationMinutes)
                    result.success(null)
                }
                "stopService" -> {
                    android.util.Log.d("MainActivity", "Stopping service")
                    stopAudioService()
                    result.success(null)
                }
                "updateNotification" -> {
                    val message = call.argument<String>("message") ?: ""
                    android.util.Log.d("MainActivity", "Updating notification: $message")
                    updateNotification(message)
                    result.success(null)
                }
                "showErrorNotification" -> {
                    val title = call.argument<String>("title") ?: "Error"
                    val message = call.argument<String>("message") ?: ""
                    android.util.Log.d("MainActivity", "Showing error notification: $title")
                    showErrorNotification(title, message)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAudioService(mode: String, durationMinutes: Long = -1L) {
        // Check required runtime permissions based on Android version
        val missingPermissions = mutableListOf<String>()

        // Android 13+ (API 33+) requires runtime notification permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!hasNotificationPermission()) {
                missingPermissions.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // Android 12+ (API 31+) requires runtime Bluetooth permission for audio routing
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!hasBluetoothPermission()) {
                missingPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        }

        // Request any missing permissions
        if (missingPermissions.isNotEmpty()) {
            android.util.Log.d("MainActivity", "Missing permissions: $missingPermissions, requesting...")
            // Store service start request for after permissions are granted
            pendingServiceStart = PendingServiceStart(mode, durationMinutes)
            requestPermissions(missingPermissions.toTypedArray())
            return
        }

        // All permissions granted or not required, start service
        startAudioServiceInternal(mode, durationMinutes)
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Pre-Android 13 doesn't require runtime permission
            true
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Pre-Android 12 doesn't require runtime permission
            true
        }
    }

    private fun requestPermissions(permissions: Array<String>) {
        // Determine request code based on what we're requesting
        val requestCode = when {
            permissions.size > 1 -> COMBINED_PERMISSIONS_REQUEST_CODE
            permissions.contains(Manifest.permission.POST_NOTIFICATIONS) -> NOTIFICATION_PERMISSION_REQUEST_CODE
            permissions.contains(Manifest.permission.BLUETOOTH_CONNECT) -> BLUETOOTH_PERMISSION_REQUEST_CODE
            else -> COMBINED_PERMISSIONS_REQUEST_CODE
        }

        ActivityCompat.requestPermissions(this, permissions, requestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        when (requestCode) {
            NOTIFICATION_PERMISSION_REQUEST_CODE,
            BLUETOOTH_PERMISSION_REQUEST_CODE,
            COMBINED_PERMISSIONS_REQUEST_CODE -> {
                // Check which permissions were granted and which were denied
                val deniedPermissions = mutableListOf<String>()

                for (i in permissions.indices) {
                    if (grantResults[i] != PackageManager.PERMISSION_GRANTED) {
                        deniedPermissions.add(permissions[i])
                    }
                }

                if (deniedPermissions.isEmpty()) {
                    android.util.Log.d("MainActivity", "All permissions granted")
                    // Start the pending service if there is one
                    pendingServiceStart?.let { pending ->
                        startAudioServiceInternal(pending.mode, pending.durationMinutes)
                        pendingServiceStart = null
                    }
                } else {
                    android.util.Log.w("MainActivity", "Permissions denied: $deniedPermissions")
                    // Clear pending request
                    pendingServiceStart = null

                    // Build error message based on denied permissions
                    val errorMessage = buildPermissionErrorMessage(deniedPermissions)

                    // Show error notification through the service (best effort)
                    showErrorNotification("Permission Required", errorMessage)
                }
            }
        }
    }

    private fun buildPermissionErrorMessage(deniedPermissions: List<String>): String {
        val messages = mutableListOf<String>()

        if (deniedPermissions.contains(Manifest.permission.POST_NOTIFICATIONS)) {
            messages.add("notification permission for background listening")
        }

        if (deniedPermissions.contains(Manifest.permission.BLUETOOTH_CONNECT)) {
            messages.add("Bluetooth permission for wireless headset support")
        }

        return when (messages.size) {
            0 -> "Required permissions are needed"
            1 -> messages[0].replaceFirstChar { it.uppercase() } + " is required"
            else -> messages.joinToString(" and ") { it.replaceFirstChar { c -> c.uppercase() } } + " are required"
        }
    }

    private fun startAudioServiceInternal(mode: String, durationMinutes: Long) {
        val intent = Intent(this, AudioBackgroundService::class.java).apply {
            putExtra("mode", mode)
            putExtra("durationMinutes", durationMinutes)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: SecurityException) {
            android.util.Log.e("MainActivity", "SecurityException starting foreground service: ${e.message}")
            android.util.Log.e("MainActivity", "This usually means the app is not in foreground or permissions are missing")
            // Retry after a short delay to allow activity to become visible
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                } catch (e2: Exception) {
                    android.util.Log.e("MainActivity", "Retry failed: ${e2.message}")
                }
            }, 1000)
        }
    }

    private fun stopAudioService() {
        val intent = Intent(this, AudioBackgroundService::class.java)
        stopService(intent)
    }

    private fun updateNotification(message: String) {
        val intent = Intent(this, AudioBackgroundService::class.java).apply {
            putExtra("message", message)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun showErrorNotification(title: String, message: String) {
        // Send error notification request to service via intent
        val errorIntent = Intent(this, AudioBackgroundService::class.java).apply {
            putExtra("showError", true)
            putExtra("errorTitle", title)
            putExtra("errorMessage", message)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                startForegroundService(errorIntent)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Could not show error notification: ${e.message}")
            }
        } else {
            startService(errorIntent)
        }
    }
}
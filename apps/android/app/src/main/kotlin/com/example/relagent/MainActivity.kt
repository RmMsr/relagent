package org.venkado.relagent

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.relagent.background_service"
    private val NOTIFICATION_ACTION_CHANNEL = "com.relagent.notification_actions"

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
                "getNotificationPermissionStatus" -> {
                    val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        NotificationManagerCompat.from(this).areNotificationsEnabled()
                    } else {
                        true // Older versions don't need runtime permission
                    }
                    result.success(if (status) "granted" else "denied")
                }
                "requestNotificationPermissionDialog" -> {
                    // Show in-app permission request dialog first
                    // Note: This is a simplified implementation - in production you'd want
                    // a proper dialog with explanation, but for now this opens system settings
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success("requested")
                    } else {
                        result.success("granted") // Older versions grant by default
                    }
                }
                "openNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                    result.success("opened")
                }
                "requestNotificationPermissionDialog" -> {
                    // Simplified approach - open system settings for now
                    // In a full implementation, this would show an in-app dialog
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success("opened")
                    } else {
                        result.success("granted") // Older versions grant by default
                    }
                }
                "openNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                    result.success("opened")
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success("requested")
                    } else {
                        result.success("granted") // Older versions grant by default
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAudioService(mode: String, durationMinutes: Long = -1L) {
        val intent = Intent(this, AudioBackgroundService::class.java).apply {
            putExtra("mode", mode)
            putExtra("durationMinutes", durationMinutes)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
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

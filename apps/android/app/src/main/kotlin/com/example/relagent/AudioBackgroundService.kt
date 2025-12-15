package org.venkado.relagent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Date

/**
 * Minimal foreground service for Phase 1 POC testing.
 * Keeps app alive during background audio operations.
 *
 * Note: Audio focus is managed by audio_session package (used by just_audio and record).
 * This service only handles wake lock and foreground notification.
 */
class AudioBackgroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentMode: String = MODE_IDLE

    // Time display fields
    private var recordingStartTime: Long = 0
    private var recordingDurationMinutes: Long = -1
    private var lastNotificationText: String = ""
    private val notificationUpdateHandler = Handler(Looper.getMainLooper())
    private val notificationUpdateRunnable = object : Runnable {
        override fun run() {
            updateNotificationWithEndTime()
            notificationUpdateHandler.postDelayed(this, 60000) // Update every 60 seconds
        }
    }

    companion object {
        private const val TAG = "AudioBackgroundService"
        private const val CHANNEL_ID = "relagent_audio_service"
        private const val ERROR_CHANNEL_ID = "relagent_errors"
        private const val NOTIFICATION_ID = 1001
        private const val ERROR_NOTIFICATION_ID = 1002

        private const val MODE_IDLE = "idle"
        private const val MODE_RECORDING = "recording"
        private const val MODE_PLAYING = "playing"

        const val ACTION_STOP = "org.venkado.relagent.STOP"
        private const val ACTION_NOTIFICATION_DISMISSED = "org.venkado.relagent.NOTIFICATION_DISMISSED"
    }

    private val dismissalReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_NOTIFICATION_DISMISSED) {
                Log.d(TAG, "Notification dismissed - recreating immediately")
                // Recreate notification immediately if service is still active
                if (currentMode != MODE_IDLE) {
                    recreateNotification()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        createNotificationChannel()
        createErrorNotificationChannel()

        // Register receiver for notification dismissal
        val filter = IntentFilter(ACTION_NOTIFICATION_DISMISSED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissalReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissalReceiver, filter)
        }
        Log.d(TAG, "Dismissal receiver registered")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service started")

        // Check if this is an error notification request
        val showError = intent?.getBooleanExtra("showError", false) ?: false
        if (showError) {
            val title = intent?.getStringExtra("errorTitle") ?: "Error"
            val message = intent?.getStringExtra("errorMessage") ?: ""
            showErrorNotification(title, message)
            return START_STICKY
        }

        val mode = intent?.getStringExtra("mode") ?: MODE_IDLE
        val message = intent?.getStringExtra("message")
        val durationMinutes = intent?.getLongExtra("durationMinutes", -1L) ?: -1L

        if (message != null) {
            // Update notification message without changing mode
            updateNotificationText(message)
        } else {
            // Update service mode (which also updates notification)
            updateServiceMode(mode, durationMinutes)
        }

        // Keep service running after app is killed
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        // Not a bound service for Phase 1
        return null
    }

    override fun onDestroy() {
        Log.d(TAG, "Service destroyed")
        releaseWakeLock()
        stopNotificationUpdates()
        try {
            unregisterReceiver(dismissalReceiver)
            Log.d(TAG, "Dismissal receiver unregistered")
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering dismissal receiver: ${e.message}")
        }
        super.onDestroy()
    }

    private fun updateServiceMode(mode: String, durationMinutes: Long = -1L) {
        currentMode = mode
        Log.d(TAG, "Mode changed to: $mode (duration: $durationMinutes min)")

        try {
            when (mode) {
                MODE_IDLE -> {
                    // IMPORTANT: Don't stop service during IDLE - it's just a transition state
                    // Keep service running to avoid Android killing it when restarting from background
                    Log.d(TAG, "Mode idle - keeping service alive during transition")
                    releaseWakeLock()
                    stopNotificationUpdates()
                    // Keep last notification visible (don't remove it)
                }
                MODE_RECORDING -> {
                    Log.d(TAG, "Starting foreground service for recording")
                    acquireWakeLock(durationMinutes)

                    // Track start time and duration for time display
                    recordingStartTime = System.currentTimeMillis()
                    recordingDurationMinutes = durationMinutes

                    // Create notification and track its text
                    val endTime = if (durationMinutes > 0) getEndTimeText() else ""
                    lastNotificationText = if (durationMinutes > 0) {
                        "Listening... (ends at $endTime)"
                    } else {
                        "Listening... (unlimited)"
                    }

                    val notification = createNotificationWithTime()
                    startForeground(NOTIFICATION_ID, notification)

                    // Start periodic updates for limited durations
                    if (durationMinutes > 0) {
                        startNotificationUpdates()
                    }

                    Log.d(TAG, "Foreground service started with notification")
                }
                MODE_PLAYING -> {
                    Log.d(TAG, "Starting foreground service for playback")
                    releaseWakeLock() // No wake lock needed for playback
                    stopNotificationUpdates()
                    val notification = createNotification("Speaking...")
                    startForeground(NOTIFICATION_ID, notification)
                    Log.d(TAG, "Foreground service started with notification")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating service mode: ${e.message}", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Audio Service",
                NotificationManager.IMPORTANCE_DEFAULT // DEFAULT shows in status bar without sound
            ).apply {
                description = "Keeps Relagent running for background audio"
                setShowBadge(false)
                setSound(null, null) // No sound
                enableVibration(false) // No vibration
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun createErrorNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ERROR_CHANNEL_ID,
                "Errors and Alerts",
                NotificationManager.IMPORTANCE_HIGH // HIGH shows heads-up notification
            ).apply {
                description = "Important alerts about listening failures"
                setShowBadge(true)
                // Keep default sound and vibration for errors
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Error notification channel created")
        }
    }

    private fun createNotification(contentText: String): Notification {
        // Create delete intent to detect when notification is dismissed
        val deleteIntent = Intent(ACTION_NOTIFICATION_DISMISSED).apply {
            setPackage(packageName)
        }
        val deletePendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            deleteIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Relagent conversation active")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // Standard system icon that exists on all devices
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // Cannot be dismissed
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setDeleteIntent(deletePendingIntent) // Detect dismissal attempts

        // Add stop button for recording or playback modes
        if (currentMode != MODE_IDLE) {
            val stopIntent = Intent(ACTION_STOP).apply {
                setPackage(packageName)
            }
            val stopPendingIntent = PendingIntent.getBroadcast(
                this,
                0,
                stopIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "Stop",
                stopPendingIntent
            )
        }

        return builder.build()
    }

    fun updateNotificationText(message: String) {
        // Skip update if text hasn't changed
        if (message == lastNotificationText) {
            Log.d(TAG, "Skipping notification update - text unchanged: $message")
            return
        }

        Log.d(TAG, "Updating notification text: $message")
        lastNotificationText = message
        val notification = createNotification(message)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun recreateNotification() {
        Log.d(TAG, "Recreating notification after dismissal")
        when (currentMode) {
            MODE_RECORDING -> {
                val notification = createNotificationWithTime()
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notification)
                Log.d(TAG, "Recording notification recreated")
            }
            MODE_PLAYING -> {
                val notification = createNotification("Speaking...")
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notification)
                Log.d(TAG, "Playing notification recreated")
            }
            else -> {
                Log.d(TAG, "Not recreating notification - mode is $currentMode")
            }
        }
    }

    private fun acquireWakeLock(durationMinutes: Long = -1L) {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$TAG::RecordingWakeLock"
            ).apply {
                setReferenceCounted(false)
            }
        }

        if (wakeLock?.isHeld == false) {
            // Calculate wake lock timeout based on user setting
            val timeoutMs = when {
                durationMinutes < 0 -> {
                    // Unlimited: use 24 hour timeout
                    Log.d(TAG, "Unlimited duration - using 24h wake lock")
                    24 * 60 * 60 * 1000L
                }
                else -> {
                    // Limited: user duration + 5 minute buffer
                    val totalMinutes = durationMinutes + 5
                    Log.d(TAG, "Limited duration - using ${totalMinutes}min wake lock (${durationMinutes}min + 5min buffer)")
                    totalMinutes * 60 * 1000L
                }
            }

            wakeLock?.acquire(timeoutMs)
            Log.d(TAG, "Wake lock acquired for ${timeoutMs / 1000 / 60}min")
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Wake lock released")
            }
        }
    }

    // Time Display Methods

    private fun createNotificationWithTime(): Notification {
        val text = if (recordingDurationMinutes > 0) {
            val endTime = getEndTimeText()
            "Listening... (ends at $endTime)"
        } else {
            "Listening... (unlimited)"
        }
        Log.d(TAG, "Creating recording notification with text: $text")
        return createNotification(text)
    }

    private fun getEndTimeText(): String {
        if (recordingDurationMinutes <= 0) return ""

        val endTimeMs = recordingStartTime + (recordingDurationMinutes * 60 * 1000)
        val endDate = Date(endTimeMs)
        val timeFormat = android.text.format.DateFormat.getTimeFormat(this)
        return timeFormat.format(endDate)
    }

    private fun updateNotificationWithEndTime() {
        if (currentMode == MODE_RECORDING && recordingDurationMinutes > 0) {
            // Calculate what the new notification text would be
            val endTime = getEndTimeText()
            val newText = "Listening... (ends at $endTime)"

            // Skip update if text hasn't changed
            if (newText == lastNotificationText) {
                Log.d(TAG, "Skipping notification update - text unchanged: $newText")
                return
            }

            // Update notification
            lastNotificationText = newText
            val notification = createNotificationWithTime()
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notification)
            Log.d(TAG, "Notification updated with new text: $newText")
        }
    }

    private fun startNotificationUpdates() {
        stopNotificationUpdates()
        notificationUpdateHandler.postDelayed(notificationUpdateRunnable, 60000)
        Log.d(TAG, "Started notification time updates (every 60s)")
    }

    private fun stopNotificationUpdates() {
        notificationUpdateHandler.removeCallbacks(notificationUpdateRunnable)
        lastNotificationText = "" // Reset so next update isn't skipped
        Log.d(TAG, "Stopped notification time updates")
    }

    // Error Notification Methods

    fun showErrorNotification(title: String, message: String) {
        Log.d(TAG, "Showing error notification: $title - $message")

        // Create intent to open settings (reopen the app)
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, ERROR_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .setAutoCancel(true) // Can be dismissed
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_preferences,
                "Open App",
                pendingIntent
            )
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(ERROR_NOTIFICATION_ID, notification)
    }

}

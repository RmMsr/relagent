package org.venkado.relagent

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Single owner of Android audio routing state (audio mode + communication device).
 * No other component may write these. Routing is only active on API 31+; on older
 * versions every method reports "unsupported" and the default mic is used.
 *
 * Route readiness is awaited via OnCommunicationDeviceChangedListener — the actual
 * route change — never the sticky SCO broadcast or polling. The route is held for
 * IDLE_RELEASE_MS after a recording stops so consecutive utterances skip the SCO
 * reconnect, then released so other apps regain A2DP.
 */
class MicRouter(context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "MicRouter"
        private const val METHOD_CHANNEL = "com.relagent.mic_router"
        private const val EVENT_CHANNEL = "com.relagent.mic_router_events"
        private const val READY_TIMEOUT_MS = 3000L
        private const val IDLE_RELEASE_MS = 5000L
    }

    private val appContext = context.applicationContext
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    private var idleRelease: Runnable? = null
    private var targetDevice: AudioDeviceInfo? = null
    private var routeHeld = false

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) {
            Log.d(TAG, "Devices added: ${added.joinToString { typeString(it.type) }}")
            emitDeviceChange()
        }

        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) {
            Log.d(TAG, "Devices removed: ${removed.joinToString { typeString(it.type) }}")
            emitDeviceChange()
        }
    }

    // Diagnostics only: reports which device the recording actually landed on.
    // Never drives behavior — Android can report a route that diverges from
    // what the audio HAL really captures from, and there is no app-level API
    // that can see through that, so routing stays best effort.
    private val recordingCallback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            for (config in configs) {
                val actual = config.audioDevice ?: continue
                Log.d(TAG, "Recording routed to ${typeString(actual.type)} (id=${actual.id})")
                val target = targetDevice
                // Compare by type (+ address when available), not id: actual
                // comes from AudioRecordingConfiguration while target comes from
                // availableCommunicationDevices — different enumeration APIs can
                // assign different ids to the very same physical route.
                val addressMatches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    target?.address == actual.address
                } else {
                    true
                }
                if (routeHeld && target != null &&
                    (actual.type != target.type || !addressMatches)) {
                    Log.w(
                        TAG,
                        "Route mismatch: target ${typeString(target.type)} " +
                            "but recording on ${typeString(actual.type)}"
                    )
                }
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "listInputs" -> result.success(listInputs())
                    "querySelection" -> result.success(handleQuerySelection(call.arguments()))
                    "ensureReady" -> handleEnsureReady(call.arguments(), result)
                    "releaseAfterIdle" -> {
                        scheduleIdleRelease()
                        result.success(null)
                    }
                    "releaseNow" -> {
                        releaseNow()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Method ${call.method} failed: ${e.message}", e)
                result.error("mic_router", e.message, null)
            }
        }
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
        audioManager.registerAudioRecordingCallback(recordingCallback, mainHandler)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        audioManager.unregisterAudioRecordingCallback(recordingCallback)
        cancelIdleRelease()
        if (routeHeld) releaseNow()
    }

    private fun emitDeviceChange() {
        mainHandler.post { eventSink?.success("devicesChanged") }
    }

    // --- Device enumeration ---

    private fun listInputs(): List<Map<String, Any?>> {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val result = mutableListOf<Map<String, Any?>>()
        var builtinSeen = false
        for (device in devices) {
            val category = categoryOf(device.type) ?: continue
            // Phones expose several built-in mics (bottom, back); show one entry.
            if (category == "builtin") {
                if (builtinSeen) continue
                builtinSeen = true
            }
            result.add(deviceMap(device))
        }
        return result
    }

    private fun categoryOf(type: Int): String? = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtin"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
        26 /* TYPE_BLE_HEADSET (API 31) */ -> "bluetooth"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
        else -> null
    }

    private fun deviceMap(device: AudioDeviceInfo): Map<String, Any?> = mapOf(
        "id" to device.id,
        "category" to (categoryOf(device.type) ?: "other"),
        "name" to device.productName.toString(),
        "address" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) device.address else "",
    )

    // --- Selection policy: pinned -> Bluetooth -> built-in ---

    private data class Selection(val device: AudioDeviceInfo?, val fellBack: Boolean)

    @RequiresApi(Build.VERSION_CODES.S)
    private fun selectDevice(preference: Map<String, Any?>?): Selection {
        val mode = preference?.get("mode") as? String ?: "auto"
        val candidates = audioManager.availableCommunicationDevices
        Log.d(
            TAG,
            "selectDevice: mode=$mode preference=$preference candidates=" +
                candidates.joinToString { "${typeString(it.type)}(id=${it.id})" },
        )
        if (mode == "pinned") {
            val category = preference?.get("category") as? String
            if (category == "builtin") return Selection(null, false)
            val address = preference?.get("address") as? String
            val match = candidates.firstOrNull {
                categoryOf(it.type) == category &&
                    (address.isNullOrEmpty() || it.address == address)
            }
            if (match != null) return Selection(match, false)
            return Selection(autoPick(candidates), fellBack = true)
        }
        return Selection(autoPick(candidates), false)
    }

    private fun autoPick(candidates: List<AudioDeviceInfo>): AudioDeviceInfo? =
        candidates.firstOrNull { categoryOf(it.type) == "bluetooth" }

    private fun handleQuerySelection(preference: Map<String, Any?>?): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return mapOf("status" to "unsupported", "device" to null)
        }
        val selection = selectDevice(preference)
        return mapOf(
            "status" to if (selection.fellBack) "fallback" else "ok",
            "device" to selection.device?.let { deviceMap(it) },
        )
    }

    // --- Route establishment ---

    private fun handleEnsureReady(preference: Map<String, Any?>?, result: MethodChannel.Result) {
        cancelIdleRelease()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(mapOf("status" to "unsupported", "device" to null))
            return
        }
        ensureReady31(preference, result)
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun ensureReady31(preference: Map<String, Any?>?, result: MethodChannel.Result) {
        val selection = selectDevice(preference)
        val target = selection.device
        if (target == null) {
            // Built-in target: drop any route we still hold so the default mic wins.
            if (routeHeld) releaseNow()
            targetDevice = null
            result.success(
                mapOf(
                    "status" to if (selection.fellBack) "fallback" else "ok",
                    "device" to null,
                )
            )
            return
        }

        targetDevice = target
        val doneStatus = if (selection.fellBack) "fallback" else "ok"
        if (audioManager.communicationDevice?.id == target.id) {
            routeHeld = true
            Log.d(TAG, "Route already active: ${typeString(target.type)}")
            result.success(mapOf("status" to doneStatus, "device" to deviceMap(target)))
            return
        }

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        val requested = audioManager.setCommunicationDevice(target)
        if (!requested) {
            Log.w(TAG, "setCommunicationDevice rejected for ${typeString(target.type)}")
            result.success(mapOf("status" to "failed", "device" to deviceMap(target)))
            return
        }
        routeHeld = true

        var done = false
        var listener: AudioManager.OnCommunicationDeviceChangedListener? = null
        fun finish(status: String) {
            if (done) return
            done = true
            listener?.let { audioManager.removeOnCommunicationDeviceChangedListener(it) }
            Log.d(TAG, "ensureReady: $status for ${typeString(target.type)}")
            result.success(mapOf("status" to status, "device" to deviceMap(target)))
        }

        val timeout = Runnable { finish("timeout") }
        listener = AudioManager.OnCommunicationDeviceChangedListener { device ->
            if (device?.id == target.id) {
                mainHandler.removeCallbacks(timeout)
                finish(doneStatus)
            }
        }
        audioManager.addOnCommunicationDeviceChangedListener(appContext.mainExecutor, listener)
        mainHandler.postDelayed(timeout, READY_TIMEOUT_MS)
        // The route may have flipped between the fast-path check and listener registration.
        if (audioManager.communicationDevice?.id == target.id) {
            mainHandler.removeCallbacks(timeout)
            finish(doneStatus)
        }
    }

    // --- Release ---

    private fun scheduleIdleRelease() {
        cancelIdleRelease()
        if (!routeHeld) return
        val runnable = Runnable {
            idleRelease = null
            releaseNow()
        }
        idleRelease = runnable
        mainHandler.postDelayed(runnable, IDLE_RELEASE_MS)
        Log.d(TAG, "Idle release scheduled in ${IDLE_RELEASE_MS}ms")
    }

    private fun cancelIdleRelease() {
        idleRelease?.let { mainHandler.removeCallbacks(it) }
        idleRelease = null
    }

    private fun releaseNow() {
        cancelIdleRelease()
        targetDevice = null
        if (!routeHeld && audioManager.mode == AudioManager.MODE_NORMAL) return
        routeHeld = false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            }
            audioManager.mode = AudioManager.MODE_NORMAL
            Log.d(TAG, "Route released, audio mode NORMAL")
        } catch (e: Exception) {
            Log.e(TAG, "Release failed: ${e.message}", e)
        }
    }

    private fun typeString(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BUILTIN_MIC"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BLUETOOTH_SCO"
        26 -> "BLE_HEADSET"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB_DEVICE"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB_HEADSET"
        else -> "TYPE_$type"
    }
}

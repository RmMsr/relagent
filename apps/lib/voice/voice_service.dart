import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '/speech_recognition/asr_metadata.dart';
import '/voice/model_resolver.dart';
import 'voice_service_stub.dart'
    if (dart.library.io) 'voice_service_native.dart'
    as platform;

/// Replaces RecordState from package:record.
/// Used by providers and widgets to track recording lifecycle.
enum AudioRecordingStatus { stopped, recording, paused }

/// Local type replacing AudioInterruptionType from audio_session.
enum AudioInterruptionType { pause, duck, unknown }

/// Local event type for audio interruptions (phone calls, alarms, etc.).
class AudioInterruptionEvent {
  final AudioInterruptionType type;
  final bool begin;

  const AudioInterruptionEvent({required this.type, required this.begin});
}

/// Query interface for platform voice capabilities.
abstract mixin class VoiceCapabilities {
  bool get isAsrAvailable;
  bool get isTtsAvailable;
  bool get isBackgroundListeningAvailable;

  /// Whether the platform supports enumerating and selecting input devices.
  /// Note: on Android below API 31 the surface exists but selection results
  /// report [MicSelectionStatus.unsupported].
  bool get isInputSelectionAvailable;
}

/// Category of an audio input device, used for selection and the button symbol.
enum MicDeviceCategory { builtin, bluetooth, wired, usb, other }

/// An available audio input device as reported by the platform.
class MicDevice {
  final int id;
  final MicDeviceCategory category;
  final String name;
  final String address;

  const MicDevice({
    required this.id,
    required this.category,
    required this.name,
    this.address = '',
  });

  factory MicDevice.fromMap(Map<dynamic, dynamic> map) => MicDevice(
    id: (map['id'] as num?)?.toInt() ?? 0,
    category: MicDeviceCategory.values.asNameMap()[map['category']] ??
        MicDeviceCategory.other,
    name: map['name'] as String? ?? '',
    address: map['address'] as String? ?? '',
  );

  @override
  String toString() => 'MicDevice(${category.name}, $name)';
}

/// Microphone preference: automatic (Bluetooth-first) or pinned to a device.
///
/// Pinned devices are identified by category + address (+ name for display),
/// not by platform device ID, which is not stable across reboots.
class MicPreference {
  final MicDeviceCategory? category;
  final String address;
  final String name;

  const MicPreference.auto() : category = null, address = '', name = '';

  const MicPreference.pinned({
    required MicDeviceCategory this.category,
    this.address = '',
    this.name = '',
  });

  bool get isAuto => category == null;

  bool matches(MicDevice device) =>
      category == device.category &&
      (address.isEmpty || address == device.address);

  Map<String, Object?> toChannelMap() => isAuto
      ? const {'mode': 'auto'}
      : {'mode': 'pinned', 'category': category!.name, 'address': address};

  Map<String, Object?> toJson() =>
      {'category': category?.name, 'address': address, 'name': name};

  factory MicPreference.fromJson(Map<String, dynamic> json) {
    final category =
        MicDeviceCategory.values.asNameMap()[json['category'] as String?];
    if (category == null) return const MicPreference.auto();
    return MicPreference.pinned(
      category: category,
      address: json['address'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

/// Outcome of resolving or establishing the input device selection.
enum MicSelectionStatus {
  /// Selection resolved (and, for ensureReady, route active).
  ok,

  /// Pinned device absent; automatic selection applied instead.
  fallback,

  /// Route did not become active within the timeout; recording proceeds.
  timeout,

  /// The platform rejected the routing request.
  failed,

  /// Platform has no input selection (web, iOS, Android < 12).
  unsupported,

  /// Channel error; degraded to default device.
  error,
}

class MicSelectionResult {
  final MicSelectionStatus status;

  /// The selected device; null means the platform default (built-in) mic.
  final MicDevice? device;

  const MicSelectionResult(this.status, this.device);
}

/// Abstract interface encapsulating all voice-related platform dependencies.
///
/// Native platforms provide a full implementation wrapping sherpa_onnx, record,
/// and audio_session. Web provides a no-op stub.
abstract class VoiceService implements VoiceCapabilities {
  // ASR

  /// Initialize the audio recorder (microphone permissions, state listeners).
  void initAudioRecorder();

  /// Initialize ASR model and start recording.
  /// Pass [asrMetadata] to use a downloaded model instead of bundled.
  Future<void> startRecording({
    required ValueChanged<String> onTextRecognized,
    required VoidCallback onTextFinished,
    ValueChanged<AudioRecordingStatus>? onStatusChanged,
    VoidCallback? onAudioDataReceived,
    ValueChanged<double>? onAmplitudeChanged,
    ValueChanged<Object>? onStreamError,
    VoidCallback? onStreamDone,
    AsrModelMetadata? asrMetadata,
  });

  Future<void> stopRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();

  // TTS

  /// Initialize TTS engine (may spawn background isolate).
  /// Pass [resolvedTtsModel] to use a downloaded model instead of bundled.
  Future<void> initializeTts({ResolvedTtsModel? resolvedTtsModel});

  /// Generate speech audio from text. Returns WAV bytes or null on failure.
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    int speakerId = 0,
    double speed = 1.0,
  });

  /// Dispose TTS resources.
  void disposeTts();

  // Audio session

  /// Configure audio session for speech/communication mode (initial one-time setup).
  Future<void> configureAudioSession();

  /// Configure and activate audio session for voice input (enables Bluetooth SCO mic).
  Future<void> configureAudioSessionForRecording();

  /// Configure and activate audio session for speech playback (uses Bluetooth A2DP).
  Future<void> configureAudioSessionForPlayback();

  /// Activate audio session.
  Future<void> activateAudioSession();

  /// Deactivate audio session.
  Future<void> deactivateAudioSession();

  /// Stream of audio interruption events (phone calls, alarms, etc.).
  /// Empty on platforms without audio session support.
  Stream<AudioInterruptionEvent> get interruptionEvents;

  /// Stream of audio device change events (Bluetooth connect/disconnect).
  /// Empty on platforms without audio session support.
  Stream<void> get deviceChangedEvents;

  // Input device selection (Android 12+; no-op elsewhere)

  /// List available input devices. Empty where unsupported.
  Future<List<MicDevice>> listInputDevices();

  /// Set the microphone preference applied to subsequent recordings.
  void setInputDevicePreference(MicPreference preference);

  /// Resolve which input device the current preference selects, without
  /// changing any routing state. Used for the recording button symbol.
  Future<MicSelectionResult> queryInputSelection();

  // Background service (Android foreground service)

  Future<void> startBackgroundService(String mode, {int durationMinutes = -1});
  Future<void> stopBackgroundService();
  Future<void> updateNotification(String message);
  Future<void> showErrorNotification(String title, String message);

  /// Set up handler for notification actions (e.g., "Stop" button).
  void setupNotificationActionHandler(Future<void> Function(String) handler);

  void dispose();
}

VoiceService createVoiceService() => platform.createVoiceService();

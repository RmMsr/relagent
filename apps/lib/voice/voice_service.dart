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

  /// Pre-cache TTS model files (call from main isolate before generating).
  Future<void> preCacheTtsModels();

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

  /// Configure audio session for speech/communication mode.
  Future<void> configureAudioSession();

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

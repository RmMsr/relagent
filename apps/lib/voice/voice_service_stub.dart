import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '/voice/voice_service.dart';

/// No-op voice service for platforms without native voice support (web).
class NoOpVoiceService extends VoiceService {
  @override
  bool get isAsrAvailable => false;

  @override
  bool get isTtsAvailable => false;

  @override
  bool get isBackgroundListeningAvailable => false;

  // ASR — no-ops

  @override
  void initAudioRecorder() {}

  @override
  Future<void> startRecording({
    required ValueChanged<String> onTextRecognized,
    required VoidCallback onTextFinished,
    ValueChanged<AudioRecordingStatus>? onStatusChanged,
    VoidCallback? onAudioDataReceived,
    ValueChanged<double>? onAmplitudeChanged,
    ValueChanged<Object>? onStreamError,
    VoidCallback? onStreamDone,
  }) async {}

  @override
  Future<void> stopRecording() async {}

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  // TTS — no-ops

  @override
  Future<void> preCacheTtsModels() async {}

  @override
  Future<void> initializeTts() async {}

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    int speakerId = 0,
    double speed = 1.0,
  }) async => null;

  @override
  void disposeTts() {}

  // Audio session — no-ops

  @override
  Future<void> configureAudioSession() async {}

  @override
  Future<void> activateAudioSession() async {}

  @override
  Future<void> deactivateAudioSession() async {}

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents => const Stream.empty();

  @override
  Stream<void> get deviceChangedEvents => const Stream.empty();

  // Background service — no-ops

  @override
  Future<void> startBackgroundService(
    String mode, {
    int durationMinutes = -1,
  }) async {}

  @override
  Future<void> stopBackgroundService() async {}

  @override
  Future<void> updateNotification(String message) async {}

  @override
  Future<void> showErrorNotification(String title, String message) async {}

  @override
  void setupNotificationActionHandler(Future<void> Function(String) handler) {}

  @override
  void dispose() {}
}

VoiceService createVoiceService() => NoOpVoiceService();

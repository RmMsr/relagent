import 'dart:async';

import 'package:audio_session/audio_session.dart' as native_audio;
import 'package:flutter/services.dart';
import '/config/app_config.dart';
import '/models/model_catalog.dart';
import '/speech_recognition/services.dart' as asr;
import '/speech_recognition/asr_metadata.dart';
import '/speech_recognition/sherpa_vad_asr.dart';
import '/tts/sherpa_tts.dart' as native_tts;
import '/tts/tts_isolate_worker.dart';
import '/utils/logger.dart';
import '/voice/asset_model_loader.dart';
import 'package:sherpa_voice/model_loader.dart';
import '/voice/model_resolver.dart';
import '/voice/voice_service.dart';
import 'package:record/record.dart' as record_pkg;

/// Native voice service wrapping sherpa_onnx, record, and audio_session.
class NativeVoiceService extends VoiceService {
  final ModelLoader _modelLoader = AssetModelLoader();
  asr.AsrService? _asr;
  TtsIsolateWorker? _ttsWorker;
  bool _ttsInitialized = false;

  static const _backgroundServiceChannel = MethodChannel(
    'com.relagent.background_service',
  );
  static const _notificationActionsChannel = MethodChannel(
    'com.relagent.notification_actions',
  );

  final StreamController<AudioInterruptionEvent> _interruptionController =
      StreamController.broadcast();
  final StreamController<void> _deviceChangedController =
      StreamController.broadcast();

  StreamSubscription<dynamic>? _interruptionSub;
  StreamSubscription<dynamic>? _deviceChangedSub;

  @override
  bool get isAsrAvailable => true;

  @override
  bool get isTtsAvailable => true;

  @override
  bool get isBackgroundListeningAvailable => true;

  ModelLoader get modelLoader => _modelLoader;

  // --- ASR ---

  @override
  void initAudioRecorder() {
    _asr?.init();
  }

  @override
  Future<void> startRecording({
    required ValueChanged<String> onTextRecognized,
    required VoidCallback onTextFinished,
    ValueChanged<AudioRecordingStatus>? onStatusChanged,
    VoidCallback? onAudioDataReceived,
    ValueChanged<double>? onAmplitudeChanged,
    ValueChanged<Object>? onStreamError,
    VoidCallback? onStreamDone,
    AsrModelMetadata? asrMetadata,
  }) async {
    // Recreate ASR if the model changed (compare by ID, not object reference)
    if (_asr != null && _asr!.modelMetadata?.modelId != asrMetadata?.modelId) {
      _asr!.dispose();
      _asr = null;
    }

    if (_asr == null) {
      final isOffline =
          asrMetadata?.architecture == ModelArchitecture.offlineNemoTransducer;
      if (isOffline) {
        Logger.debug('NativeVoiceService: Using VAD-based offline ASR');
        _asr = VadAsr(
          textRecognized: onTextRecognized,
          textFinished: onTextFinished,
          onStatusChanged: onStatusChanged,
          onAudioDataReceived: onAudioDataReceived,
          onAmplitudeChanged: onAmplitudeChanged,
          onStreamError: onStreamError,
          onStreamDone: onStreamDone,
          modelMetadata: asrMetadata!,
        );
      } else {
        _asr = asr.ASR(
          textRecognized: onTextRecognized,
          textFinished: onTextFinished,
          onRecordStateChanged: onStatusChanged != null
              ? (state) => onStatusChanged(_mapRecordState(state))
              : null,
          onAudioDataReceived: onAudioDataReceived,
          onAmplitudeChanged: onAmplitudeChanged,
          onStreamError: onStreamError,
          onStreamDone: onStreamDone,
          modelMetadata: asrMetadata,
        );
      }
    }
    _asr!.init();
    await _asr!.start();
  }

  @override
  Future<void> stopRecording() async {
    await _asr?.stop();
  }

  @override
  Future<void> pauseRecording() async {
    await _asr?.pause();
  }

  @override
  Future<void> resumeRecording() async {
    await _asr?.resume();
  }

  AudioRecordingStatus _mapRecordState(record_pkg.RecordState state) {
    return switch (state) {
      record_pkg.RecordState.stop => AudioRecordingStatus.stopped,
      record_pkg.RecordState.record => AudioRecordingStatus.recording,
      record_pkg.RecordState.pause => AudioRecordingStatus.paused,
    };
  }

  // --- TTS ---

  @override
  Future<void> preCacheTtsModels() async {
    if (AppConfig.ttsModelName == null) return;
    await native_tts.preCacheTtsModelFiles();
  }

  ResolvedTtsModel? _currentResolvedTtsModel;

  @override
  Future<void> initializeTts({ResolvedTtsModel? resolvedTtsModel}) async {
    // Check if we need to reinitialize with a different model
    if (_ttsInitialized && resolvedTtsModel != _currentResolvedTtsModel) {
      Logger.debug('NativeVoiceService: TTS model changed, reinitializing');
      disposeTts();
    }

    if (_ttsInitialized) return;

    // Need either a bundled model or a resolved downloaded model
    if (AppConfig.ttsModelName == null && resolvedTtsModel == null) {
      Logger.debug('NativeVoiceService: No TTS model available, skipping init');
      return;
    }
    _currentResolvedTtsModel = resolvedTtsModel;
    _ttsWorker = TtsIsolateWorker();
    await _ttsWorker!.initialize(resolvedModel: resolvedTtsModel);
    _ttsInitialized = true;
  }

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    if (!_ttsInitialized || _ttsWorker == null) {
      await initializeTts(resolvedTtsModel: _currentResolvedTtsModel);
    }

    try {
      return await _ttsWorker!.generateAudio(
        text: text,
        messageId: messageId,
        speakerId: speakerId,
        speed: speed,
      );
    } catch (e) {
      Logger.debug('NativeVoiceService: TTS generation failed: $e');
      return null;
    }
  }

  @override
  void disposeTts() {
    _ttsWorker?.dispose();
    _ttsWorker = null;
    _ttsInitialized = false;
  }

  // --- Audio Session ---

  @override
  Future<void> configureAudioSession() async {
    try {
      final session = await native_audio.AudioSession.instance;
      await session.configure(
        const native_audio.AudioSessionConfiguration.speech(),
      );

      // Subscribe to interruption events if not already subscribed
      _interruptionSub ??= session.interruptionEventStream.listen((event) {
        AudioInterruptionType type;
        switch (event.type) {
          case native_audio.AudioInterruptionType.pause:
            type = AudioInterruptionType.pause;
          case native_audio.AudioInterruptionType.duck:
            type = AudioInterruptionType.duck;
          case native_audio.AudioInterruptionType.unknown:
            type = AudioInterruptionType.unknown;
        }
        _interruptionController.add(
          AudioInterruptionEvent(type: type, begin: event.begin),
        );
      });

      // Subscribe to device changes if not already subscribed
      _deviceChangedSub ??= session.devicesChangedEventStream.listen((event) {
        Logger.debug('NativeVoiceService: Audio devices changed');
        Logger.debug('  Devices added: ${event.devicesAdded}');
        Logger.debug('  Devices removed: ${event.devicesRemoved}');
        _deviceChangedController.add(null);
      });
    } catch (e) {
      Logger.debug('NativeVoiceService: Failed to configure audio session: $e');
    }
  }

  @override
  Future<void> activateAudioSession() async {
    try {
      final session = await native_audio.AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      Logger.debug('NativeVoiceService: Failed to activate audio session: $e');
    }
  }

  @override
  Future<void> deactivateAudioSession() async {
    try {
      final session = await native_audio.AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      Logger.debug(
        'NativeVoiceService: Failed to deactivate audio session: $e',
      );
    }
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents =>
      _interruptionController.stream;

  @override
  Stream<void> get deviceChangedEvents => _deviceChangedController.stream;

  // --- Background Service ---

  @override
  Future<void> startBackgroundService(
    String mode, {
    int durationMinutes = -1,
  }) async {
    try {
      final arguments = <String, dynamic>{'mode': mode};
      if (mode == 'recording') {
        arguments['durationMinutes'] = durationMinutes;
      }
      await _backgroundServiceChannel.invokeMethod('startService', arguments);
    } on PlatformException catch (e) {
      Logger.debug(
        'NativeVoiceService: Failed to start background service: ${e.message}',
      );
      rethrow;
    }
  }

  @override
  Future<void> stopBackgroundService() async {
    try {
      await _backgroundServiceChannel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      Logger.debug(
        'NativeVoiceService: Failed to stop background service: ${e.message}',
      );
      rethrow;
    }
  }

  @override
  Future<void> updateNotification(String message) async {
    try {
      await _backgroundServiceChannel.invokeMethod('updateNotification', {
        'message': message,
      });
    } on PlatformException catch (e) {
      Logger.debug(
        'NativeVoiceService: Failed to update notification: ${e.message}',
      );
    }
  }

  @override
  Future<void> showErrorNotification(String title, String message) async {
    try {
      await _backgroundServiceChannel.invokeMethod('showErrorNotification', {
        'title': title,
        'message': message,
      });
    } catch (e) {
      Logger.debug('NativeVoiceService: Failed to show error notification: $e');
    }
  }

  @override
  void setupNotificationActionHandler(Future<void> Function(String) handler) {
    _notificationActionsChannel.setMethodCallHandler((call) async {
      await handler(call.method);
    });
  }

  @override
  void dispose() {
    _asr?.dispose();
    _asr = null;
    disposeTts();
    _interruptionSub?.cancel();
    _deviceChangedSub?.cancel();
    _interruptionController.close();
    _deviceChangedController.close();
  }
}

VoiceService createVoiceService() => NativeVoiceService();

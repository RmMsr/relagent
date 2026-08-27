import 'dart:async';

import 'package:audio_session/audio_session.dart' as native_audio;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '/models/model_catalog.dart';
import '/speech_recognition/services.dart' as asr;
import '/speech_recognition/asr_metadata.dart';
import '/speech_recognition/sherpa_vad_asr.dart';
import '/tts/tts_isolate_worker.dart';
import '/utils/logger.dart';
import '/voice/lru_pool.dart';
import '/voice/mic_router.dart';
import '/voice/model_resolver.dart';
import '/voice/voice_service.dart';
import 'package:record/record.dart' as record_pkg;

/// Native voice service wrapping sherpa_onnx, record, and audio_session.
/// Android microphone routing is owned by the native MicRouter; this class
/// only sequences it (ensureReady before the recorder opens, release after).
class NativeVoiceService extends VoiceService {
  asr.AsrService? _asr;

  final MicRouter _micRouter;
  MicPreference _micPreference = const MicPreference.auto();
  StreamSubscription<void>? _micEventsSub;
  // Set by configureAudioSessionForRecording(), read by startRecording() to
  // tell VadAsr which route it's about to record on.
  MicSelectionResult? _lastMicSelection;

  NativeVoiceService({MicRouter? micRouter})
    : _micRouter = micRouter ?? MicRouter();

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
  // audio_session's devicesChangedEventStream and MicRouter's own
  // AudioDeviceCallback both fire for the same underlying Bluetooth
  // connect/disconnect, each forwarding into _deviceChangedController below.
  // Debounce so one physical event triggers one reconfiguration, not two.
  Timer? _deviceChangeDebounce;

  @override
  bool get isAsrAvailable => true;

  @override
  bool get isTtsAvailable => true;

  @override
  bool get isBackgroundListeningAvailable => true;

  @override
  bool get isInputSelectionAvailable => _micRouter.isSupported;

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
      final isOffline = asrMetadata?.architecture.isOfflineAsr ?? false;
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
    await _asr!.start(
      isBluetoothRoute:
          _lastMicSelection?.device?.category == MicDeviceCategory.bluetooth,
    );
  }

  @override
  Future<void> stopRecording() async {
    await _asr?.stop();
    // Keep the route for 5s so a follow-up utterance skips SCO reconnect.
    await _micRouter.releaseAfterIdle();
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
  //
  // A small LRU pool of live TtsIsolateWorkers (each its own isolate holding
  // one loaded native model), keyed by resolved model id, so switching
  // between a handful of recently-used languages/models doesn't pay a
  // dispose+reload cost every time — only on a genuine pool miss. Keyed by
  // model id (a String) rather than the ResolvedTtsModel instance itself,
  // since callers legitimately construct a fresh ResolvedTtsModel per call.

  static const _maxTtsPoolSize = 3;

  late final _ttsPool = LruPool<String, TtsIsolateWorker>(
    maxSize: _maxTtsPoolSize,
    onEvict: (worker) {
      Logger.debug('NativeVoiceService: TTS pool evicted a worker');
      worker.dispose();
    },
  );

  Future<TtsIsolateWorker?> _ttsWorkerFor(
    ResolvedTtsModel? resolvedTtsModel,
  ) async {
    if (resolvedTtsModel == null) return null;
    final key = resolvedTtsModel.modelId;

    final existing = _ttsPool.get(key);
    if (existing != null) return existing;

    final worker = TtsIsolateWorker();
    await worker.initialize(resolvedModel: resolvedTtsModel);
    _ttsPool.put(key, worker);
    return worker;
  }

  @override
  Future<void> initializeTts({ResolvedTtsModel? resolvedTtsModel}) async {
    if (resolvedTtsModel == null) {
      Logger.debug('NativeVoiceService: No TTS model available, skipping init');
      return;
    }
    await _ttsWorkerFor(resolvedTtsModel);
  }

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    ResolvedTtsModel? resolvedTtsModel,
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    final worker = await _ttsWorkerFor(resolvedTtsModel);
    if (worker == null) return null;

    try {
      return await worker.generateAudio(
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
    _ttsPool.clear();
  }

  // --- Input device selection ---

  @override
  Future<List<MicDevice>> listInputDevices() => _micRouter.listInputs();

  @override
  void setInputDevicePreference(MicPreference preference) {
    _micPreference = preference;
  }

  @override
  Future<MicSelectionResult> queryInputSelection() =>
      _micRouter.querySelection(_micPreference);

  // --- Audio Session ---

  @override
  Future<void> configureAudioSessionForRecording() async {
    try {
      final session = await native_audio.AudioSession.instance;
      await session.configure(
        native_audio.AudioSessionConfiguration(
          // iOS: playAndRecord + voiceChat enables Bluetooth HFP mic
          avAudioSessionCategory:
              native_audio.AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              native_audio.AVAudioSessionCategoryOptions.allowBluetooth |
              native_audio.AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: native_audio.AVAudioSessionMode.voiceChat,
          // Android: voiceCommunication activates Bluetooth SCO for mic input
          androidAudioAttributes: const native_audio.AndroidAudioAttributes(
            contentType: native_audio.AndroidAudioContentType.speech,
            usage: native_audio.AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType:
              native_audio.AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      // Establish the mic route and wait until Android reports it active, so
      // the recorder opens on the intended device (MicRouter bounds the wait).
      // Best effort: whatever Android reports is what we record on.
      _lastMicSelection = await _micRouter.ensureReady(_micPreference);
    } catch (e) {
      Logger.debug(
        'NativeVoiceService: Failed to configure audio session for recording: $e',
      );
    }
  }

  @override
  Future<void> configureAudioSessionForPlayback() async {
    try {
      final session = await native_audio.AudioSession.instance;
      await session.configure(
        native_audio.AudioSessionConfiguration(
          // iOS: playback + allowBluetoothA2dp routes to high-quality BT output
          avAudioSessionCategory: native_audio.AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              native_audio.AVAudioSessionCategoryOptions.allowBluetooth |
              native_audio.AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          avAudioSessionMode: native_audio.AVAudioSessionMode.spokenAudio,
          // Android: assistant routes speech output through Bluetooth A2DP
          androidAudioAttributes: const native_audio.AndroidAudioAttributes(
            contentType: native_audio.AndroidAudioContentType.speech,
            usage: native_audio.AndroidAudioUsage.assistant,
          ),
          androidAudioFocusGainType:
              native_audio.AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      // Playback needs A2DP; drop any held mic route immediately.
      await _micRouter.releaseNow();
    } catch (e) {
      Logger.debug(
        'NativeVoiceService: Failed to configure audio session for playback: $e',
      );
    }
  }

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
        _scheduleDeviceChanged();
      });

      // MicRouter reports device-topology changes so the UI can refresh the
      // input-device symbol. The actual capture route is logged natively for
      // diagnostics only; it never drives behavior here.
      _micEventsSub ??= _micRouter.deviceChanges.listen((_) {
        Logger.debug('NativeVoiceService: MicRouter reported devicesChanged');
        _scheduleDeviceChanged();
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

  void _scheduleDeviceChanged() {
    _deviceChangeDebounce?.cancel();
    _deviceChangeDebounce = Timer(const Duration(milliseconds: 250), () {
      _deviceChangedController.add(null);
    });
  }

  @override
  void dispose() {
    _asr?.dispose();
    _asr = null;
    disposeTts();
    _interruptionSub?.cancel();
    _deviceChangedSub?.cancel();
    _micEventsSub?.cancel();
    _deviceChangeDebounce?.cancel();
    _interruptionController.close();
    _deviceChangedController.close();
  }
}

VoiceService createVoiceService() => NativeVoiceService();

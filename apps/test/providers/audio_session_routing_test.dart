import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/providers/audio_coordinator_provider.dart';
import 'package:relagent/providers/background_service_provider.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/voice_service_provider.dart';
import 'package:relagent/speech_recognition/asr_metadata.dart';
import 'package:relagent/voice/model_download_service.dart';
import 'package:relagent/voice/model_resolver.dart';
import 'package:relagent/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoOpModelDownloadService extends ModelDownloadService {
  @override
  Future<Set<String>> listDownloadedModels() async => {};
  @override
  Future<int> totalStorageUsed() async => 0;
  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {}
  @override
  void cancelDownload(String modelId) {}
  @override
  Future<void> deleteModel(String modelId) async {}
}

class _TrackingVoiceService extends VoiceService {
  int configureForRecordingCallCount = 0;
  int configureForPlaybackCallCount = 0;

  final _deviceChangedController = StreamController<void>.broadcast();

  void simulateDeviceChange() => _deviceChangedController.add(null);

  @override
  bool get isAsrAvailable => false;
  @override
  bool get isTtsAvailable => false;
  @override
  bool get isBackgroundListeningAvailable => false;

  @override
  bool get isInputSelectionAvailable => false;

  @override
  Future<List<MicDevice>> listInputDevices() async => const [];

  @override
  void setInputDevicePreference(MicPreference preference) {}

  @override
  Future<MicSelectionResult> queryInputSelection() async =>
      const MicSelectionResult(MicSelectionStatus.unsupported, null);

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
    AsrModelMetadata? asrMetadata,
  }) async {}

  @override
  Future<void> stopRecording() async {}
  @override
  Future<void> pauseRecording() async {}
  @override
  Future<void> resumeRecording() async {}

  @override
  Future<void> initializeTts({ResolvedTtsModel? resolvedTtsModel}) async {}

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    ResolvedTtsModel? resolvedTtsModel,
    int speakerId = 0,
    double speed = 1.0,
  }) async => null;

  @override
  void disposeTts() {}

  @override
  Future<void> configureAudioSession() async {}

  @override
  Future<void> configureAudioSessionForRecording() async {
    configureForRecordingCallCount++;
  }

  @override
  Future<void> configureAudioSessionForPlayback() async {
    configureForPlaybackCallCount++;
  }

  @override
  Future<void> activateAudioSession() async {}
  @override
  Future<void> deactivateAudioSession() async {}

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents => const Stream.empty();

  @override
  Stream<void> get deviceChangedEvents => _deviceChangedController.stream;

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
  void dispose() => _deviceChangedController.close();
}

void main() {
  late ProviderContainer container;
  late _TrackingVoiceService trackingService;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'user_settings':
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour"}',
    });
    final sharedPreferences = await SharedPreferences.getInstance();
    trackingService = _TrackingVoiceService();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        modelDownloadServiceProvider.overrideWithValue(
          _NoOpModelDownloadService(),
        ),
        voiceServiceProvider.overrideWithValue(trackingService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Audio session routing', () {
    test(
      'requestRecording() calls configureAudioSessionForRecording',
      () async {
        final coordinator = container.read(audioCoordinatorProvider.notifier);

        await coordinator.requestRecording();

        expect(trackingService.configureForRecordingCallCount, 1);
        expect(trackingService.configureForPlaybackCallCount, 0);
      },
    );

    test('requestPlayback() calls configureAudioSessionForPlayback', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      await coordinator.requestPlayback();

      expect(trackingService.configureForPlaybackCallCount, 1);
      expect(trackingService.configureForRecordingCallCount, 0);
    });

    test(
      'switching from playing to recording reconfigures for recording',
      () async {
        final coordinator = container.read(audioCoordinatorProvider.notifier);

        await coordinator.requestPlayback();
        await coordinator.requestRecording();

        expect(trackingService.configureForRecordingCallCount, 1);
        expect(trackingService.configureForPlaybackCallCount, 1);
      },
    );

    test(
      'device change while recording reconfigures audio session for recording',
      () async {
        // Initialize background service provider (subscribes to device changes)
        container.read(backgroundServiceProvider);
        final coordinator = container.read(audioCoordinatorProvider.notifier);
        await coordinator.requestRecording();
        final countBefore = trackingService.configureForRecordingCallCount;

        trackingService.simulateDeviceChange();
        await Future<void>.delayed(Duration.zero);

        expect(trackingService.configureForRecordingCallCount, countBefore + 1);
      },
    );

    test(
      'device change while playing reconfigures audio session for playback',
      () async {
        container.read(backgroundServiceProvider);
        final coordinator = container.read(audioCoordinatorProvider.notifier);
        await coordinator.requestPlayback();
        final countBefore = trackingService.configureForPlaybackCallCount;

        trackingService.simulateDeviceChange();
        await Future<void>.delayed(Duration.zero);

        expect(trackingService.configureForPlaybackCallCount, countBefore + 1);
      },
    );

    test('device change while idle does not reconfigure', () async {
      container.read(backgroundServiceProvider);
      // Stay idle, do not request recording or playback

      trackingService.simulateDeviceChange();
      await Future<void>.delayed(Duration.zero);

      expect(trackingService.configureForRecordingCallCount, 0);
      expect(trackingService.configureForPlaybackCallCount, 0);
    });
  });
}

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/providers/audio_coordinator_provider.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/providers/playback_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/voice_service_provider.dart';
import 'package:relagent/voice/model_download_service.dart';
import 'package:relagent/voice/voice_service.dart'
    hide AudioInterruptionType, AudioInterruptionEvent;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_test_fixtures.mocks.dart';

/// A [ModelDownloadService] stub that returns empty state immediately,
/// preventing async filesystem I/O from outliving tests.
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

/// Test fixtures and mocks for audio subsystem testing.
///
/// Usage:
/// ```dart
/// test('My test', () async {
///   final fixture = AudioTestFixture();
///   await fixture.setUp();
///
///   // Use fixture.container to access providers with mocked dependencies
///   final state = fixture.container.read(audioCoordinatorProvider);
///
///   fixture.tearDown();
/// });
/// ```

// Generate mocks using build_runner:
// dart run build_runner build
@GenerateNiceMocks([MockSpec<AudioSession>(), MockSpec<AudioPlayer>()])
class AudioTestFixture {
  late ProviderContainer container;
  late MockAudioSession mockAudioSession;
  late MockAudioPlayer mockAudioPlayer;

  /// Set up test environment with mocked dependencies.
  ///
  /// Pass [voiceService] to override the platform voice service (e.g. with a
  /// fake TTS implementation) — tests that don't need TTS can omit it.
  Future<void> setUp({VoiceService? voiceService}) async {
    // Initialize Flutter test bindings
    TestWidgetsFlutterBinding.ensureInitialized();

    // Set up SharedPreferences mocks with silent voice mode to prevent auto-resume
    SharedPreferences.setMockInitialValues({
      'user_settings':
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour"}',
    });
    final sharedPreferences = await SharedPreferences.getInstance();

    mockAudioSession = MockAudioSession();
    mockAudioPlayer = MockAudioPlayer();

    // Configure default mock behaviors
    _configureMockAudioSession();
    _configureMockAudioPlayer();

    // Create container with overrides for mocked dependencies
    container = ProviderContainer(
      overrides: [
        // Override SharedPreferences provider
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        // Override AudioPlayer provider with mock
        audioPlayerProvider.overrideWithValue(mockAudioPlayer),
        // Stub model download service so no async filesystem I/O outlives tests
        modelDownloadServiceProvider.overrideWithValue(
          _NoOpModelDownloadService(),
        ),
        if (voiceService != null)
          voiceServiceProvider.overrideWithValue(voiceService),
      ],
    );
  }

  /// Configure mock audio session with sensible defaults
  void _configureMockAudioSession() {
    // Active state management
    when(mockAudioSession.setActive(any)).thenAnswer((_) async => true);

    // Configuration
    when(mockAudioSession.configure(any)).thenAnswer((_) async {});

    // Device streams - return empty by default
    when(
      mockAudioSession.devicesStream,
    ).thenAnswer((_) => Stream.value(<AudioDevice>{}));

    // Interruption events - return empty by default
    when(mockAudioSession.interruptionEventStream).thenAnswer(
      (_) => Stream.value(
        AudioInterruptionEvent(false, AudioInterruptionType.unknown),
      ),
    );

    // Device changes - return empty by default
    when(mockAudioSession.devicesChangedEventStream).thenAnswer(
      (_) => Stream.value(
        AudioDevicesChangedEvent(
          devicesAdded: <AudioDevice>{},
          devicesRemoved: <AudioDevice>{},
        ),
      ),
    );
  }

  /// Configure mock audio player with sensible defaults
  void _configureMockAudioPlayer() {
    // Player state stream - use a StreamController for dynamic state changes
    final playerStateController = StreamController<PlayerState>.broadcast();

    // Start with idle state
    playerStateController.add(PlayerState(false, ProcessingState.idle));

    when(
      mockAudioPlayer.playerStateStream,
    ).thenAnswer((_) => playerStateController.stream);

    // Playback control
    Timer? autoCompleteTimer;
    when(mockAudioPlayer.play()).thenAnswer((_) async {
      // A new play() session supersedes any earlier pending auto-complete.
      autoCompleteTimer?.cancel();
      // Simulate playback starting
      playerStateController.add(PlayerState(true, ProcessingState.ready));
      // Complete playback after a short delay to allow tests to observe state
      autoCompleteTimer = Timer(const Duration(milliseconds: 50), () {
        if (!playerStateController.isClosed) {
          playerStateController.add(
            PlayerState(false, ProcessingState.completed),
          );
        }
      });
    });

    when(mockAudioPlayer.pause()).thenAnswer((_) async {
      playerStateController.add(PlayerState(false, ProcessingState.ready));
    });

    when(mockAudioPlayer.stop()).thenAnswer((_) async {
      // Real just_audio halts playback on stop() — no further completion
      // event should arrive for whatever was playing before this call.
      autoCompleteTimer?.cancel();
      playerStateController.add(PlayerState(false, ProcessingState.idle));
    });

    // Audio source
    when(mockAudioPlayer.setAudioSource(any)).thenAnswer((_) async => null);

    // Disposal
    when(mockAudioPlayer.dispose()).thenAnswer((_) async {
      autoCompleteTimer?.cancel();
      playerStateController.close();
    });
  }

  /// Simulate Bluetooth device connection
  void simulateBluetoothConnect(String deviceName) {
    final bluetoothDevice = MockAudioDevice(
      id: 'bt-1',
      name: deviceName,
      type: AudioDeviceType.bluetoothA2dp,
    );

    when(
      mockAudioSession.devicesStream,
    ).thenAnswer((_) => Stream.value({bluetoothDevice}));

    // Trigger device change event
    when(mockAudioSession.devicesChangedEventStream).thenAnswer(
      (_) => Stream.value(
        AudioDevicesChangedEvent(
          devicesAdded: {bluetoothDevice},
          devicesRemoved: <AudioDevice>{},
        ),
      ),
    );
  }

  /// Simulate Bluetooth device disconnection
  void simulateBluetoothDisconnect(String deviceName) {
    final bluetoothDevice = MockAudioDevice(
      id: 'bt-1',
      name: deviceName,
      type: AudioDeviceType.bluetoothA2dp,
    );

    when(
      mockAudioSession.devicesStream,
    ).thenAnswer((_) => Stream.value(<AudioDevice>{}));

    when(mockAudioSession.devicesChangedEventStream).thenAnswer(
      (_) => Stream.value(
        AudioDevicesChangedEvent(
          devicesAdded: <AudioDevice>{},
          devicesRemoved: {bluetoothDevice},
        ),
      ),
    );
  }

  /// Simulate phone call (temporary audio focus loss)
  void simulatePhoneCall({required bool begin}) {
    when(mockAudioSession.interruptionEventStream).thenAnswer(
      (_) => Stream.value(
        AudioInterruptionEvent(begin, AudioInterruptionType.pause),
      ),
    );
  }

  /// Simulate playback completion
  void simulatePlaybackComplete() {
    when(mockAudioPlayer.playerStateStream).thenAnswer(
      (_) => Stream.value(PlayerState(false, ProcessingState.completed)),
    );
  }

  /// Clean up test resources
  void tearDown() {
    container.dispose();
  }
}

/// Mock audio device for testing
class MockAudioDevice implements AudioDevice {
  @override
  final String id;

  @override
  final String name;

  @override
  final AudioDeviceType type;

  MockAudioDevice({required this.id, required this.name, required this.type});

  @override
  bool get isInput =>
      type == AudioDeviceType.builtInMic ||
      type == AudioDeviceType.bluetoothSco;

  @override
  bool get isOutput =>
      type == AudioDeviceType.builtInSpeaker ||
      type == AudioDeviceType.builtInEarpiece ||
      type == AudioDeviceType.bluetoothA2dp ||
      type == AudioDeviceType.bluetoothSco;
}

/// Common test scenarios as reusable fixtures
class AudioTestScenarios {
  /// Scenario: Recording → Playback → Recording (happy path)
  static Future<void> recordingPlaybackRecordingFlow(
    ProviderContainer container,
  ) async {
    final coordinator = container.read(audioCoordinatorProvider.notifier);

    // Start recording
    final recordingGranted = await coordinator.requestRecording();
    assert(recordingGranted, 'Recording should be granted when idle');
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.recording,
      'Should be in recording mode',
    );

    // Transition to playback
    final playbackGranted = await coordinator.requestPlayback();
    assert(playbackGranted, 'Playback should be granted');
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.playing,
      'Should be in playing mode',
    );

    // Release playback
    await coordinator.releasePlayback();
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.idle,
      'Should return to idle',
    );
  }

  /// Scenario: Denied playback doesn't break state
  static Future<void> deniedPlaybackScenario(
    ProviderContainer container,
  ) async {
    final coordinator = container.read(audioCoordinatorProvider.notifier);
    final playback = container.read(playbackProvider.notifier);

    // Acquire playback lock via coordinator
    await coordinator.requestPlayback();

    // Try to enqueue item - should be denied
    final item = PlaybackItem(id: 'test', content: Future.value(Uint8List(0)));
    await playback.enqueue(item);

    // Wait for processing
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Lock should still be held
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.playing,
      'Lock should still be held after denied playback',
    );

    // Item should be completed
    assert(item.onFinished.isCompleted, 'Denied item should be completed');
  }

  /// Scenario: Phone call interruption
  static Future<void> phoneCallInterruption(
    ProviderContainer container,
    AudioTestFixture fixture,
  ) async {
    final coordinator = container.read(audioCoordinatorProvider.notifier);

    // Start recording
    await coordinator.requestRecording();

    // Simulate phone call
    fixture.simulatePhoneCall(begin: true);
    // Coordinator should handle the interruption event
    coordinator.handleAudioFocusChange('temporary_loss');

    // Should be waiting
    assert(
      container.read(audioCoordinatorProvider).isWaiting,
      'Should be waiting during phone call',
    );

    // Phone call ends
    fixture.simulatePhoneCall(begin: false);
    await coordinator.handleAudioFocusChange('gain');

    // Should restore recording
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.recording,
      'Should restore recording after call',
    );
  }

  /// Scenario: Pause/resume preserves lock
  static Future<void> pauseResumeFlow(ProviderContainer container) async {
    final playback = container.read(playbackProvider.notifier);

    // Enqueue and play item
    final item = PlaybackItem(
      id: 'test',
      content: Future.value(Uint8List.fromList([1, 2, 3])),
    );
    await playback.enqueue(item);
    // Wait briefly for playback to start, but pause before auto-completion (50ms)
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Should be playing with lock held
    assert(
      container.read(playbackProvider).status == PlaybackStatus.playing,
      'Should be playing',
    );
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.playing,
      'Lock should be held',
    );

    // Pause before auto-completion happens
    await playback.pause();

    // Should be paused but lock still held
    assert(
      container.read(playbackProvider).status == PlaybackStatus.paused,
      'Should be paused',
    );
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.playing,
      'Lock should STILL be held during pause',
    );

    // Resume
    await playback.resume();

    // Should be playing with lock still held
    assert(
      container.read(playbackProvider).status == PlaybackStatus.playing,
      'Should be playing again',
    );
    assert(
      container.read(audioCoordinatorProvider).mode == AudioMode.playing,
      'Lock should still be held',
    );
  }
}

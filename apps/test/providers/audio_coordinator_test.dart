import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/audio_coordinator_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for AudioCoordinator state machine invariants.
///
/// CRITICAL INVARIANTS:
/// 1. Only one mode can be active at a time (mutual exclusion)
/// 2. Transitions must follow valid paths: idle ↔ recording, idle ↔ playing
/// 3. Recording and playing cannot transition directly to each other
/// 4. Only the lock holder can release the lock
void main() {
  late ProviderContainer container;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Use silent voice mode to prevent auto-resume recording
    SharedPreferences.setMockInitialValues({
      'user_settings': '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour"}',
    });
    final sharedPreferences = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('AudioCoordinator State Machine', () {
    test('Initial state is idle', () {
      final state = container.read(audioCoordinatorProvider);
      expect(state.mode, AudioMode.idle);
      expect(state.canRecord, true);
      expect(state.canPlay, true);
    });

    test('Can transition from idle to recording', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);
      final granted = await coordinator.requestRecording();

      expect(granted, true);
      expect(container.read(audioCoordinatorProvider).mode,
          AudioMode.recording);
    });

    test('Can transition from idle to playing', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);
      final granted = await coordinator.requestPlayback();

      expect(granted, true);
      expect(
          container.read(audioCoordinatorProvider).mode, AudioMode.playing);
    });

    test('Cannot record while playing (mutual exclusion)', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      // Start playing
      await coordinator.requestPlayback();
      expect(container.read(audioCoordinatorProvider).mode, AudioMode.playing);

      // Try to record - should transition through idle first
      final granted = await coordinator.requestRecording();

      // requestRecording() stops playback first, then grants recording
      expect(granted, true);
      expect(container.read(audioCoordinatorProvider).mode,
          AudioMode.recording);
    });

    test('Cannot play while recording (mutual exclusion)', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      // Start recording
      await coordinator.requestRecording();
      expect(container.read(audioCoordinatorProvider).mode,
          AudioMode.recording);

      // Try to play - should transition through idle first
      final granted = await coordinator.requestPlayback();

      // requestPlayback() stops recording first, then grants playback
      expect(granted, true);
      expect(
          container.read(audioCoordinatorProvider).mode, AudioMode.playing);
    });

    test('Recording lock can be released', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      await coordinator.requestRecording();
      expect(container.read(audioCoordinatorProvider).mode,
          AudioMode.recording);

      await coordinator.releaseRecording();
      expect(container.read(audioCoordinatorProvider).mode, AudioMode.idle);
    });

    test('Playback lock can be released', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      await coordinator.requestPlayback();
      expect(
          container.read(audioCoordinatorProvider).mode, AudioMode.playing);

      await coordinator.releasePlayback();
      expect(container.read(audioCoordinatorProvider).mode, AudioMode.idle);
    });

    test('releaseRecording is idempotent when not recording', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      // Release when idle - should not crash
      await coordinator.releaseRecording();
      expect(container.read(audioCoordinatorProvider).mode, AudioMode.idle);

      // Release when playing
      await coordinator.requestPlayback();
      await coordinator.releaseRecording();
      expect(
          container.read(audioCoordinatorProvider).mode, AudioMode.playing);
    });

    test('releasePlayback is idempotent when not playing', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      // Release when idle - should not crash
      await coordinator.releasePlayback();
      expect(container.read(audioCoordinatorProvider).mode, AudioMode.idle);

      // Release when recording
      await coordinator.requestRecording();
      await coordinator.releasePlayback();
      expect(container.read(audioCoordinatorProvider).mode,
          AudioMode.recording);
    });

    test('State flags match mode correctly', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      // Idle
      var state = container.read(audioCoordinatorProvider);
      expect(state.isIdle, true);
      expect(state.isRecording, false);
      expect(state.isPlaying, false);

      // Recording
      await coordinator.requestRecording();
      state = container.read(audioCoordinatorProvider);
      expect(state.isIdle, false);
      expect(state.isRecording, true);
      expect(state.isPlaying, false);

      // Playing
      await coordinator.requestPlayback();
      state = container.read(audioCoordinatorProvider);
      expect(state.isIdle, false);
      expect(state.isRecording, false);
      expect(state.isPlaying, true);
    });
  });

  group('Audio Focus Integration', () {
    test('Temporary loss transitions to idle', () {
      final coordinator = container.read(audioCoordinatorProvider.notifier);
      coordinator.handleAudioFocusChange('temporary_loss');

      expect(container.read(audioCoordinatorProvider).mode, AudioMode.idle);
      expect(
          container.read(audioCoordinatorProvider).isWaiting, true);
    });

    test('Gain after temporary loss can restore state', () async {
      final coordinator = container.read(audioCoordinatorProvider.notifier);

      // Start recording
      await coordinator.requestRecording();

      // Simulate temporary loss (phone call)
      coordinator.handleAudioFocusChange('temporary_loss');
      expect(container.read(audioCoordinatorProvider).mode, AudioMode.idle);

      // Regain focus
      coordinator.handleAudioFocusChange('gain');

      // Should restore recording (implementation-dependent)
      // Note: This tests the current auto-resume behavior
      expect(container.read(audioCoordinatorProvider).mode,
          AudioMode.recording);
    });
  });
}

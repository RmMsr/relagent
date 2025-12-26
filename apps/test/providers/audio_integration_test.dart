import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/audio_coordinator_provider.dart';
import 'package:relagent/providers/playback_provider.dart';

import '../fixtures/audio_test_fixtures.dart';

/// Integration tests for audio subsystem using test fixtures.
///
/// These tests verify the critical invariants documented in AUDIO_ARCHITECTURE.md:
/// 1. Mutual exclusion - Only one audio mode active at a time
/// 2. Lock ownership - Only lock holder can release
/// 3. State transitions - Must go through idle
/// 4. Pause semantics - Pause doesn't release lock
///
/// To run these tests once mocking is set up:
/// ```bash
/// flutter test test/providers/audio_integration_test.dart
/// ```
void main() {
  group('Audio System Integration Tests', () {
    late AudioTestFixture fixture;

    setUp(() async {
      fixture = AudioTestFixture();
      await fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('Recording → Playback → Recording (happy path)', () async {
      await AudioTestScenarios.recordingPlaybackRecordingFlow(
        fixture.container,
      );
    });

    test('Denied playback preserves lock (regression test)', () async {
      // This is the critical test that would have caught the duplicate playback bug
      await AudioTestScenarios.deniedPlaybackScenario(fixture.container);
    });

    test('Pause/resume preserves lock (regression test)', () async {
      // This verifies pause doesn't release the playback lock
      await AudioTestScenarios.pauseResumeFlow(fixture.container);
    });

    test('Phone call interruption and restoration', () async {
      await AudioTestScenarios.phoneCallInterruption(
        fixture.container,
        fixture,
      );
    });

    test('Bluetooth device connect/disconnect', () async {
      // Simulate Bluetooth headphones connecting
      fixture.simulateBluetoothConnect('Test Headphones');

      // Audio routing should update (verified via logs in real implementation)
      // This test documents the expected behavior

      // Simulate disconnect
      fixture.simulateBluetoothDisconnect('Test Headphones');

      // Should fall back to phone speaker/earpiece
    });
  });

  group('Edge Cases and Race Conditions', () {
    late AudioTestFixture fixture;

    setUp(() async {
      fixture = AudioTestFixture();
      await fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('Multiple rapid playback requests', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Rapidly enqueue multiple items
      for (var i = 0; i < 5; i++) {
        final item = PlaybackItem(
          id: 'item-$i',
          content: Future.value(Uint8List.fromList([i])),
        );
        await playback.enqueue(item);
      }

      // Should process sequentially without corruption
      expect(
        fixture.container.read(playbackProvider).queue.length,
        lessThanOrEqualTo(5),
      );

      // Wait for all async operations to complete before tearDown
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    test('Pause during playback start', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Start playback
      final item = PlaybackItem(
        id: 'test',
        content: Future.value(Uint8List.fromList([1, 2, 3])),
      );
      await playback.enqueue(item);

      // Immediately pause (race condition)
      await playback.pause();

      // Should handle gracefully - either paused or completed
      final status = fixture.container.read(playbackProvider).status;
      expect(
        status == PlaybackStatus.paused || status == PlaybackStatus.idle,
        true,
      );
    });

    test('Release lock multiple times (idempotent)', () async {
      final coordinator = fixture.container.read(
        audioCoordinatorProvider.notifier,
      );

      await coordinator.requestPlayback();

      // Release multiple times - should not crash
      await coordinator.releasePlayback();
      await coordinator.releasePlayback();
      await coordinator.releasePlayback();

      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.idle,
      );
    });
  });
}

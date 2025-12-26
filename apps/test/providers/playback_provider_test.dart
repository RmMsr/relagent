import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/audio_coordinator_provider.dart';
import 'package:relagent/providers/playback_provider.dart';

import '../fixtures/audio_test_fixtures.dart';

/// Tests for PlaybackProvider lock safety invariants.
///
/// CRITICAL INVARIANTS:
/// 1. Only the item that acquired the playback lock can release it
/// 2. Items denied playback must not release the global lock
/// 3. Pause/resume preserves the lock
/// 4. Queue processing maintains lock ownership
void main() {
  late AudioTestFixture fixture;

  setUp(() async {
    fixture = AudioTestFixture();
    await fixture.setUp();
  });

  tearDown(() {
    fixture.tearDown();
  });

  group('PlaybackProvider Lock Safety', () {
    test('Denied playback does not release the lock', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final coordinator = fixture.container.read(audioCoordinatorProvider.notifier);

      // Manually acquire playback lock (simulating another source)
      await coordinator.requestPlayback();
      expect(
          fixture.container.read(audioCoordinatorProvider).mode, AudioMode.playing);

      // Try to enqueue an item - should be denied and removed
      final item = PlaybackItem(
        id: 'test-denied',
        content: Future.value(Uint8List(0)),
      );
      await playback.enqueue(item);

      // Wait for processing
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Lock should still be held (mode still playing)
      expect(
          fixture.container.read(audioCoordinatorProvider).mode, AudioMode.playing);

      // Item should be completed (not stuck in queue)
      expect(item.onFinished.isCompleted, true);
    });

    test('Successful playback can release the lock', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Create a valid item
      final item = PlaybackItem(
        id: 'test-success',
        content: Future.value(Uint8List.fromList([1, 2, 3])),
      );

      // Enqueue and let it acquire the lock
      await playback.enqueue(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Should have acquired lock
      expect(
          fixture.container.read(audioCoordinatorProvider).mode, AudioMode.playing);

      // Stop playback
      await playback.stop();

      // Lock should be released
      expect(fixture.container.read(audioCoordinatorProvider).mode, AudioMode.idle);
    });

    test('Pause preserves the lock', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Create and enqueue item
      final item = PlaybackItem(
        id: 'test-pause',
        content: Future.value(Uint8List.fromList([1, 2, 3])),
      );
      await playback.enqueue(item);
      // Wait briefly for playback to start, but pause before auto-completion (50ms)
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Should be playing
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.playing);
      expect(
          fixture.container.read(audioCoordinatorProvider).mode, AudioMode.playing);

      // Pause before auto-completion happens
      await playback.pause();

      // Should be paused but lock still held
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.paused);
      expect(
          fixture.container.read(audioCoordinatorProvider).mode, AudioMode.playing);
    });

    test('Resume from pause works correctly', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Create and enqueue item
      final item = PlaybackItem(
        id: 'test-resume',
        content: Future.value(Uint8List.fromList([1, 2, 3])),
      );
      await playback.enqueue(item);
      // Wait briefly for playback to start, but pause before auto-completion
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Pause before auto-completion
      await playback.pause();
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.paused);

      // Resume
      await playback.resume();
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.playing);
      expect(
          fixture.container.read(audioCoordinatorProvider).mode, AudioMode.playing);
    });

    test('Queue with multiple items processes correctly', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Enqueue multiple items
      final items = [
        PlaybackItem(
          id: 'item-1',
          content: Future.value(Uint8List.fromList([1])),
        ),
        PlaybackItem(
          id: 'item-2',
          content: Future.value(Uint8List.fromList([2])),
        ),
      ];

      // Enqueue first item and let it start processing
      await playback.enqueue(items[0]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Enqueue second item
      await playback.enqueue(items[1]);

      // Stop should complete all items immediately
      await playback.stop();

      // Wait for all items to finish
      await Future.wait(items.map((item) => item.onFinished.future));

      // All items should be completed
      for (final item in items) {
        expect(item.onFinished.isCompleted, true);
      }

      // Give time for all async operations including lock release to complete
      // The mock player's completion events may still be pending
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Queue should be empty
      expect(fixture.container.read(playbackProvider).queue.isEmpty, true);
      expect(fixture.container.read(audioCoordinatorProvider).mode, AudioMode.idle);
    });
  });

  group('PlaybackProvider State Machine', () {
    test('Initial state is idle', () {
      final state = fixture.container.read(playbackProvider);
      expect(state.status, PlaybackStatus.idle);
      expect(state.currentItem, null);
      expect(state.queue.isEmpty, true);
    });

    test('Stop is idempotent', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Stop when idle
      await playback.stop();
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.idle);

      // Create and play item
      final item = PlaybackItem(
        id: 'test',
        content: Future.value(Uint8List.fromList([1])),
      );
      await playback.enqueue(item);
      // Wait briefly for playback to start
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Stop multiple times - should be idempotent
      await playback.stop();
      await playback.stop();
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.idle);
    });

    test('Pause/resume are idempotent', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Pause when idle - should not crash
      await playback.pause();
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.idle);

      // Resume when idle - should not crash
      await playback.resume();
      expect(fixture.container.read(playbackProvider).status, PlaybackStatus.idle);
    });
  });
}

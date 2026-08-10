import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
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
      final coordinator = fixture.container.read(
        audioCoordinatorProvider.notifier,
      );

      // Manually acquire playback lock (simulating another source)
      await coordinator.requestPlayback();
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );

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
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );

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
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );

      // Stop playback
      await playback.stop();

      // Lock should be released
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.idle,
      );
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
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.playing,
      );
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );

      // Pause before auto-completion happens
      await playback.pause();

      // Should be paused but lock still held
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.paused,
      );
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );
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
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.paused,
      );

      // Resume
      await playback.resume();
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.playing,
      );
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );
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
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.idle,
      );
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
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );

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
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );
    });

    test('Pause/resume are idempotent', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Pause when idle - should not crash
      await playback.pause();
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );

      // Resume when idle - should not crash
      await playback.resume();
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );
    });
  });

  group('PlaybackProvider Chunk Navigation Primitives', () {
    test('position reads through to the underlying player', () {
      final playback = fixture.container.read(playbackProvider.notifier);
      when(
        fixture.mockAudioPlayer.position,
      ).thenReturn(const Duration(seconds: 5));

      expect(playback.currentPosition(), const Duration(seconds: 5));
    });

    test('seekToStart seeks to zero when an item is current', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final item = PlaybackItem(
        id: 'seek-test',
        content: Future.value(Uint8List.fromList([1])),
      );
      await playback.enqueue(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await playback.seekToStart();

      verify(fixture.mockAudioPlayer.seek(Duration.zero)).called(1);
    });

    test('seekToStart is a no-op when nothing is playing', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      await playback.seekToStart();

      verifyNever(fixture.mockAudioPlayer.seek(any));
    });

    test('skipCurrent advances to the next queued item', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final items = [
        PlaybackItem(
          id: 'skip-1',
          content: Future.value(Uint8List.fromList([1])),
        ),
        PlaybackItem(
          id: 'skip-2',
          content: Future.value(Uint8List.fromList([2])),
        ),
      ];
      await playback.enqueue(items[0]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await playback.enqueue(items[1]);

      await playback.skipCurrent();
      // Short delay: observe the mid-flight state before item-1's mock
      // playback timer (scheduled ~50ms after its own play() call) fires.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(items[0].onFinished.isCompleted, true);
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'skip-2',
      );
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.playing,
      );
    });

    test('skipCurrent with nothing queued afterward goes idle', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final item = PlaybackItem(
        id: 'skip-only',
        content: Future.value(Uint8List.fromList([1])),
      );
      await playback.enqueue(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await playback.skipCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(item.onFinished.isCompleted, true);
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );
      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.idle,
      );
    });

    test('skipCurrent is a no-op when idle', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      await playback.skipCurrent();

      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );
      verifyNever(fixture.mockAudioPlayer.stop());
    });

    test('removeQueued drops matching not-yet-playing items', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final item0 = PlaybackItem(
        id: 'rq-0',
        content: Future.value(Uint8List.fromList([0])),
      );
      final item1 = PlaybackItem(
        id: 'rq-1',
        content: Future.value(Uint8List.fromList([1])),
      );
      final item2 = PlaybackItem(
        id: 'rq-2',
        content: Future.value(Uint8List.fromList([2])),
      );
      await playback.enqueue(item0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await playback.enqueue(item1);
      await playback.enqueue(item2);

      playback.removeQueued((item) => item.id == 'rq-1');

      expect(item1.onFinished.isCompleted, true);
      expect(
        fixture.container
            .read(playbackProvider)
            .queue
            .map((i) => i.id)
            .toList(),
        ['rq-0', 'rq-2'],
      );
      expect(fixture.container.read(playbackProvider).currentItem?.id, 'rq-0');
    });

    test('removeQueued never touches the current item', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final item0 = PlaybackItem(
        id: 'rq-current',
        content: Future.value(Uint8List.fromList([0])),
      );
      await playback.enqueue(item0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      playback.removeQueued((item) => true);

      expect(item0.onFinished.isCompleted, false);
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'rq-current',
      );
    });
  });

  group('PlaybackProvider Sequential Chunk Continuity', () {
    test('holds the coordinator lock continuously across back-to-back '
        'same-session items instead of releasing and reacquiring it', () async {
      final playback = fixture.container.read(playbackProvider.notifier);

      // Every re-entry into AudioMode.playing reconfigures the native
      // audio session (Bluetooth routing/focus), which is audible as a
      // gap or crackle. Chunked TTS enqueues its next chunk while the
      // current one is still playing (one-chunk-ahead prefetch), so a
      // continuous multi-chunk message must only cross playing->idle->
      // playing once for the whole run, not once per chunk boundary.
      var playingEntries = 0;
      fixture.container.listen(audioCoordinatorProvider, (prev, next) {
        if (prev?.mode != AudioMode.playing && next.mode == AudioMode.playing) {
          playingEntries++;
        }
      });

      final items = [
        PlaybackItem(
          id: 'chunk-1',
          content: Future.value(Uint8List.fromList([1])),
        ),
        PlaybackItem(
          id: 'chunk-2',
          content: Future.value(Uint8List.fromList([2])),
        ),
      ];

      await playback.enqueue(items[0]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Prefetch chunk-2 while chunk-1 is still playing, same as
      // TtsNotifier's one-chunk-ahead prefetch.
      await playback.enqueue(items[1]);

      // Let both chunks run to natural completion (mock auto-completes
      // playback 50ms after each `play()` call).
      await Future.wait([
        items[0].onFinished.future,
        items[1].onFinished.future,
      ]).timeout(const Duration(seconds: 2));

      expect(playingEntries, 1);
    });
  });

  group('PlaybackProvider Interruption Recovery', () {
    test('resyncs its own state when the coordinator forcibly revokes the '
        'lock mid-playback (e.g. a phone-call interruption)', () async {
      final playback = fixture.container.read(playbackProvider.notifier);
      final coordinator = fixture.container.read(
        audioCoordinatorProvider.notifier,
      );

      final item = PlaybackItem(
        id: 'interrupted',
        content: Future.value(Uint8List.fromList([1])),
      );
      await playback.enqueue(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        fixture.container.read(audioCoordinatorProvider).mode,
        AudioMode.playing,
      );

      // AudioCoordinator forces mode back to idle directly on a real audio
      // focus interruption - PlaybackService never asked for this.
      coordinator.handleAudioFocusChange('temporary_loss');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // PlaybackService must notice the lock was taken away and stop
      // believing it's still playing, instead of hanging forever.
      expect(item.onFinished.isCompleted, true);
      expect(
        fixture.container.read(playbackProvider).status,
        PlaybackStatus.idle,
      );
    });

    test(
      'does not leave an orphaned playback lock after an interruption ends',
      () async {
        final playback = fixture.container.read(playbackProvider.notifier);
        final coordinator = fixture.container.read(
          audioCoordinatorProvider.notifier,
        );

        final item1 = PlaybackItem(
          id: 'interrupted',
          content: Future.value(Uint8List.fromList([1])),
        );
        await playback.enqueue(item1);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        coordinator.handleAudioFocusChange('temporary_loss');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Interruption ends.
        await coordinator.handleAudioFocusChange('gain');

        // Nobody owns the lock anymore, so it must not be re-granted to a
        // dangling `playing` mode that will never be released.
        expect(
          fixture.container.read(audioCoordinatorProvider).mode,
          AudioMode.idle,
        );

        // New playback must actually work afterward, not be denied forever.
        final item2 = PlaybackItem(
          id: 'after-recovery',
          content: Future.value(Uint8List.fromList([2])),
        );
        await playback.enqueue(item2);
        await item2.onFinished.future.timeout(const Duration(seconds: 2));

        expect(
          fixture.container.read(audioCoordinatorProvider).mode,
          AudioMode.idle,
        );
      },
    );

    test(
      'forceStop halts active playback even when voiceMode was already '
      'silent - the resting default outside continuous voice, so an '
      'edge-triggered voiceMode change alone never fires',
      () async {
        final playback = fixture.container.read(playbackProvider.notifier);
        final coordinator = fixture.container.read(
          audioCoordinatorProvider.notifier,
        );

        final item = PlaybackItem(
          id: 'now-playing',
          content: Future.value(Uint8List.fromList([1])),
        );
        await playback.enqueue(item);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          fixture.container.read(playbackProvider).status,
          PlaybackStatus.playing,
        );

        coordinator.forceStop();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(item.onFinished.isCompleted, true);
        expect(
          fixture.container.read(playbackProvider).status,
          PlaybackStatus.idle,
        );
        expect(
          fixture.container.read(audioCoordinatorProvider).mode,
          AudioMode.idle,
        );
      },
    );
  });
}

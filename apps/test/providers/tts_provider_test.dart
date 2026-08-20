import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:relagent/providers/audio_coordinator_provider.dart';
import 'package:relagent/providers/playback_provider.dart';
import 'package:relagent/providers/tts_provider.dart';
import 'package:relagent/tts/text_chunker.dart';
import 'package:relagent/voice/voice_service_stub.dart';

import '../fixtures/audio_test_fixtures.dart';

/// Fake TTS backend: returns short canned audio instantly instead of
/// touching sherpa-onnx/isolates, so [TtsNotifier] can be exercised against
/// real chunking/prefetch/navigation logic in a unit test.
class _FakeTtsVoiceService extends NoOpVoiceService {
  final Set<String> failFor;
  _FakeTtsVoiceService({this.failFor = const {}});

  @override
  bool get isTtsAvailable => true;

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    if (failFor.contains(messageId)) return null;
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// Polls until `currentItem?.id == expectedId` or gives up after ~2s —
/// natural chunk-to-chunk cascades (mock auto-complete + lock
/// release/reacquire) don't have a fixed enough duration to land on with a
/// single hardcoded `Future.delayed`.
Future<void> _pollForCurrentItemId(
  ProviderContainer container,
  String expectedId,
) async {
  for (var i = 0; i < 200; i++) {
    if (container.read(playbackProvider).currentItem?.id == expectedId) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _threeParagraphMessage = 'Para one.\n\nPara two.\n\nPara three.';
const _shortListThenParagraph = '- one\n- two\n- three\n\nAfter list.';

final _longListItemText = List.filled(
  10,
  'This is a moderately long sentence for testing purposes.',
).join(' ');
final _listWithOneLongItem = '- short one\n- $_longListItemText\n- short three';

void main() {
  group('pauseDurationFor', () {
    test('scales inversely with speed so pauses stay proportionate', () {
      expect(
        pauseDurationFor(ChunkPause.paragraph, 1.0),
        const Duration(milliseconds: 250),
      );
      expect(
        pauseDurationFor(ChunkPause.paragraph, 2.0),
        const Duration(milliseconds: 125),
      );
      expect(
        pauseDurationFor(ChunkPause.heading, 0.5),
        const Duration(milliseconds: 1400),
      );
      expect(
        pauseDurationFor(ChunkPause.clause, 2.0),
        const Duration(milliseconds: 75),
      );
    });

    test('none stays zero regardless of speed', () {
      expect(pauseDurationFor(ChunkPause.none, 2.0), Duration.zero);
      expect(pauseDurationFor(ChunkPause.none, 0.5), Duration.zero);
    });
  });

  late AudioTestFixture fixture;

  setUp(() async {
    fixture = AudioTestFixture();
    await fixture.setUp(voiceService: _FakeTtsVoiceService());
  });

  tearDown(() {
    fixture.tearDown();
  });

  group('TtsNotifier chunked playback', () {
    test('a multi-paragraph message is split into chunks', () async {
      final tts = fixture.container.read(ttsProvider.notifier);

      await tts.enqueue(_threeParagraphMessage, 'msg-chunks');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final messageState = fixture.container
          .read(ttsProvider)
          .getMessageState('msg-chunks');
      expect(messageState.totalChunks, 3);
    });

    test(
      'prefetch enqueues the next chunk once the first starts playing',
      () async {
        final tts = fixture.container.read(ttsProvider.notifier);

        await tts.enqueue(_threeParagraphMessage, 'msg-prefetch');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          fixture.container.read(playbackProvider).currentItem?.id,
          'msg-prefetch#0',
        );
        expect(fixture.container.read(playbackProvider).queue.length, 2);
        expect(
          fixture.container.read(playbackProvider).queue.map((i) => i.id),
          containsAll(['msg-prefetch#0', 'msg-prefetch#1']),
        );
      },
    );

    test(
      'message status becomes completed only after the last chunk',
      () async {
        final tts = fixture.container.read(ttsProvider.notifier);

        await tts.enqueue(_threeParagraphMessage, 'msg-complete');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // First chunk is underway; the message must not be completed yet.
        expect(
          fixture.container
              .read(ttsProvider)
              .getMessageState('msg-complete')
              .status,
          isNot(MessagePlaybackStatus.completed),
        );

        // Let all three chunks cascade through (play ~50ms + lock
        // release/reacquire ~100ms per hop).
        await Future<void>.delayed(const Duration(milliseconds: 900));

        expect(
          fixture.container
              .read(ttsProvider)
              .getMessageState('msg-complete')
              .status,
          MessagePlaybackStatus.completed,
        );
      },
    );

    test('a failed final chunk still marks the message completed', () async {
      final failingFixture = AudioTestFixture();
      await failingFixture.setUp(
        voiceService: _FakeTtsVoiceService(failFor: {'msg-fail#0'}),
      );
      addTearDown(failingFixture.tearDown);

      final tts = failingFixture.container.read(ttsProvider.notifier);
      await tts.enqueue('Only paragraph.', 'msg-fail');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        failingFixture.container
            .read(ttsProvider)
            .getMessageState('msg-fail')
            .status,
        MessagePlaybackStatus.completed,
      );
    });

    test(
      'skipPreviousChunk drops the stale prefetched chunk so nothing is skipped',
      () async {
        final tts = fixture.container.read(ttsProvider.notifier);
        when(fixture.mockAudioPlayer.position).thenReturn(Duration.zero);

        await tts.enqueue(_threeParagraphMessage, 'msg-back');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          fixture.container.read(playbackProvider).currentItem?.id,
          'msg-back#0',
        );

        // Force-advance to chunk 1. The mock player auto-completes whatever
        // is playing ~50ms after it starts, so the window to observe "chunk 1
        // is current, chunk 2 prefetched" is narrow — check promptly.
        await tts.skipNextChunk('msg-back');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          fixture.container.read(playbackProvider).currentItem?.id,
          'msg-back#1',
        );
        expect(
          fixture.container.read(playbackProvider).queue.map((i) => i.id),
          containsAll(['msg-back#1', 'msg-back#2']),
        );

        await tts.skipPreviousChunk('msg-back');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Jumped back to chunk 0; the stale chunk 2 prefetch must be gone so
        // chunk 1 gets replayed instead of being skipped over.
        expect(
          fixture.container.read(playbackProvider).currentItem?.id,
          'msg-back#0',
        );
        expect(
          fixture.container.read(playbackProvider).queue.map((i) => i.id),
          isNot(contains('msg-back#2')),
        );
      },
    );

    test('skipNextChunk treats a short list as one paragraph, skipping all '
        'its items at once', () async {
      final tts = fixture.container.read(ttsProvider.notifier);
      when(fixture.mockAudioPlayer.position).thenReturn(Duration.zero);

      await tts.enqueue(_shortListThenParagraph, 'msg-list');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-list#0',
      );

      await tts.skipNextChunk('msg-list');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Jumps straight to "After list." (chunk 3), past items 1 and 2.
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-list#3',
      );
    });

    test("skipPreviousChunk from within a short list jumps to the list's "
        'first item, not the previous one', () async {
      final tts = fixture.container.read(ttsProvider.notifier);
      when(fixture.mockAudioPlayer.position).thenReturn(Duration.zero);

      await tts.enqueue(_shortListThenParagraph, 'msg-list-back');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Let natural playback cascade through item 1 to item 2 ("three") —
      // polled rather than a fixed wait, since the exact hop duration
      // (mock auto-complete + lock release/reacquire) isn't precise enough
      // to land on with a hardcoded delay.
      await _pollForCurrentItemId(fixture.container, 'msg-list-back#2');
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-list-back#2',
      );

      await tts.skipPreviousChunk('msg-list-back');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-list-back#0',
      );
    });

    test("skipPreviousChunk from just after a short list jumps to the list's "
        'first item, not just its last item', () async {
      final tts = fixture.container.read(ttsProvider.notifier);
      when(fixture.mockAudioPlayer.position).thenReturn(Duration.zero);

      await tts.enqueue(_shortListThenParagraph, 'msg-list-after');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tts.skipNextChunk('msg-list-after');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-list-after#3',
      );

      await tts.skipPreviousChunk('msg-list-after');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-list-after#0',
      );
    });

    test('a list containing one long item is not collapsed for navigation — '
        'forward still steps one raw chunk at a time', () async {
      final tts = fixture.container.read(ttsProvider.notifier);
      when(fixture.mockAudioPlayer.position).thenReturn(Duration.zero);

      await tts.enqueue(_listWithOneLongItem, 'msg-long-item');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-long-item#0',
      );

      await tts.skipNextChunk('msg-long-item');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Not collapsed: forward only advances by one raw chunk (into the
      // long item's own text), not straight past the whole list.
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-long-item#1',
      );
    });

    test('playNow clears a stale prefetched chunk left over from a different '
        'message (e.g. one still playing in another chat session)', () async {
      final tts = fixture.container.read(ttsProvider.notifier);

      await tts.enqueue(_threeParagraphMessage, 'msg-old');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tts.skipNextChunk('msg-old');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-old#1',
      );
      expect(
        fixture.container.read(playbackProvider).queue.map((i) => i.id),
        contains('msg-old#2'),
      );

      await tts.playNow('Single paragraph.', 'msg-new');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The new message's first chunk plays, and nothing from the old
      // message is still queued behind it — neither the prefetched tail
      // (msg-old#2) nor the item that was actually playing at interrupt
      // time (msg-old#1, which removeQueued() alone would leave behind as
      // queue.first since it never touches the head).
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        'msg-new#0',
      );
      expect(fixture.container.read(playbackProvider).queue.map((i) => i.id), [
        'msg-new#0',
      ]);

      // Let msg-new#0 finish (mock auto-completes ~50ms after play()) and
      // confirm playback goes idle instead of resurrecting msg-old#1.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        fixture.container.read(playbackProvider).currentItem?.id,
        isNot('msg-old#1'),
      );
    });

    test('playNow resets a message it interrupts mid-playback, so it stops '
        'reporting playback focus (and its UI reverts to a single play '
        'button instead of the back/pause/forward row)', () async {
      final tts = fixture.container.read(ttsProvider.notifier);

      await tts.enqueue(_threeParagraphMessage, 'msg-old');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tts.skipNextChunk('msg-old');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Mid-message: chunk 1 of 3, not the last chunk — the natural
      // completion path (which only fires when the *last* chunk is lost)
      // would never reset msg-old on its own.
      expect(
        fixture.container.read(ttsProvider).getMessageState('msg-old').status,
        MessagePlaybackStatus.playing,
      );

      await tts.playNow('Single paragraph.', 'msg-new');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final oldState = fixture.container
          .read(ttsProvider)
          .getMessageState('msg-old');
      expect(oldState.hasPlaybackFocus, isFalse);
      expect(oldState.status, MessagePlaybackStatus.idle);
    });

    test(
      'an external force-stop (e.g. the notification Stop button) resets '
      'the message it interrupts mid-playback, so its UI reverts to a '
      'single play button instead of staying stuck on back/pause/forward',
      () async {
        final tts = fixture.container.read(ttsProvider.notifier);
        final coordinator = fixture.container.read(
          audioCoordinatorProvider.notifier,
        );

        await tts.enqueue(_threeParagraphMessage, 'msg-stopped');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Mid-message: chunk 0 of 3, not the last chunk - same gap as the
        // playNow case above, but this time nothing at the call site knows
        // which message is being interrupted to manually reset it first.
        expect(
          fixture.container
              .read(ttsProvider)
              .getMessageState('msg-stopped')
              .status,
          MessagePlaybackStatus.playing,
        );

        coordinator.forceStop();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final state = fixture.container
            .read(ttsProvider)
            .getMessageState('msg-stopped');
        expect(state.hasPlaybackFocus, isFalse);
        expect(state.status, MessagePlaybackStatus.idle);
      },
    );
  });
}

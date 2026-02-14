import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/sse_provider.dart';

void main() {
  late MessageEventDedup dedup;

  setUp(() {
    dedup = MessageEventDedup();
  });

  group('MessageEventDedup', () {
    test('first event triggers fetch with fromId null (full load)', () {
      final result = dedup.onEvent(2);

      expect(result.skip, isFalse);
      expect(result.fromId, isNull);
    });

    test('second event after fetch completes fetches incrementally', () {
      final first = dedup.onEvent(2);
      expect(first.skip, isFalse);
      dedup.fetchComplete();

      final second = dedup.onEvent(4);

      expect(second.skip, isFalse);
      expect(second.fromId, 3);
    });

    test('event with lower or equal sequence ID is skipped', () {
      dedup.onEvent(4);
      dedup.fetchComplete();

      expect(dedup.onEvent(4).skip, isTrue);
      expect(dedup.onEvent(2).skip, isTrue);
    });

    test('event during in-flight fetch is skipped', () {
      final first = dedup.onEvent(2);
      expect(first.skip, isFalse);

      // Second event arrives while fetch is in-flight
      final second = dedup.onEvent(4);
      expect(second.skip, isTrue);
    });

    test('in-flight skip absorbs higher sequence ID', () {
      dedup.onEvent(2); // triggers fetch
      dedup.onEvent(4); // skipped, absorbed
      dedup.fetchComplete();

      // Next event should fetch from 5, not 3
      final result = dedup.onEvent(6);

      expect(result.skip, isFalse);
      expect(result.fromId, 5);
    });

    test('multiple events during in-flight are all skipped', () {
      dedup.onEvent(2); // triggers fetch

      expect(dedup.onEvent(4).skip, isTrue);
      expect(dedup.onEvent(6).skip, isTrue);
      expect(dedup.onEvent(8).skip, isTrue);

      dedup.fetchComplete();

      // After completion, next event fetches from 9
      final result = dedup.onEvent(10);

      expect(result.skip, isFalse);
      expect(result.fromId, 9);
    });

    test('lower sequence ID during in-flight is also skipped', () {
      dedup.onEvent(4); // triggers fetch

      // Lower sequence ID arrives (out-of-order replay)
      final result = dedup.onEvent(2);

      expect(result.skip, isTrue);
    });

    test('reset clears all state', () {
      dedup.onEvent(4);
      dedup.reset();

      final result = dedup.onEvent(2);

      expect(result.skip, isFalse);
      expect(result.fromId, isNull);
    });

    test('reset during in-flight clears fetch state', () {
      dedup.onEvent(4); // triggers fetch, in-flight
      dedup.reset();

      // After reset, first event triggers full load again
      final result = dedup.onEvent(2);

      expect(result.skip, isFalse);
      expect(result.fromId, isNull);
    });

    group('seed', () {
      test('seeded dedup skips events at or below seed value', () {
        dedup.seed(4);

        expect(dedup.onEvent(2).skip, isTrue);
        expect(dedup.onEvent(4).skip, isTrue);
      });

      test('seeded dedup processes events above seed value', () {
        dedup.seed(4);

        final result = dedup.onEvent(6);

        expect(result.skip, isFalse);
        expect(result.fromId, 5);
      });

      test('seed with null is a no-op', () {
        dedup.seed(null);

        final result = dedup.onEvent(0);

        expect(result.skip, isFalse);
        expect(result.fromId, isNull);
      });

      test('seed does not lower existing sequence ID', () {
        dedup.seed(6);
        dedup.seed(2);

        expect(dedup.onEvent(4).skip, isTrue);
      });

      test('seed after events keeps higher value', () {
        dedup.onEvent(4);
        dedup.fetchComplete();

        dedup.seed(2);

        // Should still use 4, not 2
        final result = dedup.onEvent(6);
        expect(result.skip, isFalse);
        expect(result.fromId, 5);
      });

      test('app restart scenario: messages loaded then SSE replays', () {
        // App loads messages with max sequence ID 4
        dedup.seed(4);

        // SSE replays old events — all should be skipped
        expect(dedup.onEvent(0).skip, isTrue);
        expect(dedup.onEvent(2).skip, isTrue);
        expect(dedup.onEvent(4).skip, isTrue);

        // New event after replay
        final result = dedup.onEvent(6);
        expect(result.skip, isFalse);
        expect(result.fromId, 5);
      });
    });

    test('realistic scenario: rapid burst of events', () {
      // User sends message, engine responds: events seq=2, seq=4 arrive fast
      final first = dedup.onEvent(2);
      expect(first.skip, isFalse);
      expect(first.fromId, isNull);

      // seq=4 arrives before fetch completes — skipped
      final second = dedup.onEvent(4);
      expect(second.skip, isTrue);

      // Fetch completes (got messages 0-4)
      dedup.fetchComplete();

      // Later, another message: seq=6
      final third = dedup.onEvent(6);
      expect(third.skip, isFalse);
      expect(third.fromId, 5);
    });
  });
}

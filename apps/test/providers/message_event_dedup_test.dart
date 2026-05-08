import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/agentic_chat_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/sse_provider.dart';

class _StubSettingsNotifier extends SettingsNotifier {
  @override
  Settings build() => Settings.defaults();

  @override
  Future<String?> getEnginePassword() async => null;

  @override
  Future<String?> getEngineApiKey() async => null;
}

/// Tracks calls to loadHistory and optionally pauses them via a Completer.
class _TrackingChatNotifier extends AgenticChatNotifier {
  int loadHistoryCount = 0;
  Completer<void>? _pauseCompleter;

  void pauseNextLoad() {
    _pauseCompleter = Completer<void>();
  }

  void resumeLoad() {
    final c = _pauseCompleter;
    _pauseCompleter = null;
    c?.complete();
  }

  @override
  Future<void> loadHistory({String? afterMessageId}) async {
    loadHistoryCount++;
    final c = _pauseCompleter;
    if (c != null) await c.future;
  }
}

ProviderContainer _makeContainer(_TrackingChatNotifier tracker) {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _StubSettingsNotifier()),
      agenticChatProvider.overrideWith(() => tracker),
    ],
  );
}

void main() {
  group('SseNotifier.fetchSinceCursor coalescing', () {
    test('single call proceeds immediately', () async {
      final tracker = _TrackingChatNotifier();
      final container = _makeContainer(tracker);
      addTearDown(container.dispose);

      await container.read(sseProvider.notifier).fetchSinceCursor();

      expect(tracker.loadHistoryCount, 1);
    });

    test('sequential calls each execute independently', () async {
      final tracker = _TrackingChatNotifier();
      final container = _makeContainer(tracker);
      addTearDown(container.dispose);

      final notifier = container.read(sseProvider.notifier);
      await notifier.fetchSinceCursor();
      await notifier.fetchSinceCursor();

      expect(tracker.loadHistoryCount, 2);
    });

    test('concurrent call while in-flight coalesces into one refetch', () async {
      final tracker = _TrackingChatNotifier();
      tracker.pauseNextLoad();
      final container = _makeContainer(tracker);
      addTearDown(container.dispose);

      final notifier = container.read(sseProvider.notifier);

      final first = notifier.fetchSinceCursor();
      // Second call arrives while first is paused — should set pending, not start new load
      unawaited(notifier.fetchSinceCursor());

      tracker.resumeLoad();
      await first;

      // Allow pending refetch to complete
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Total: original + one coalesced refetch
      expect(tracker.loadHistoryCount, 2);
    });

    test('multiple concurrent calls coalesce into one refetch', () async {
      final tracker = _TrackingChatNotifier();
      tracker.pauseNextLoad();
      final container = _makeContainer(tracker);
      addTearDown(container.dispose);

      final notifier = container.read(sseProvider.notifier);

      final first = notifier.fetchSinceCursor();
      unawaited(notifier.fetchSinceCursor());
      unawaited(notifier.fetchSinceCursor());
      unawaited(notifier.fetchSinceCursor());

      tracker.resumeLoad();
      await first;

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Still only 2: the original + one coalesced refetch regardless of how
      // many calls arrived while in-flight
      expect(tracker.loadHistoryCount, 2);
    });

    test('no pending refetch when second call arrives after first completes', () async {
      final tracker = _TrackingChatNotifier();
      final container = _makeContainer(tracker);
      addTearDown(container.dispose);

      final notifier = container.read(sseProvider.notifier);

      await notifier.fetchSinceCursor();
      // Not concurrent — arrives after first is done
      await notifier.fetchSinceCursor();

      expect(tracker.loadHistoryCount, 2);
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:agentic_client/agentic_client.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/agentic_chat_provider.dart';
import 'package:relagent/providers/sessions_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/sse_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session identity is the family key now, not something read off Settings.
class _StubSettingsNotifier extends SettingsNotifier {
  @override
  Settings build() => Settings.defaults();

  @override
  Future<String?> getEnginePassword({String? url}) async => null;

  @override
  Future<String?> getEngineApiKey({String? url}) async => null;
}

/// Tracks calls to refreshFromServer instead of making real network calls.
class _TrackingChatNotifier extends AgenticChatNotifier {
  _TrackingChatNotifier(super.sessionId);
  int refreshCount = 0;

  @override
  Future<void> refreshFromServer({http.Client? client}) async {
    refreshCount++;
  }
}

int _nextEventId = 1;
MessagesAppendedEvent _appendedEvent(String sessionId, {DateTime? createdAt}) {
  return MessagesAppendedEvent(
    id: _nextEventId++,
    createdAt: createdAt ?? DateTime.now().toUtc(),
    sessionId: sessionId,
  );
}

Future<ProviderContainer> _makeContainer({
  List<Override> extraOverrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _StubSettingsNotifier()),
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...extraOverrides,
    ],
  );
}

void main() {
  group('SseNotifier — messages.appended routing', () {
    // The coalescing behavior this file used to test lived in
    // SseNotifier.fetchSinceCursor(); that method is gone — coalescing now
    // lives in AgenticChatNotifier.refreshFromServer() itself (see design
    // Decision 5) and is covered directly in agentic_chat_provider_test.dart.
    // What's specific to SseNotifier now is the routing decision itself:
    // an existing instance gets refreshed; a session with none gets a
    // lightweight sessions-list bump instead (design Decision 4).

    test("routes to an existing instance's refreshFromServer", () async {
      final tracker = _TrackingChatNotifier('s1');
      final container = await _makeContainer(
        extraOverrides: [agenticChatProvider('s1').overrideWith(() => tracker)],
      );
      addTearDown(container.dispose);

      // Materialize the instance first — matches a displayed session.
      final subscription = container.listen(
        agenticChatProvider('s1'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      final sseNotifier = container.read(sseProvider.notifier);
      await sseNotifier.handleEventForTest(_appendedEvent('s1'));

      expect(tracker.refreshCount, 1);
    });

    test(
      'does not create a new instance for a session with no live instance',
      () async {
        final container = await _makeContainer();
        addTearDown(container.dispose);

        final sseNotifier = container.read(sseProvider.notifier);
        await sseNotifier.handleEventForTest(_appendedEvent('never-watched'));

        expect(
          container.exists(agenticChatProvider('never-watched')),
          isFalse,
          reason:
              'the SSE handler itself must not be a reason instances get '
              'created — that would defeat the memory bound the disposal '
              'policy relies on',
        );
      },
    );

    test(
      'bumps the sessions list activity for a session with no live instance',
      () async {
        final container = await _makeContainer();
        addTearDown(container.dispose);

        final oldTime = DateTime.utc(2020, 1, 1);
        container
            .read(sessionsProvider.notifier)
            .addSession(
              SessionInfo(
                sessionId: 'bg-session',
                title: 'Background',
                createdAt: oldTime,
                updatedAt: oldTime,
              ),
            );

        final newTime = DateTime.utc(2025, 6, 1);
        final sseNotifier = container.read(sseProvider.notifier);
        await sseNotifier.handleEventForTest(
          _appendedEvent('bg-session', createdAt: newTime),
        );

        final sessions = container.read(sessionsProvider).sessions;
        expect(sessions.first.sessionInfo.sessionId, 'bg-session');
        expect(sessions.first.sessionInfo.updatedAt, newTime);
        expect(
          container.exists(agenticChatProvider('bg-session')),
          isFalse,
          reason:
              'a lightweight activity bump must not materialize the full '
              'chat-state instance',
        );
      },
    );

    test(
      'an older/out-of-order created_at does not regress an already-newer timestamp',
      () async {
        final container = await _makeContainer();
        addTearDown(container.dispose);

        final newTime = DateTime.utc(2025, 6, 1);
        container
            .read(sessionsProvider.notifier)
            .addSession(
              SessionInfo(
                sessionId: 'bg-session',
                title: 'Background',
                createdAt: newTime,
                updatedAt: newTime,
              ),
            );

        final olderTime = DateTime.utc(2020, 1, 1);
        final sseNotifier = container.read(sseProvider.notifier);
        await sseNotifier.handleEventForTest(
          _appendedEvent('bg-session', createdAt: olderTime),
        );

        final sessions = container.read(sessionsProvider).sessions;
        expect(sessions.first.sessionInfo.updatedAt, newTime);
      },
    );
  });
}

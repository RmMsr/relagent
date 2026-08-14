import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relagent/agentic/models.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/agentic_chat_provider.dart';
import 'package:relagent/providers/displayed_session_provider.dart';
import 'package:relagent/providers/new_chat_draft_provider.dart';
import 'package:relagent/providers/settings_provider.dart';

class _StubSettingsNotifier extends SettingsNotifier {
  @override
  Settings build() =>
      Settings.defaults().copyWith(engineBaseUrl: 'http://localhost:0');

  @override
  Future<String?> getEnginePassword({String? url}) async => null;

  @override
  Future<String?> getEngineApiKey({String? url}) async => null;

  // The real implementation persists via a manager this stub's build()
  // never initializes (it skips ref.watch(settingsPersistenceManagerProvider)
  // entirely) — override to just update in-memory state.
  @override
  Future<bool> setAgenticSessionId(String sessionId) async {
    state = state.copyWith(agenticSessionId: sessionId);
    return true;
  }
}

ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: [settingsProvider.overrideWith(() => _StubSettingsNotifier())],
  );
}

void main() {
  group('NewChatDraftNotifier', () {
    test('ignores blank submissions', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(newChatDraftProvider.notifier);

      await notifier.sendMessage('   ');

      expect(container.read(newChatDraftProvider).pendingUserMessage, isNull);
      expect(container.read(newChatDraftProvider).isLoading, isFalse);
    });

    test('changeSensitivity updates local state only (no session to apply it to yet)',
        () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(newChatDraftProvider.notifier);

      notifier.changeSensitivity(SensitivityLevel.confidential);

      expect(
        container.read(newChatDraftProvider).sensitivityLevel,
        SensitivityLevel.confidential,
      );
    });

    test('sendMessage sets isLoading and the optimistic message while in flight',
        () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final mockClient = MockClient((request) async {
        started.complete();
        await release.future;
        return http.Response(
          jsonEncode({
            'session_id': 'new-session',
            'message': {
              'message_id': 'm-response',
              'role': 'assistant',
              'content': 'hi',
              'final': true,
            },
          }),
          200,
        );
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(newChatDraftProvider.notifier);

      final send = notifier.sendMessage('hello', client: mockClient);
      await started.future;

      final mid = container.read(newChatDraftProvider);
      expect(mid.isLoading, isTrue);
      expect(mid.pendingUserMessage?.text, 'hello');

      release.complete();
      await send;
    });

    test('sendMessage on failure surfaces an error and resets isLoading',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error":"boom"}', 500);
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(newChatDraftProvider.notifier);

      await notifier.sendMessage('hello', client: mockClient);

      final state = container.read(newChatDraftProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
    });

    test(
        'sendMessage seeds the new session, points displayedSessionProvider '
        'at it, and resets the draft', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_id': 'new-session',
            'message': {
              'message_id': 'm-response',
              'role': 'assistant',
              'content': 'hi there',
              'final': true,
            },
          }),
          200,
        );
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(newChatDraftProvider.notifier);

      await notifier.sendMessage('hello', client: mockClient);

      expect(container.read(displayedSessionProvider), 'new-session');
      expect(
        container.read(settingsProvider).agenticSessionId,
        'new-session',
      );

      final seeded = container.read(agenticChatProvider('new-session'));
      expect(seeded.messages.map((m) => m.text), ['hello', 'hi there']);
      expect(seeded.messages.every((m) => m.isFinal), isTrue);

      final draft = container.read(newChatDraftProvider);
      expect(draft.pendingUserMessage, isNull);
      expect(draft.isLoading, isFalse);
    });

    test('a second sendMessage while one is already in flight is ignored',
        () async {
      final requestCount = <int>[];
      final release = Completer<void>();
      final mockClient = MockClient((request) async {
        requestCount.add(1);
        await release.future;
        return http.Response(
          jsonEncode({
            'session_id': 'new-session',
            'message': {
              'message_id': 'm-response',
              'role': 'assistant',
              'content': 'hi',
              'final': true,
            },
          }),
          200,
        );
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(newChatDraftProvider.notifier);

      final first = notifier.sendMessage('hello', client: mockClient);
      await notifier.sendMessage('second, should be ignored', client: mockClient);

      // Ignored, not queued or overwritten — the pending message is still
      // the first one while it's in flight.
      expect(
        container.read(newChatDraftProvider).pendingUserMessage?.text,
        'hello',
      );

      release.complete();
      await first;

      expect(requestCount.length, 1);
    });
  });
}

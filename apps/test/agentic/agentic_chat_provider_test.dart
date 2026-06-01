import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relagent/agentic/models.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/agentic_chat_provider.dart';
import 'package:relagent/providers/settings_provider.dart';

/// Minimal settings stub — avoids SharedPreferences, modelDownloadProvider,
/// and path_provider so these tests run as pure unit tests.
class _StubSettingsNotifier extends SettingsNotifier {
  final String? sessionId;
  _StubSettingsNotifier({this.sessionId});

  @override
  Settings build() => Settings.defaults().copyWith(
        agenticSessionId: sessionId,
        engineBaseUrl: 'http://localhost:0',
      );

  @override
  Future<String?> getEnginePassword({String? url}) async => null;

  @override
  Future<String?> getEngineApiKey({String? url}) async => null;
}

AgenticMessage _systemMessageWithApprovals(List<ApprovalData> approvals) {
  return AgenticMessage(
    messageId: 'msg-test',
    localId: 'msg-test',
    text: '',
    role: AgenticRole.system,
    approvals: approvals,
  );
}

ApprovalData _pendingApproval(String id) {
  return ApprovalData(
    id: id,
    type: ApprovalType.outgoingData,
    purpose: 'test purpose',
  );
}

ProviderContainer _makeContainer({String? sessionId}) {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _StubSettingsNotifier(sessionId: sessionId)),
    ],
  );
}

void main() {
  group('AgenticChatNotifier immutability', () {
    // No session ID → triggerContinuation exits immediately, no async side effects.
    late ProviderContainer container;
    late AgenticChatNotifier notifier;

    setUp(() {
      container = _makeContainer();
      notifier = container.read(agenticChatProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('declineApproval produces new ApprovalData instance', () {
      final approval = _pendingApproval('a1');
      final message = _systemMessageWithApprovals([approval]);

      notifier.setStateForTest(AgenticChatState(messages: [message]));

      final before = container.read(agenticChatProvider).messages.first.approvals!.first;
      expect(before.resolution, ApprovalResolution.pending);

      notifier.declineApproval('a1');

      final after = container.read(agenticChatProvider).messages.first.approvals!.first;
      expect(after.resolution, ApprovalResolution.declined);

      // Original object unchanged — confirms immutability
      expect(approval.resolution, ApprovalResolution.pending);
      expect(identical(before, after), isFalse);
    });

    test('declineApproval produces new AgenticMessage instance', () {
      final message = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      final beforeMsg = container.read(agenticChatProvider).messages.first;

      notifier.declineApproval('a1');

      final afterMsg = container.read(agenticChatProvider).messages.first;
      expect(identical(beforeMsg, afterMsg), isFalse);
    });

    test('declineApproval does not affect other approvals', () {
      final a1 = _pendingApproval('a1');
      final a2 = _pendingApproval('a2');
      final message = _systemMessageWithApprovals([a1, a2]);
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      notifier.declineApproval('a1');

      final approvals = container.read(agenticChatProvider).messages.first.approvals!;
      expect(approvals[0].resolution, ApprovalResolution.declined);
      expect(approvals[1].resolution, ApprovalResolution.pending);
    });

    test('changeSensitivity marks pending approvals stale via new instances', () async {
      // Needs its own container with a session ID so changeSensitivity doesn't
      // short-circuit. The test is async so async side effects complete before
      // tearDown disposes the container.
      final localContainer = _makeContainer(sessionId: 'test-session');
      addTearDown(localContainer.dispose);
      final localNotifier = localContainer.read(agenticChatProvider.notifier);

      final approval = _pendingApproval('a1');
      final message = _systemMessageWithApprovals([approval]);
      localNotifier.setStateForTest(
        AgenticChatState(
          messages: [message],
          sensitivityLevel: SensitivityLevel.personal,
        ),
      );

      // Await so the HTTP call (which will fail) completes before tearDown.
      // Only sensitivity level is reverted on failure — messages remain stale.
      await localNotifier
          .changeSensitivity(SensitivityLevel.confidential)
          .catchError((_) {});

      final updatedMsg = localContainer.read(agenticChatProvider).messages.first;
      expect(updatedMsg.isStale, isTrue);
      expect(
        updatedMsg.approvals!.first.resolution,
        ApprovalResolution.stale,
      );

      // Original objects unchanged — confirms immutability
      expect(message.isStale, isFalse);
      expect(approval.resolution, ApprovalResolution.pending);
    });
  });

  group('AgenticChatState.copyWith', () {
    test('preserves unspecified fields', () {
      final state = AgenticChatState(
        messages: [],
        sensitivityLevel: SensitivityLevel.confidential,
        isLoading: true,
      );

      final updated = state.copyWith(isLoading: false);

      expect(updated.isLoading, isFalse);
      expect(updated.sensitivityLevel, SensitivityLevel.confidential);
      expect(updated.messages, isEmpty);
    });

    test('queuedMessage round-trips through copyWith', () {
      const state = AgenticChatState(messages: []);
      final withQueue = state.copyWith(queuedMessage: 'hi');
      expect(withQueue.queuedMessage, 'hi');

      final preserved = withQueue.copyWith(isLoading: true);
      expect(preserved.queuedMessage, 'hi');

      final cleared = withQueue.copyWith(clearQueuedMessage: true);
      expect(cleared.queuedMessage, isNull);
    });
  });

  group('AgenticChatState getters', () {
    test('isAwaiting is false on empty idle state', () {
      const state = AgenticChatState(messages: []);
      expect(state.isAwaiting, isFalse);
    });

    test('isAwaiting is true while isLoading', () {
      const state = AgenticChatState(messages: [], isLoading: true);
      expect(state.isAwaiting, isTrue);
    });

    test('isAwaiting is true when trailing message is non-final', () {
      final state = AgenticChatState(
        messages: [AgenticMessage.user('hi')], // user defaults isFinal=false
      );
      expect(state.isAwaiting, isTrue);
    });

    test('isAwaiting is false when trailing message is final', () {
      final state = AgenticChatState(
        messages: [AgenticMessage.assistant('hello')], // assistant is final
      );
      expect(state.isAwaiting, isFalse);
    });

    test('isAwaiting skips trailing error messages', () {
      // Errors are local-only UI events. A trailing error must NOT mask
      // an in-flight cycle that the engine still owns (the failed-
      // continuation case).
      final inflightSys = AgenticMessage(
        messageId: 'msg-sys',
        localId: 'sys',
        text: '',
        role: AgenticRole.system,
        approvals: const [],
        isFinal: false,
      );
      final state = AgenticChatState(
        messages: [
          inflightSys,
          AgenticMessage.error('boom'), // isFinal=true
        ],
      );
      expect(state.isAwaiting, isTrue);
    });

    test('inputEnabled is true with no queued message', () {
      const state = AgenticChatState(messages: []);
      expect(state.inputEnabled, isTrue);
    });

    test('inputEnabled is false when a queued message exists', () {
      const state = AgenticChatState(messages: [], queuedMessage: 'q');
      expect(state.inputEnabled, isFalse);
    });
  });

  group('AgenticChatNotifier — queued message', () {
    late ProviderContainer container;
    late AgenticChatNotifier notifier;

    setUp(() {
      container = _makeContainer(sessionId: 'test-session');
      notifier = container.read(agenticChatProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('clears queued message when active session id changes', () {
      // Seed a queued message tied to session 'test-session'.
      notifier.setStateForTest(
        const AgenticChatState(messages: [], queuedMessage: 'for session A'),
      );
      expect(
        container.read(agenticChatProvider).queuedMessage,
        'for session A',
      );

      // Switch to a different active session — queue must NOT carry over,
      // otherwise it would auto-dispatch into the wrong session.
      final settingsNotifier = container.read(settingsProvider.notifier);
      settingsNotifier.state = settingsNotifier.state.copyWith(
        agenticSessionId: 'different-session',
      );

      expect(container.read(agenticChatProvider).queuedMessage, isNull);
    });

    test('retryFailedMessages on stuck continuation keeps the SystemAction',
        () async {
      // Reproduce the failed-/continue scenario: granted approval lives
      // in an in-flight SystemAction (final=false). Retry must not strip
      // the SystemAction (the engine still has it) and must call
      // triggerContinuation rather than re-POSTing user messages.
      final granted = ApprovalData(
        id: 'a1',
        type: ApprovalType.outgoingData,
        purpose: 'p',
        resolution: ApprovalResolution.granted,
      );
      final user = AgenticMessage(
        messageId: 'msg-user-0',
        localId: 'u',
        text: 'go',
        role: AgenticRole.user,
        isFinal: false,
      );
      final stuckSys = AgenticMessage(
        messageId: 'msg-sys-1',
        localId: 'sys',
        text: '',
        role: AgenticRole.system,
        approvals: [granted],
        isFinal: false,
      );
      final error = AgenticMessage.error('inference failed');

      notifier.setStateForTest(
        AgenticChatState(messages: [user, stuckSys, error]),
      );

      // Will hit the network in test env and append a new error; that
      // is fine — we're checking that the strip kept the SystemAction
      // and that triggerContinuation, not sendMessage-with-user-text,
      // was the recovery branch taken.
      await notifier.retryFailedMessages().catchError((_) {});

      final messages = container.read(agenticChatProvider).messages;
      // SystemAction (msg-sys-1) survived the strip.
      expect(
        messages.any(
          (m) => m.messageId == 'msg-sys-1' && m.role == AgenticRole.system,
        ),
        isTrue,
      );
      // Original user message (msg-user-0) survived too.
      expect(
        messages.any(
          (m) => m.messageId == 'msg-user-0' && m.role == AgenticRole.user,
        ),
        isTrue,
      );
      // No new user message was appended (no re-POST of "go").
      final userMessages =
          messages.where((m) => m.role == AgenticRole.user).toList();
      expect(userMessages.length, 1);
      expect(userMessages.first.messageId, 'msg-user-0');
    });

    test('retryFailedMessages keeps the trailing error in history', () async {
      // A failed send leaves [user(final), error]. Retrying re-POSTs the
      // unsent user message but MUST keep the original error so the user
      // can follow the sequence of events, and MUST NOT duplicate the
      // user message.
      final user = AgenticMessage(
        messageId: 'msg-user-0',
        localId: 'u',
        text: 'go',
        role: AgenticRole.user,
        isFinal: true,
      );
      final error = AgenticMessage.error('inference engine unreachable');

      notifier.setStateForTest(
        AgenticChatState(messages: [user, error]),
      );

      // The re-POST hits the network in the test env and fails; that's fine —
      // we only assert the original error survived and the user wasn't dupbed.
      await notifier.retryFailedMessages().catchError((_) {});

      final messages = container.read(agenticChatProvider).messages;

      expect(
        messages.any(
          (m) =>
              m.messageId == error.messageId && m.role == AgenticRole.error,
        ),
        isTrue,
        reason: 'original error must be preserved across retry',
      );
      final userMessages =
          messages.where((m) => m.role == AgenticRole.user).toList();
      expect(userMessages.length, 1);
      expect(userMessages.first.messageId, 'msg-user-0');
    });

    test('preserves queued message when active session id is unchanged', () {
      notifier.setStateForTest(
        const AgenticChatState(messages: [], queuedMessage: 'still here'),
      );

      // Re-set the same id — listener selects on agenticSessionId so the
      // no-op change must not fire the queue-clear callback.
      final settingsNotifier = container.read(settingsProvider.notifier);
      settingsNotifier.state = settingsNotifier.state.copyWith(
        agenticSessionId: 'test-session',
      );

      expect(container.read(agenticChatProvider).queuedMessage, 'still here');
    });

    test('sendMessage enqueues when awaiting and does not append', () async {
      // Seed an in-flight trailing system message (pending approval).
      final pending = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [pending]));

      // Sanity: cycle is in-flight per state machine.
      expect(container.read(agenticChatProvider).isAwaiting, isTrue);

      await notifier.sendMessage('queue me');

      final state = container.read(agenticChatProvider);
      expect(state.queuedMessage, 'queue me');
      // Original message list unchanged (no user bubble appended).
      expect(state.messages.length, 1);
      expect(state.inputEnabled, isFalse);
    });

    test('sendMessage replaces an existing queued message', () async {
      final pending = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(
        AgenticChatState(messages: [pending], queuedMessage: 'first'),
      );

      await notifier.sendMessage('second');

      expect(container.read(agenticChatProvider).queuedMessage, 'second');
    });

    test('sendMessage ignores blank queued submissions', () async {
      final pending = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [pending]));

      await notifier.sendMessage('   ');

      expect(container.read(agenticChatProvider).queuedMessage, isNull);
    });

    test('editQueued returns the text and clears the slot', () {
      notifier.setStateForTest(
        const AgenticChatState(messages: [], queuedMessage: 'draft'),
      );

      final text = notifier.editQueued();

      expect(text, 'draft');
      expect(container.read(agenticChatProvider).queuedMessage, isNull);
      expect(container.read(agenticChatProvider).inputEnabled, isTrue);
    });

    test('editQueued returns null when nothing is queued', () {
      notifier.setStateForTest(const AgenticChatState(messages: []));
      expect(notifier.editQueued(), isNull);
    });
  });

  group('AgenticChatNotifier — _ingestMessages', () {
    late ProviderContainer container;
    late AgenticChatNotifier notifier;

    setUp(() {
      container = _makeContainer();
      notifier = container.read(agenticChatProvider.notifier);
    });

    tearDown(() => container.dispose());

    AgenticMessage _msg(
      String messageId,
      AgenticRole role, {
      bool isFinal = true,
      String text = '',
    }) {
      return AgenticMessage(
        messageId: messageId,
        localId: 'lid-$messageId',
        text: text,
        role: role,
        isFinal: isFinal,
      );
    }

    test('new message is appended', () {
      notifier.setStateForTest(AgenticChatState(messages: []));

      notifier.ingestMessagesForTest([_msg('m1', AgenticRole.user, text: 'hi')]);

      final msgs = container.read(agenticChatProvider).messages;
      expect(msgs.length, 1);
      expect(msgs[0].messageId, 'm1');
    });

    test('present-and-final message is skipped (not overwritten)', () {
      final existing = _msg('m1', AgenticRole.assistant, text: 'original');
      notifier.setStateForTest(AgenticChatState(messages: [existing]));

      notifier.ingestMessagesForTest(
        [_msg('m1', AgenticRole.assistant, text: 'CHANGED')],
      );

      final msgs = container.read(agenticChatProvider).messages;
      expect(msgs.length, 1);
      expect(msgs[0].text, 'original');
    });

    test('present-and-non-final message is replaced', () {
      final existing =
          _msg('m1', AgenticRole.system, isFinal: false, text: 'old');
      notifier.setStateForTest(AgenticChatState(messages: [existing]));

      notifier.ingestMessagesForTest(
        [_msg('m1', AgenticRole.system, text: 'updated')],
      );

      final msgs = container.read(agenticChatProvider).messages;
      expect(msgs.length, 1);
      expect(msgs[0].text, 'updated');
      expect(msgs[0].isFinal, isTrue);
    });

    test('repeated call with same message is idempotent', () {
      final msg = _msg('m1', AgenticRole.user, text: 'hello');
      notifier.setStateForTest(AgenticChatState(messages: [msg]));

      notifier.ingestMessagesForTest([msg]);
      notifier.ingestMessagesForTest([msg]);

      expect(container.read(agenticChatProvider).messages.length, 1);
    });

    test('multiple new messages appended in order', () {
      notifier.setStateForTest(
        AgenticChatState(
          messages: [_msg('m1', AgenticRole.user, text: 'first')],
        ),
      );

      notifier.ingestMessagesForTest([
        _msg('m2', AgenticRole.assistant, text: 'second'),
        _msg('m3', AgenticRole.system, text: 'third'),
      ]);

      final texts =
          container.read(agenticChatProvider).messages.map((m) => m.text);
      expect(texts.toList(), ['first', 'second', 'third']);
    });

    test('AgenticMessage.assistant defaults to final', () {
      expect(AgenticMessage.assistant('hi').isFinal, isTrue);
    });

    test('AgenticMessage.error defaults to final', () {
      expect(AgenticMessage.error('boom').isFinal, isTrue);
    });

    test('AgenticMessage.user defaults to non-final (in-flight)', () {
      expect(AgenticMessage.user('hi').isFinal, isFalse);
    });
  });

  group('AgenticChatNotifier — loadHistory sensitivity', () {
    test('sets sensitivityLevel from response on full load', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_id': 'test-session',
            'messages': [],
            'sensitivity_level': 4,
          }),
          200,
        );
      });

      final container = _makeContainer(sessionId: 'test-session');
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider.notifier);

      await notifier.loadHistory(client: mockClient);

      final state = container.read(agenticChatProvider);
      expect(state.sensitivityLevel, SensitivityLevel.confidential);
    });

    test('sets sensitivityLevel from response on incremental load', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_id': 'test-session',
            'messages': [],
            'sensitivity_level': 4,
          }),
          200,
        );
      });

      final container = _makeContainer(sessionId: 'test-session');
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider.notifier);

      await notifier.loadHistory(afterMessageId: 'cursor', client: mockClient);

      final state = container.read(agenticChatProvider);
      expect(state.sensitivityLevel, SensitivityLevel.confidential);
    });

    test('does not reset sensitivityLevel when field is absent', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_id': 'test-session',
            'messages': [],
          }),
          200,
        );
      });

      final container = _makeContainer(sessionId: 'test-session');
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider.notifier);

      notifier.setStateForTest(
        AgenticChatState(
          messages: [],
          sensitivityLevel: SensitivityLevel.confidential,
        ),
      );

      await notifier.loadHistory(client: mockClient);

      final state = container.read(agenticChatProvider);
      expect(state.sensitivityLevel, SensitivityLevel.confidential);
    });
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agentic_client/agentic_client.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/agentic_chat_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/tts_provider.dart';

/// Minimal settings stub — avoids SharedPreferences, modelDownloadProvider,
/// and path_provider so these tests run as pure unit tests. Session
/// identity now lives entirely in the family key, not Settings, so this
/// only needs to supply engine connection config.
class _StubSettingsNotifier extends SettingsNotifier {
  @override
  Settings build() =>
      Settings.defaults().copyWith(engineBaseUrl: 'http://localhost:0');

  @override
  Future<String?> getEnginePassword({String? url}) async => null;

  @override
  Future<String?> getEngineApiKey({String? url}) async => null;

  /// Lets a test flip voice mode mid-flight, simulating the user turning on
  /// auto-playback while a request is still in the air.
  void setVoiceModeForTest(VoiceMode mode) {
    state = state.copyWith(voiceMode: mode);
  }
}

/// Records enqueue() calls instead of touching real TTS/audio backends,
/// which aren't available in a plain ProviderContainer unit test.
class _RecordingTtsNotifier extends TtsNotifier {
  final List<String> enqueuedMessageIds = [];

  @override
  TtsState build() => TtsState.initial();

  @override
  Future<void> enqueue(String text, String messageId) async {
    enqueuedMessageIds.add(messageId);
  }
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

ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: [settingsProvider.overrideWith(() => _StubSettingsNotifier())],
  );
}

void main() {
  group('AgenticChatNotifier immutability', () {
    late ProviderContainer container;
    late AgenticChatNotifier notifier;

    setUp(() {
      container = _makeContainer();
      notifier = container.read(agenticChatProvider('s1').notifier);
    });

    tearDown(() => container.dispose());

    test('declineApproval produces new ApprovalData instance', () {
      final approval = _pendingApproval('a1');
      final message = _systemMessageWithApprovals([approval]);

      notifier.setStateForTest(AgenticChatState(messages: [message]));

      final before =
          container.read(agenticChatProvider('s1')).messages.first.approvals!.first;
      expect(before.resolution, ApprovalResolution.pending);

      // Hits the network in the test env and fails; that's fine — only the
      // synchronous optimistic update (before the first await) is asserted.
      notifier.declineApproval('a1').catchError((_) {});

      final after =
          container.read(agenticChatProvider('s1')).messages.first.approvals!.first;
      expect(after.resolution, ApprovalResolution.declined);

      // Original object unchanged — confirms immutability
      expect(approval.resolution, ApprovalResolution.pending);
      expect(identical(before, after), isFalse);
    });

    test('declineApproval produces new AgenticMessage instance', () {
      final message = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      final beforeMsg = container.read(agenticChatProvider('s1')).messages.first;

      notifier.declineApproval('a1').catchError((_) {});

      final afterMsg = container.read(agenticChatProvider('s1')).messages.first;
      expect(identical(beforeMsg, afterMsg), isFalse);
    });

    test('declineApproval does not affect other approvals', () {
      final a1 = _pendingApproval('a1');
      final a2 = _pendingApproval('a2');
      final message = _systemMessageWithApprovals([a1, a2]);
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      notifier.declineApproval('a1').catchError((_) {});

      final approvals =
          container.read(agenticChatProvider('s1')).messages.first.approvals!;
      expect(approvals[0].resolution, ApprovalResolution.declined);
      expect(approvals[1].resolution, ApprovalResolution.pending);
    });

    test('changeSensitivity marks pending approvals stale via new instances', () async {
      final approval = _pendingApproval('a1');
      final message = _systemMessageWithApprovals([approval]);
      notifier.setStateForTest(
        AgenticChatState(
          messages: [message],
          sensitivityLevel: SensitivityLevel.personal,
        ),
      );

      // Await so the HTTP call (which will fail) completes before tearDown.
      // Only sensitivity level is reverted on failure — messages remain stale.
      await notifier
          .changeSensitivity(SensitivityLevel.confidential)
          .catchError((_) {});

      final updatedMsg = container.read(agenticChatProvider('s1')).messages.first;
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
      container = _makeContainer();
      notifier = container.read(agenticChatProvider('test-session').notifier);
    });

    tearDown(() => container.dispose());

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

      final messages = container.read(agenticChatProvider('test-session')).messages;
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

      final messages = container.read(agenticChatProvider('test-session')).messages;

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

    test('sendMessage enqueues when awaiting and does not append', () async {
      // Seed an in-flight trailing system message (pending approval).
      final pending = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [pending]));

      // Sanity: cycle is in-flight per state machine.
      expect(container.read(agenticChatProvider('test-session')).isAwaiting, isTrue);

      await notifier.sendMessage('queue me');

      final state = container.read(agenticChatProvider('test-session'));
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

      expect(container.read(agenticChatProvider('test-session')).queuedMessage, 'second');
    });

    test('sendMessage ignores blank queued submissions', () async {
      final pending = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [pending]));

      await notifier.sendMessage('   ');

      expect(container.read(agenticChatProvider('test-session')).queuedMessage, isNull);
    });

    test('editQueued returns the text and clears the slot', () {
      notifier.setStateForTest(
        const AgenticChatState(messages: [], queuedMessage: 'draft'),
      );

      final text = notifier.editQueued();

      expect(text, 'draft');
      expect(container.read(agenticChatProvider('test-session')).queuedMessage, isNull);
      expect(container.read(agenticChatProvider('test-session')).inputEnabled, isTrue);
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
      notifier = container.read(agenticChatProvider('s1').notifier);
    });

    tearDown(() => container.dispose());

    AgenticMessage msg(
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

      notifier.ingestMessagesForTest([msg('m1', AgenticRole.user, text: 'hi')]);

      final msgs = container.read(agenticChatProvider('s1')).messages;
      expect(msgs.length, 1);
      expect(msgs[0].messageId, 'm1');
    });

    test('present-and-final message is skipped (not overwritten)', () {
      final existing = msg('m1', AgenticRole.assistant, text: 'original');
      notifier.setStateForTest(AgenticChatState(messages: [existing]));

      notifier.ingestMessagesForTest(
        [msg('m1', AgenticRole.assistant, text: 'CHANGED')],
      );

      final msgs = container.read(agenticChatProvider('s1')).messages;
      expect(msgs.length, 1);
      expect(msgs[0].text, 'original');
    });

    test('present-and-non-final message is replaced', () {
      final existing =
          msg('m1', AgenticRole.system, isFinal: false, text: 'old');
      notifier.setStateForTest(AgenticChatState(messages: [existing]));

      notifier.ingestMessagesForTest(
        [msg('m1', AgenticRole.system, text: 'updated')],
      );

      final msgs = container.read(agenticChatProvider('s1')).messages;
      expect(msgs.length, 1);
      expect(msgs[0].text, 'updated');
      expect(msgs[0].isFinal, isTrue);
    });

    test('repeated call with same message is idempotent', () {
      final message = msg('m1', AgenticRole.user, text: 'hello');
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      notifier.ingestMessagesForTest([message]);
      notifier.ingestMessagesForTest([message]);

      expect(container.read(agenticChatProvider('s1')).messages.length, 1);
    });

    test('multiple new messages appended in order', () {
      notifier.setStateForTest(
        AgenticChatState(
          messages: [msg('m1', AgenticRole.user, text: 'first')],
        ),
      );

      notifier.ingestMessagesForTest([
        msg('m2', AgenticRole.assistant, text: 'second'),
        msg('m3', AgenticRole.system, text: 'third'),
      ]);

      final texts =
          container.read(agenticChatProvider('s1')).messages.map((m) => m.text);
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

  group('AgenticChatNotifier — loadHistory / refreshFromServer', () {
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

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('test-session').notifier);

      await notifier.loadHistory(client: mockClient);

      final state = container.read(agenticChatProvider('test-session'));
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

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('test-session').notifier);

      await notifier.loadHistory(afterMessageId: 'cursor', client: mockClient);

      final state = container.read(agenticChatProvider('test-session'));
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

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('test-session').notifier);

      notifier.setStateForTest(
        AgenticChatState(
          messages: [],
          sensitivityLevel: SensitivityLevel.confidential,
        ),
      );

      await notifier.loadHistory(client: mockClient);

      final state = container.read(agenticChatProvider('test-session'));
      expect(state.sensitivityLevel, SensitivityLevel.confidential);
    });

    test('refreshFromServer fetches everything for a fresh instance (no cursor)',
        () async {
      Uri? requestedUri;
      final mockClient = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({'session_id': 'test-session', 'messages': []}),
          200,
        );
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('test-session').notifier);

      await notifier.refreshFromServer(client: mockClient);

      expect(
        requestedUri!.queryParameters.containsKey('after'),
        isFalse,
        reason: 'a fresh instance has no final messages, so its cursor is '
            'null — the same code path degrades to a full load',
      );
    });

    test('refreshFromServer fetches since the last known final message',
        () async {
      Uri? requestedUri;
      final mockClient = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({'session_id': 'test-session', 'messages': []}),
          200,
        );
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('test-session').notifier);
      notifier.setStateForTest(
        AgenticChatState(
          messages: [
            AgenticMessage(
              messageId: 'm-final',
              localId: 'm-final',
              text: 'hi',
              role: AgenticRole.assistant,
              isFinal: true,
            ),
          ],
        ),
      );

      await notifier.refreshFromServer(client: mockClient);

      expect(requestedUri!.queryParameters['after'], 'm-final');
    });

    test('refreshFromServer coalesces concurrent calls into one re-fetch',
        () async {
      var requestCount = 0;
      final firstRequestStarted = Completer<void>();
      final releaseFirstResponse = Completer<void>();
      final secondRequestCompleted = Completer<void>();
      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          firstRequestStarted.complete();
          await releaseFirstResponse.future;
        }
        final response = http.Response(
          jsonEncode({'session_id': 'test-session', 'messages': []}),
          200,
        );
        if (requestCount == 2) secondRequestCompleted.complete();
        return response;
      });

      final container = _makeContainer();
      addTearDown(container.dispose);
      // Keep the instance alive across the awaits below — matches a
      // realistically-displayed session and avoids relying on autoDispose
      // timing luck within the test itself.
      final subscription =
          container.listen(agenticChatProvider('test-session'), (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(agenticChatProvider('test-session').notifier);

      unawaited(notifier.refreshFromServer(client: mockClient));
      await firstRequestStarted.future;
      // Fired while the first is still in flight — must coalesce into a
      // single re-fetch after it completes, not a second overlapping one.
      unawaited(notifier.refreshFromServer(client: mockClient));
      unawaited(notifier.refreshFromServer(client: mockClient));

      releaseFirstResponse.complete();
      await secondRequestCompleted.future;

      expect(
        requestCount,
        2,
        reason: 'the in-flight call plus exactly one coalesced re-fetch',
      );
    });
  });

  group('AgenticChatNotifier — seedFirstExchange', () {
    test('merges the user message and response, marking both final when the '
        'response is final', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('new-session').notifier);

      final userMessage = AgenticMessage.user('hello');
      final response = AgenticMessage.assistant('hi there');

      notifier.seedFirstExchange(
        userMessage: userMessage,
        response: response,
        sensitivityLevel: SensitivityLevel.confidential,
      );

      final state = container.read(agenticChatProvider('new-session'));
      expect(state.messages.map((m) => m.messageId), [
        userMessage.messageId,
        response.messageId,
      ]);
      expect(state.messages.every((m) => m.isFinal), isTrue);
      expect(state.sensitivityLevel, SensitivityLevel.confidential);
    });

    test('leaves the response non-final when it is not final (e.g. a pending approval)',
        () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agenticChatProvider('new-session').notifier);

      final userMessage = AgenticMessage.user('do the thing');
      final response = _systemMessageWithApprovals([_pendingApproval('a1')]);

      notifier.seedFirstExchange(
        userMessage: userMessage,
        response: response,
        sensitivityLevel: SensitivityLevel.personal,
      );

      final state = container.read(agenticChatProvider('new-session'));
      expect(state.isAwaiting, isTrue);
    });
  });

  group('AgenticChatNotifier — per-session isolation', () {
    test('two different session ids produce independent instances', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifierA = container.read(agenticChatProvider('session-a').notifier);
      notifierA.setStateForTest(
        AgenticChatState(messages: [AgenticMessage.assistant('only in A')]),
      );

      final stateB = container.read(agenticChatProvider('session-b'));
      expect(
        stateB.messages,
        isEmpty,
        reason: 'family instances are separate objects by construction — '
            'nothing written to session-a can reach session-b',
      );
    });
  });

  group('AgenticChatNotifier — disposal policy', () {
    test('a session with an in-flight cycle is not disposed when unwatched',
        () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Simulate the page watching this session (e.g. it's displayed).
      final subscription =
          container.listen(agenticChatProvider('s1'), (_, _) {});

      final notifier = container.read(agenticChatProvider('s1').notifier);
      final pending = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [pending]));
      expect(container.read(agenticChatProvider('s1')).isAwaiting, isTrue);

      // Simulate navigating away: the widget stops watching.
      subscription.close();

      // The in-flight cycle must keep it alive — re-reading it must return
      // the same state, not a freshly-rebuilt empty one, even though
      // nothing is watching it anymore.
      final stillThere = container.read(agenticChatProvider('s1'));
      expect(stillThere.messages, hasLength(1));
      expect(
        stillThere.messages.first.approvals!.first.resolution,
        ApprovalResolution.pending,
      );
    });

    test(
        'an idle session survives a quick flip back within the linger window',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      var subscription = container.listen(agenticChatProvider('s1'), (_, _) {});
      final notifier = container.read(agenticChatProvider('s1').notifier);
      notifier.setStateForTest(
        AgenticChatState(messages: [AgenticMessage.assistant('hello')]),
      );
      expect(container.read(agenticChatProvider('s1')).isAwaiting, isFalse);

      subscription.close();
      // Immediately re-watch, well within the idle-linger grace window.
      subscription = container.listen(agenticChatProvider('s1'), (_, _) {});

      final state = container.read(agenticChatProvider('s1'));
      expect(
        state.messages,
        hasLength(1),
        reason: 'a quick flip back must reuse the still-warm instance, not '
            'a freshly disposed-and-rebuilt empty one',
      );
      subscription.close();
    });

    test('an idle session is disposed after the linger window if never rewatched',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final subscription = container.listen(agenticChatProvider('s1'), (_, _) {});
      final notifier = container.read(agenticChatProvider('s1').notifier);
      notifier.setStateForTest(
        AgenticChatState(messages: [AgenticMessage.assistant('hello')]),
      );

      subscription.close();
      // Past the 500ms idle-linger window, still unwatched.
      await Future.delayed(const Duration(milliseconds: 700));

      final freshWatch = container.listen(agenticChatProvider('s1'), (_, _) {});
      final state = container.read(agenticChatProvider('s1'));
      expect(
        state.messages,
        isEmpty,
        reason: 'genuinely idle and unwatched past the linger window — '
            'disposed and rebuilt fresh on next display, matching the '
            'always-reconcile-on-redisplay design',
      );
      freshWatch.close();
    });
  });

  group('AgenticChatNotifier — auto-playback re-check on response arrival', () {
    test(
        'turning on auto-playback while a request is in flight still plays '
        'the response that arrives afterward',
        () async {
      final settingsNotifier = _StubSettingsNotifier();
      final fakeTts = _RecordingTtsNotifier();
      final responseGate = Completer<void>();

      final mockClient = MockClient((request) async {
        // Held open so the test can flip voice mode before the response
        // lands, mirroring the user toggling continuous playback while
        // still waiting for the engine to answer.
        await responseGate.future;
        return http.Response(
          jsonEncode({
            'message': {
              'role': 'assistant',
              'content': 'hi there',
              'message_id': 'resp-1',
              'final': true,
            },
          }),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => settingsNotifier),
          ttsProvider.overrideWith(() => fakeTts),
        ],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(agenticChatProvider('auto-play-session').notifier);

      // Voice mode starts silent (no auto-playback) when the message is sent.
      final sendFuture = notifier.sendMessage('hello', client: mockClient);

      // The user turns on continuous playback while the request is still
      // in flight.
      settingsNotifier.setVoiceModeForTest(VoiceMode.reading);

      responseGate.complete();
      await sendFuture;

      expect(
        fakeTts.enqueuedMessageIds,
        isNotEmpty,
        reason: 'auto-playback must be re-checked against current settings '
            'when the response arrives, not the stale settings captured '
            'when the request was sent',
      );
    });
  });
}

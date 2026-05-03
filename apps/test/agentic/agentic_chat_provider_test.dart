import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Settings build() => Settings.defaults().copyWith(agenticSessionId: sessionId);

  @override
  Future<String?> getEnginePassword() async => null;

  @override
  Future<String?> getEngineApiKey() async => null;
}

AgenticMessage _systemMessageWithApprovals(List<ApprovalData> approvals) {
  return AgenticMessage(
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
        localId: 'u',
        text: 'go',
        role: AgenticRole.user,
        id: 0,
        isFinal: false,
      );
      final stuckSys = AgenticMessage(
        localId: 'sys',
        text: '',
        role: AgenticRole.system,
        approvals: [granted],
        id: 1,
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
      // SystemAction (id=1) survived the strip.
      expect(messages.any((m) => m.id == 1 && m.role == AgenticRole.system),
          isTrue);
      // Original user message (id=0) survived too.
      expect(messages.any((m) => m.id == 0 && m.role == AgenticRole.user),
          isTrue);
      // No new local user record was appended (no re-POST of "go").
      final localUsers = messages
          .where((m) => m.role == AgenticRole.user && m.id == null)
          .toList();
      expect(localUsers, isEmpty);
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

  group('AgenticChatNotifier — refresh policy', () {
    late ProviderContainer container;
    late AgenticChatNotifier notifier;

    setUp(() {
      container = _makeContainer();
      notifier = container.read(agenticChatProvider.notifier);
    });

    tearDown(() => container.dispose());

    AgenticMessage msg(int? id, AgenticRole role, {bool isFinal = true,
        String text = ''}) {
      return AgenticMessage(
        id: id,
        localId: 'lid-$id-${role.name}-$isFinal',
        text: text,
        role: role,
        isFinal: isFinal,
      );
    }

    test('cached final=true is preserved against an updated fetched copy', () {
      final cached = [msg(1, AgenticRole.assistant, text: 'cached')];
      final fetched = [msg(1, AgenticRole.assistant, text: 'CHANGED')];

      final merged = notifier.mergeRefreshForTest(cached, fetched);

      expect(merged.length, 1);
      expect(merged[0].text, 'cached');
    });

    test('cached final=false is overwritten by fetched copy', () {
      final cached = [msg(1, AgenticRole.system, isFinal: false, text: 'cached')];
      final fetched = [msg(1, AgenticRole.system, text: 'updated')];

      final merged = notifier.mergeRefreshForTest(cached, fetched);

      expect(merged.length, 1);
      expect(merged[0].text, 'updated');
      expect(merged[0].isFinal, isTrue);
    });

    test('absent fetched messages are appended in order', () {
      final cached = [msg(1, AgenticRole.user, text: 'one')];
      final fetched = [
        msg(2, AgenticRole.system, text: 'two'),
        msg(3, AgenticRole.assistant, text: 'three'),
      ];

      final merged = notifier.mergeRefreshForTest(cached, fetched);

      expect(merged.map((m) => m.text).toList(), ['one', 'two', 'three']);
    });

    test('mixed cached/new is handled in a single pass', () {
      final cached = [
        msg(1, AgenticRole.user, text: 'u-cached'),       // final=true → keep
        msg(2, AgenticRole.system, isFinal: false, text: 'sys-cached'),
      ];
      final fetched = [
        msg(1, AgenticRole.user, text: 'u-engine'),       // skipped
        msg(2, AgenticRole.system, text: 'sys-engine'),   // overwrites
        msg(3, AgenticRole.assistant, text: 'a-engine'),  // appended
      ];

      final merged = notifier.mergeRefreshForTest(cached, fetched);

      expect(merged.map((m) => m.text).toList(),
          ['u-cached', 'sys-engine', 'a-engine']);
    });

    test('markTrailingFinal flips in-flight chain back to prior boundary', () {
      final messages = [
        msg(1, AgenticRole.assistant, text: 'prev cycle'),       // final=true
        msg(2, AgenticRole.user, isFinal: false, text: 'u'),
        msg(3, AgenticRole.system, isFinal: false, text: 's'),
        msg(4, AgenticRole.assistant, text: 'settled'),          // final=true
      ];

      final flipped = notifier.markTrailingFinalForTest(messages);

      // Prior boundary (#1) untouched, in-flight chain (#2, #3) now final,
      // settlement (#4) untouched.
      expect(flipped.map((m) => m.isFinal).toList(),
          [true, true, true, true]);
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
}

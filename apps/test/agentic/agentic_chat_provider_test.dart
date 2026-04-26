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

    test('skipApproval produces new ApprovalData instance', () {
      final approval = _pendingApproval('a1');
      final message = _systemMessageWithApprovals([approval]);

      notifier.setStateForTest(AgenticChatState(messages: [message]));

      final before = container.read(agenticChatProvider).messages.first.approvals!.first;
      expect(before.resolution, ApprovalResolution.pending);

      notifier.skipApproval('a1');

      final after = container.read(agenticChatProvider).messages.first.approvals!.first;
      expect(after.resolution, ApprovalResolution.skipped);

      // Original object unchanged — confirms immutability
      expect(approval.resolution, ApprovalResolution.pending);
      expect(identical(before, after), isFalse);
    });

    test('skipApproval produces new AgenticMessage instance', () {
      final message = _systemMessageWithApprovals([_pendingApproval('a1')]);
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      final beforeMsg = container.read(agenticChatProvider).messages.first;

      notifier.skipApproval('a1');

      final afterMsg = container.read(agenticChatProvider).messages.first;
      expect(identical(beforeMsg, afterMsg), isFalse);
    });

    test('skipApproval does not affect other approvals', () {
      final a1 = _pendingApproval('a1');
      final a2 = _pendingApproval('a2');
      final message = _systemMessageWithApprovals([a1, a2]);
      notifier.setStateForTest(AgenticChatState(messages: [message]));

      notifier.skipApproval('a1');

      final approvals = container.read(agenticChatProvider).messages.first.approvals!;
      expect(approvals[0].resolution, ApprovalResolution.skipped);
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
  });
}

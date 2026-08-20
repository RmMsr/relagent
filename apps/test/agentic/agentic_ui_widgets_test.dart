import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/agentic/models.dart';
import 'package:relagent/agentic/widgets.dart';
import 'package:relagent/providers/voice_service_provider.dart';
import 'package:relagent/voice/voice_service.dart';
import 'package:relagent/widgets/message_markdown_actions.dart';

class _FakeVoiceCapabilities implements VoiceCapabilities {
  @override
  bool get isAsrAvailable => false;
  @override
  bool get isTtsAvailable => false;
  @override
  bool get isBackgroundListeningAvailable => false;

  @override
  bool get isInputSelectionAvailable => false;
}

AgenticMessage _settledUserMsg() => AgenticMessage(
      messageId: 'seed-user',
      localId: 'seed-user',
      text: 'seed',
      role: AgenticRole.user,
      isFinal: true,
    );

Widget _wrapWithProviders(Widget child) {
  return ProviderScope(
    overrides: [
      voiceCapabilitiesProvider.overrideWithValue(_FakeVoiceCapabilities()),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

ApprovalData _pending(String id) => ApprovalData(
      id: id,
      type: ApprovalType.outgoingData,
      purpose: 'p',
    );

ApprovalData _granted(String id) => ApprovalData(
      id: id,
      type: ApprovalType.outgoingData,
      purpose: 'p',
      resolution: ApprovalResolution.granted,
    );

AgenticMessage _systemAction({
  required List<ApprovalData> approvals,
  required bool isFinal,
  bool isStale = false,
}) {
  return AgenticMessage(
    messageId: 'sys-$isFinal-$isStale',
    localId: 'sys-$isFinal-$isStale',
    text: '',
    role: AgenticRole.system,
    approvals: approvals,
    isFinal: isFinal,
    isStale: isStale,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ApprovalCard — Continue without button', () {
    testWidgets('renders "Continue without" instead of "Skip"',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalCard(
            approval: _pending('a1'),
            sessionSensitivity: SensitivityLevel.openInformation,
          ),
        ),
      );

      expect(find.text('Continue without'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Grant'), findsOneWidget);
    });

    testWidgets('Continue without invokes onDecline with the approval id',
        (tester) async {
      String? declinedId;
      await tester.pumpWidget(
        _wrap(
          ApprovalCard(
            approval: _pending('a-xyz'),
            sessionSensitivity: SensitivityLevel.openInformation,
            onDecline: (id) => declinedId = id,
          ),
        ),
      );

      await tester.tap(find.text('Continue without'));
      await tester.pump();

      expect(declinedId, 'a-xyz');
    });
  });

  group('ApprovalGroup — cycle-level Stop bar visibility', () {
    final stopBarFinder = find.byKey(const Key('approval-group-stop-bar'));

    testWidgets('shows Stop bar when SystemAction is in-flight (final=false)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(approvals: [_pending('a1')], isFinal: false),
            sessionSensitivity: SensitivityLevel.openInformation,
            onStop: () {},
          ),
        ),
      );

      expect(stopBarFinder, findsOneWidget);
    });

    testWidgets('hides Stop bar when SystemAction is settled (final=true)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(approvals: [_pending('a1')], isFinal: true),
            sessionSensitivity: SensitivityLevel.openInformation,
            onStop: () {},
          ),
        ),
      );

      expect(stopBarFinder, findsNothing);
    });

    testWidgets('hides Stop bar when group is not actionable',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(approvals: [_pending('a1')], isFinal: false),
            sessionSensitivity: SensitivityLevel.openInformation,
            isActionable: false,
            onStop: () {},
          ),
        ),
      );

      expect(stopBarFinder, findsNothing);
    });

    testWidgets('hides Stop bar when message is stale', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(
              approvals: [_pending('a1')],
              isFinal: false,
              isStale: true,
            ),
            sessionSensitivity: SensitivityLevel.openInformation,
            onStop: () {},
          ),
        ),
      );

      expect(stopBarFinder, findsNothing);
    });

    testWidgets('hides Stop bar when no onStop handler is wired',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(approvals: [_pending('a1')], isFinal: false),
            sessionSensitivity: SensitivityLevel.openInformation,
          ),
        ),
      );

      expect(stopBarFinder, findsNothing);
    });

    testWidgets('Stop bar tap invokes onStop', (tester) async {
      var stopCalls = 0;
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(approvals: [_pending('a1')], isFinal: false),
            sessionSensitivity: SensitivityLevel.openInformation,
            onStop: () => stopCalls++,
          ),
        ),
      );

      await tester.tap(stopBarFinder);
      await tester.pump();

      expect(stopCalls, 1);
    });

    testWidgets('Stop bar uses the "Stop and ask something else" label',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(approvals: [_pending('a1')], isFinal: false),
            sessionSensitivity: SensitivityLevel.openInformation,
            onStop: () {},
          ),
        ),
      );

      expect(find.text('Stop and ask something else'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets(
        'shows Continue button when stuck (in-flight, all decided, no run)',
        (tester) async {
      var continueCalls = 0;
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(
              approvals: [_granted('a1')],
              isFinal: false,
            ),
            sessionSensitivity: SensitivityLevel.openInformation,
            onContinue: () => continueCalls++,
          ),
        ),
      );

      final btn = find.byKey(const Key('approval-group-continue-button'));
      expect(btn, findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(btn);
      await tester.pump();
      expect(continueCalls, 1);
    });

    testWidgets('hides Continue button while an agent run is in flight',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(
              approvals: [_granted('a1')],
              isFinal: false,
            ),
            sessionSensitivity: SensitivityLevel.openInformation,
            isAgentRunInFlight: true,
            onContinue: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('approval-group-continue-button')),
          findsNothing);
    });

    testWidgets('hides Continue button while any approval is undecided',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(
              approvals: [_granted('a1'), _pending('a2')],
              isFinal: false,
            ),
            sessionSensitivity: SensitivityLevel.openInformation,
            onContinue: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('approval-group-continue-button')),
          findsNothing);
    });

    testWidgets('hides Continue button on a settled SystemAction',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message:
                _systemAction(approvals: [_granted('a1')], isFinal: true),
            sessionSensitivity: SensitivityLevel.openInformation,
            onContinue: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('approval-group-continue-button')),
          findsNothing);
    });

    testWidgets('hides Stop bar once any approval has been decided',
        (tester) async {
      // Mixed group: one decided (granted), one still pending. By the user's
      // rule the Stop control should disappear as soon as any decision lands.
      await tester.pumpWidget(
        _wrap(
          ApprovalGroup(
            message: _systemAction(
              approvals: [_granted('a1'), _pending('a2')],
              isFinal: false,
            ),
            sessionSensitivity: SensitivityLevel.openInformation,
            onStop: () {},
          ),
        ),
      );

      expect(stopBarFinder, findsNothing);
    });
  });

  group('QueuedMessageBubble', () {
    testWidgets('renders the queued label, edit pencil, and the text',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          QueuedMessageBubble(text: 'retry it', onEdit: () {}),
        ),
      );

      expect(find.byKey(const Key('queued-message-label')), findsOneWidget);
      expect(find.text('Next user message'), findsOneWidget);
      expect(find.byKey(const Key('queued-message-edit')), findsOneWidget);
      expect(find.text('retry it'), findsOneWidget);
    });

    testWidgets('omits edit pencil when onEdit is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const QueuedMessageBubble(text: 'no-edit'),
        ),
      );

      expect(find.byKey(const Key('queued-message-edit')), findsNothing);
      expect(find.text('Next user message'), findsOneWidget);
    });

    testWidgets('edit pencil tap invokes onEdit', (tester) async {
      var edits = 0;
      await tester.pumpWidget(
        _wrap(
          QueuedMessageBubble(text: 'q', onEdit: () => edits++),
        ),
      );

      await tester.tap(find.byKey(const Key('queued-message-edit')));
      await tester.pump();

      expect(edits, 1);
    });
  });

  group('AgenticChatHistory — queued bubble integration', () {
    testWidgets(
        'renders the queued bubble at the trailing position when set',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: AgenticChatHistory(
              messages: [_settledUserMsg()],
              queuedMessage: 'queued text',
            ),
          ),
        ),
      );

      expect(find.byType(QueuedMessageBubble), findsOneWidget);
      expect(find.text('queued text'), findsOneWidget);
    });

    testWidgets('does not render the queued bubble when queuedMessage is null',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: AgenticChatHistory(
              messages: [
                AgenticMessage(
                  messageId: 'm',
                  localId: 'm',
                  text: 'hello',
                  role: AgenticRole.user,
                  isFinal: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(QueuedMessageBubble), findsNothing);
    });

    testWidgets('forwards onEditQueued to the queued bubble', (tester) async {
      var edits = 0;
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: AgenticChatHistory(
              messages: [_settledUserMsg()],
              queuedMessage: 'q',
              onEditQueued: () => edits++,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('queued-message-edit')));
      await tester.pump();

      expect(edits, 1);
    });
  });

  group('AgenticChatInput — input disable wiring', () {
    testWidgets('TextField is disabled and send button has no handler when '
        'enabled=false', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          AgenticChatInput(enabled: false, onSubmitted: (_) {}),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
      expect(
        textField.decoration?.hintText,
        'Wait for response or edit queued message',
      );

      final sendBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send),
      );
      expect(sendBtn.onPressed, isNull);
    });

    testWidgets('TextField is enabled and send button is wired when '
        'enabled=true', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          AgenticChatInput(enabled: true, onSubmitted: (_) {}),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isTrue);
      expect(textField.decoration?.hintText, 'Type a message...');

      final sendBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send),
      );
      expect(sendBtn.onPressed, isNotNull);
    });

    testWidgets('setText overwrites the input contents', (tester) async {
      final inputKey = GlobalKey<AgenticChatInputState>();
      String? submitted;
      await tester.pumpWidget(
        _wrapWithProviders(
          AgenticChatInput(
            key: inputKey,
            onSubmitted: (text) => submitted = text,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'old draft');
      inputKey.currentState!.setText('queued recovered');
      await tester.pump();

      expect(find.text('queued recovered'), findsOneWidget);
      expect(find.text('old draft'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      expect(submitted, 'queued recovered');
    });
  });

  group('Message bubble copy button', () {
    testWidgets('user message bubble has no copy button', (tester) async {
      await tester.pumpWidget(_wrap(AgenticChatHistory(
        messages: [_settledUserMsg()],
      )));
      await tester.pump();

      expect(find.byType(MessageCopyButton), findsNothing);
    });

    testWidgets('assistant message bubble still has a copy button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(AgenticChatHistory(
        messages: [
          AgenticMessage(
            messageId: 'a1',
            localId: 'a1',
            text: 'hi there',
            role: AgenticRole.assistant,
            isFinal: true,
          ),
        ],
      )));
      await tester.pump();

      expect(find.byType(MessageCopyButton), findsOneWidget);
    });
  });

  group('Agent stats row — long answering model name', () {
    testWidgets(
        'does not overflow the message bubble when the model name is long',
        (tester) async {
      final message = AgenticMessage(
        messageId: 'm1',
        localId: 'l1',
        text: 'Hello there',
        role: AgenticRole.assistant,
        stats: const AgentStats(
          answeringModelName:
              'openrouter/anthropic/claude-3.7-sonnet-thinking-extended-context-preview',
          inputTokens: 120,
          outputTokens: 45,
        ),
        isFinal: true,
      );

      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 360, // narrow phone-width bubble
            child: AgenticChatHistory(messages: [message]),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.insights));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

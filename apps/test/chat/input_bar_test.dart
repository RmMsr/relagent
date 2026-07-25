import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/agentic/widgets.dart';
import 'package:relagent/chat/widgets.dart';
import 'package:relagent/theme/app_colors.dart';
import 'package:relagent/providers/voice_service_provider.dart';
import 'package:relagent/voice/voice_service.dart';

class _NoVoice with VoiceCapabilities {
  @override
  bool get isAsrAvailable => false;
  @override
  bool get isTtsAvailable => false;
  @override
  bool get isBackgroundListeningAvailable => false;

  @override
  bool get isInputSelectionAvailable => false;
}

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    voiceCapabilitiesProvider.overrideWithValue(_NoVoice()),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
);

void _verifySendIsRightmost(WidgetTester tester) {
  final sendFinder = find.byIcon(Icons.send);
  expect(sendFinder, findsOneWidget);

  final sendPos = tester.getCenter(sendFinder);

  final micFinder = find.byIcon(Icons.mic);
  if (micFinder.evaluate().isNotEmpty) {
    final micPos = tester.getCenter(micFinder);
    expect(sendPos.dx, greaterThan(micPos.dx), reason: 'Send must be right of mic button');
  }
}

void main() {
  testWidgets('send button is rightmost in ChatInput row', (tester) async {
    await tester.pumpWidget(_wrap(ChatInput(onSubmitted: (_) {})));
    await tester.pumpAndSettle();
    _verifySendIsRightmost(tester);
  });

  testWidgets('send button is rightmost in AgenticChatInput row', (tester) async {
    await tester.pumpWidget(_wrap(AgenticChatInput(onSubmitted: (_) {}, enabled: true)));
    await tester.pumpAndSettle();
    _verifySendIsRightmost(tester);
  });
}

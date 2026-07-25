import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/agentic/widgets.dart';
import 'package:relagent/chat/widgets.dart';
import 'package:relagent/speech_recognition/recording_target.dart';
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
  overrides: [voiceCapabilitiesProvider.overrideWithValue(_NoVoice())],
  child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
);

String _fieldText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText).first).controller.text;

/// Drives two growing partials of a single utterance with a simulated IME
/// echo in between, and asserts the second partial REPLACES the first rather
/// than appending to it. Regression for streaming/online ASR text repetition:
/// a focused, IME-connected field echoes its editing value back to the
/// controller after the synchronous write, which previously moved the
/// dictation baseline so every partial accumulated ("HalloHallo, ...").
Future<void> _runPartialsReplaceScenario(
  WidgetTester tester,
  Finder inputFinder,
  RecordingTarget target,
) async {
  final controller =
      tester.widget<EditableText>(find.byType(EditableText).first).controller;

  target.onRecordingStarted();
  await tester.pump();

  target.onTextRecognized('Hallo');
  await tester.pump();

  // Simulate the device: focused field echoes its value back a frame later,
  // firing the controller listener outside any synchronous guard window.
  controller.value = TextEditingValue(text: controller.text);
  await tester.pump();

  target.onTextRecognized('Hallo, das ist ein Test');
  await tester.pump();

  expect(
    _fieldText(tester),
    'Hallo, das ist ein Test',
    reason: 'Each partial must replace the previous, not append to it',
  );
}

void main() {
  testWidgets('ChatInput: growing partials replace, not accumulate', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(ChatInput(onSubmitted: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final target =
        tester.state<ChatInputState>(find.byType(ChatInput)) as RecordingTarget;
    await _runPartialsReplaceScenario(tester, find.byType(ChatInput), target);
  });

  testWidgets('AgenticChatInput: growing partials replace, not accumulate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AgenticChatInput(onSubmitted: (_) {}, enabled: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final target =
        tester.state<AgenticChatInputState>(find.byType(AgenticChatInput))
            as RecordingTarget;
    await _runPartialsReplaceScenario(
      tester,
      find.byType(AgenticChatInput),
      target,
    );
  });
}

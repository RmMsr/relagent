import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:relagent/chat/models.dart';
import 'package:relagent/chat/widgets.dart';
import 'package:relagent/providers/tts_provider.dart';
import 'package:relagent/theme/app_colors.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
);

ChatMessage _msg(ChatRole role, String text) => ChatMessage(
  text,
  id: 'test-id',
  role: role,
  timestamp: DateTime(2026),
);

void main() {
  testWidgets('user message bubble has outline border and no fill', (tester) async {
    await tester.pumpWidget(_wrap(ChatMessageBubble(message: _msg(ChatRole.user, 'hello'))));
    await tester.pump();

    final outlineColor = Theme.of(tester.element(find.byType(ChatMessageBubble))).colorScheme.outline;
    final containers = tester.widgetList<Container>(find.byType(Container)).toList();
    final bubble = containers.firstWhere(
      (c) {
        final deco = c.decoration as BoxDecoration?;
        final border = deco?.border as Border?;
        return border?.top.color == outlineColor;
      },
      orElse: () => throw TestFailure('No container with outline border found'),
    );
    final deco = bubble.decoration as BoxDecoration;
    expect(deco.color, isNull, reason: 'User bubble must have no fill');
  });

  testWidgets('assistant message has no bubble decoration', (tester) async {
    await tester.pumpWidget(_wrap(ChatMessageBubble(message: _msg(ChatRole.assistant, 'hi'))));
    await tester.pump();

    final colorScheme = Theme.of(tester.element(find.byType(ChatMessageBubble))).colorScheme;
    final containers = tester.widgetList<Container>(find.byType(Container)).toList();
    final hasBubble = containers.any((c) {
      final deco = c.decoration as BoxDecoration?;
      final border = deco?.border as Border?;
      return border?.top.color == colorScheme.outline ||
          deco?.color == colorScheme.primaryContainer;
    });
    expect(hasBubble, isFalse, reason: 'Assistant has no bubble decoration');
  });

  testWidgets('error message uses errorBg and left border', (tester) async {
    await tester.pumpWidget(_wrap(ChatMessageBubble(message: _msg(ChatRole.error, 'oops'))));
    await tester.pump();

    final containers = tester.widgetList<Container>(find.byType(Container)).toList();
    final anchor = containers.firstWhere(
      (c) {
        final deco = c.decoration as BoxDecoration?;
        return deco?.color == RelagentColors.errorBg;
      },
      orElse: () => throw TestFailure('No container with errorBg found'),
    );
    final deco = anchor.decoration as BoxDecoration;
    final border = deco.border as Border?;
    expect(border?.left.width, 4.0);
    expect(border?.left.color, RelagentColors.errorBorder);
  });

  testWidgets('idle assistant message shows a single speak button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ChatMessageBubble(
          message: _msg(ChatRole.assistant, 'hi'),
          onSpeak: (_, _) {},
          getMessageTtsState: (_) => const MessageTtsState(status: MessagePlaybackStatus.idle),
          onSkipPrevious: (_) {},
          onSkipNext: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsNothing);
    expect(find.byIcon(Icons.skip_next), findsNothing);
  });

  testWidgets(
    'playing assistant message shows back/pause/forward controls',
    (tester) async {
      String? skippedPrevious;
      String? skippedNext;

      await tester.pumpWidget(
        _wrap(
          ChatMessageBubble(
            message: _msg(ChatRole.assistant, 'hi'),
            onSpeak: (_, _) {},
            getMessageTtsState: (_) => const MessageTtsState(status: MessagePlaybackStatus.playing),
            onSkipPrevious: (id) => skippedPrevious = id,
            onSkipNext: (id) => skippedNext = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);

      await tester.tap(find.byIcon(Icons.skip_previous));
      await tester.tap(find.byIcon(Icons.skip_next));

      expect(skippedPrevious, 'test-id');
      expect(skippedNext, 'test-id');
    },
  );

  testWidgets('paused assistant message shows a resume icon in the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ChatMessageBubble(
          message: _msg(ChatRole.assistant, 'hi'),
          onSpeak: (_, _) {},
          getMessageTtsState: (_) => const MessageTtsState(status: MessagePlaybackStatus.paused),
          onSkipPrevious: (_) {},
          onSkipNext: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });

  testWidgets(
    'highlights only the paragraph matching currentSourceParagraphIndex',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ChatMessageBubble(
            message: _msg(ChatRole.assistant, 'Para one.\n\nPara two.'),
            onSpeak: (_, _) {},
            getMessageTtsState: (_) => const MessageTtsState(
              status: MessagePlaybackStatus.playing,
              currentSourceParagraphIndex: 1,
            ),
            onSkipPrevious: (_) {},
            onSkipNext: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdownWidgets = find.byType(GptMarkdown);
      expect(markdownWidgets, findsNWidgets(2));

      Decoration? decorationFor(int index) {
        final container = tester.widget<Container>(
          find
              .ancestor(
                of: markdownWidgets.at(index),
                matching: find.byType(Container),
              )
              .first,
        );
        return container.decoration;
      }

      expect(decorationFor(0), isNull);
      expect(decorationFor(1), isNotNull);
    },
  );

  testWidgets('no paragraph is highlighted when not focused', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChatMessageBubble(
          message: _msg(ChatRole.assistant, 'Para one.\n\nPara two.'),
          onSpeak: (_, _) {},
          getMessageTtsState: (_) => const MessageTtsState(
            status: MessagePlaybackStatus.completed,
            currentSourceParagraphIndex: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final markdownWidgets = find.byType(GptMarkdown);
    for (var i = 0; i < 2; i++) {
      final container = tester.widget<Container>(
        find
            .ancestor(
              of: markdownWidgets.at(i),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.decoration, isNull);
    }
  });
}

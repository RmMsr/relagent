import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/chat/models.dart';
import 'package:relagent/chat/widgets.dart';
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
}

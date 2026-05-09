import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/theme/app_colors.dart';

void main() {
  group('RelagentColors', () {
    test('primaryIndigo is correct', () {
      expect(RelagentColors.primaryIndigo, const Color(0xFF283593));
    });
    test('indigoTint is correct', () {
      expect(RelagentColors.indigoTint, const Color(0xFFE8EAF6));
    });
    test('errorBg differs from errorBorder', () {
      expect(RelagentColors.errorBg, isNot(equals(RelagentColors.errorBorder)));
    });
    test('dark errorBg differs from light errorBg', () {
      expect(RelagentColors.errorBgDark, isNot(equals(RelagentColors.errorBg)));
    });
  });

  group('AppTheme', () {
    test('light theme uses Material 3', () {
      expect(AppTheme.light().useMaterial3, isTrue);
    });
    test('dark theme has dark brightness', () {
      expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
    });
    test('light theme has different brightness to dark', () {
      expect(
        AppTheme.light().colorScheme.brightness,
        isNot(AppTheme.dark().colorScheme.brightness),
      );
    });
  });

  group('RelagentThemeExtension', () {
    testWidgets('errorBg returns dark value in dark theme', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (c) { ctx = c; return const SizedBox(); }),
      ));
      expect(ctx.errorBg, RelagentColors.errorBgDark);
    });
    testWidgets('errorBg returns light value in light theme', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(builder: (c) { ctx = c; return const SizedBox(); }),
      ));
      expect(ctx.errorBg, RelagentColors.errorBg);
    });
  });
}

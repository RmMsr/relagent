import 'package:flutter/material.dart';

abstract final class RelagentColors {
  // Primary palette
  static const Color primaryIndigo = Color(0xFF283593);
  static const Color indigoMid = Color(0xFF5C6BC0);
  static const Color indigoTint = Color(0xFFE8EAF6);
  static const Color indigoBorder = Color(0xFFC5CAE9);

  // Surfaces
  static const Color backgroundGrey = Color(0xFFF8F9FA);
  static const Color divider = Color(0xFFE8EAED);

  // Text
  static const Color primaryText = Color(0xFF1A1A1A);
  static const Color secondaryText = Color(0xFF5F6368);
  static const Color toggleOffMuted = Color(0xFFB0BEC5);

  // Semantic — light
  static const Color approvalBg = Color(0xFFE8EAF6);
  static const Color approvalBorder = Color(0xFF5C6BC0);

  static const Color errorBg = Color(0xFFFFEBEE);
  static const Color errorBorder = Color(0xFFEF9A9A);
  static const Color errorText = Color(0xFFB71C1C);

  static const Color noteBg = Color(0xFFE8F5E9);
  static const Color noteBorder = Color(0xFFA5D6A7);
  static const Color noteText = Color(0xFF1B5E20);

  // Semantic — dark
  static const Color approvalBgDark = Color(0xFF1A237E);
  static const Color approvalBorderDark = Color(0xFF7986CB);

  static const Color errorBgDark = Color(0xFF311919);
  static const Color errorBorderDark = Color(0xFFEF5350);
  static const Color errorTextDark = Color(0xFFEF9A9A);

  static const Color noteBgDark = Color(0xFF1B3A1F);
  static const Color noteBorderDark = Color(0xFF81C784);
  static const Color noteTextDark = Color(0xFFA5D6A7);

  // Dark surfaces
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceDarkLow = Color(0xFF252525);
  static const Color dividerDark = Color(0xFF333333);
}

abstract final class AppTheme {
  static const double chatContentMaxWidth = 800;

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RelagentColors.primaryIndigo,
      surface: RelagentColors.backgroundGrey,
    ),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RelagentColors.primaryIndigo,
      brightness: Brightness.dark,
      surface: RelagentColors.backgroundDark,
    ),
  );
}

extension RelagentThemeExtension on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  Color get approvalBg =>
      _isDark ? RelagentColors.approvalBgDark : RelagentColors.approvalBg;
  Color get approvalBorder => _isDark
      ? RelagentColors.approvalBorderDark
      : RelagentColors.approvalBorder;
  Color get errorBg =>
      _isDark ? RelagentColors.errorBgDark : RelagentColors.errorBg;
  Color get errorBorder =>
      _isDark ? RelagentColors.errorBorderDark : RelagentColors.errorBorder;
  Color get errorText =>
      _isDark ? RelagentColors.errorTextDark : RelagentColors.errorText;
  Color get noteBg =>
      _isDark ? RelagentColors.noteBgDark : RelagentColors.noteBg;
  Color get noteBorder =>
      _isDark ? RelagentColors.noteBorderDark : RelagentColors.noteBorder;
  Color get noteText =>
      _isDark ? RelagentColors.noteTextDark : RelagentColors.noteText;
}

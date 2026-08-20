import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/theme/app_colors.dart';
import 'package:relagent/widgets/voice_mode_selector.dart';

// Full settings JSON required by Settings.fromJson (simpleChatBaseUrl and
// simpleChatModel are non-nullable String fields).
const _base =
    '"simpleChatBaseUrl":"http://localhost:1234","simpleChatModel":"test"';

String _settingsJson({
  required String voiceMode,
  required bool continuousVoiceEnabled,
}) =>
    '{$_base,"voiceMode":"$voiceMode","continuousVoiceEnabled":$continuousVoiceEnabled}';

Widget _wrap(Widget child, SharedPreferences prefs) => ProviderScope(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(appBar: AppBar(actions: [child])),
  ),
);

void main() {
  testWidgets('mic icon appears when continuous recording is on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_settings': _settingsJson(
        voiceMode: 'listening',
        continuousVoiceEnabled: true,
      ),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_wrap(const VoiceModeSelector(), prefs));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsNothing);
  });

  testWidgets('mic_off icon appears when continuous recording is off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_settings': _settingsJson(
        voiceMode: 'silent',
        continuousVoiceEnabled: false,
      ),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_wrap(const VoiceModeSelector(), prefs));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
  });

  testWidgets('ON toggle button has primaryContainer background', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_settings': _settingsJson(
        voiceMode: 'listening',
        continuousVoiceEnabled: true,
      ),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_wrap(const VoiceModeSelector(), prefs));
    await tester.pumpAndSettle();

    final micButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.mic),
        matching: find.byType(IconButton),
      ),
    );
    final colorScheme = Theme.of(
      tester.element(find.byIcon(Icons.mic)),
    ).colorScheme;
    final bg = micButton.style?.backgroundColor?.resolve({});
    expect(bg, colorScheme.primaryContainer);
  });
}

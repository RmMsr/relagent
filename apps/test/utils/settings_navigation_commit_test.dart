import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/pending_settings_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/utils/settings_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'commitPendingSettings writes changed staged fields to settingsProvider',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_settings':
            '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","selectedBackend":"relagentEngine"}',
      });
      final sharedPreferences = await SharedPreferences.getInstance();

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // Stage changes to the two remaining bulk-committed fields.
      capturedRef.read(pendingSettingsProvider.notifier).updateDraft(
            (s) => s.copyWith(
              simpleChatModel: 'new-model',
              primeMessage: 'new prime message',
            ),
          );

      await commitPendingSettings(capturedRef);
      await tester.pump();

      final settings = capturedRef.read(settingsProvider);
      expect(settings.simpleChatModel, 'new-model');
      expect(settings.primeMessage, 'new prime message');
      // Fields commitPendingSettings no longer touches (now instant-saved
      // elsewhere) stay exactly as loaded.
      expect(settings.selectedBackend, ChatBackendType.relagentEngine);
    },
  );

  testWidgets(
    'commitPendingSettings writes engineBaseUrl when it changed',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_settings':
            '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","engineBaseUrl":"http://localhost:8000"}',
      });
      final sharedPreferences = await SharedPreferences.getInstance();

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      capturedRef.read(pendingSettingsProvider.notifier).updateDraft(
            (s) => s.copyWith(engineBaseUrl: 'http://localhost:9000'),
          );

      await commitPendingSettings(capturedRef);
      await tester.pump();

      expect(
        capturedRef.read(settingsProvider).engineBaseUrl,
        'http://localhost:9000',
      );
    },
  );

  testWidgets(
    'commitPendingSettings leaves engineBaseUrl untouched when unchanged',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_settings':
            '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","engineBaseUrl":"http://localhost:8000"}',
      });
      final sharedPreferences = await SharedPreferences.getInstance();

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // Stage an unrelated field only — engineBaseUrl stays whatever the
      // draft was seeded with, i.e. unchanged from settingsProvider.
      capturedRef.read(pendingSettingsProvider.notifier).updateDraft(
            (s) => s.copyWith(simpleChatModel: 'new-model'),
          );

      await commitPendingSettings(capturedRef);
      await tester.pump();

      expect(
        capturedRef.read(settingsProvider).engineBaseUrl,
        'http://localhost:8000',
      );
    },
  );
}

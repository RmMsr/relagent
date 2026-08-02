import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/pending_settings_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_settings':
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","selectedAsrModelId":"asr-saved","selectedTtsModelId":"tts-saved"}',
    });
    final sharedPreferences = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('build seeds the draft from current settings', () {
    final draft = container.read(pendingSettingsProvider);
    expect(draft.selectedAsrModelId, 'asr-saved');
    expect(draft.simpleChatModel, 'test-model');
  });

  test('updateDraft applies a partial change, leaving the rest untouched', () {
    container.read(pendingSettingsProvider.notifier).updateDraft(
          (s) => s.copyWith(selectedAsrModelId: 'asr-new'),
        );
    final draft = container.read(pendingSettingsProvider);
    expect(draft.selectedAsrModelId, 'asr-new');
    expect(draft.selectedTtsModelId, 'tts-saved');
    expect(draft.simpleChatModel, 'test-model');
  });

  test('discardPending drops a pending edit and resyncs to current settings', () {
    container.read(pendingSettingsProvider.notifier).updateDraft(
          (s) => s.copyWith(simpleChatModel: 'edited-model'),
        );
    expect(container.read(pendingSettingsProvider).simpleChatModel, 'edited-model');

    container.read(pendingSettingsProvider.notifier).discardPending();

    expect(container.read(pendingSettingsProvider).simpleChatModel, 'test-model');
  });

  test('automatically resyncs when settingsProvider changes externally (e.g. after Save)', () async {
    await container
        .read(settingsProvider.notifier)
        .updateSelectedTtsModelId('tts-changed-elsewhere');
    final draft = container.read(pendingSettingsProvider);
    expect(draft.selectedTtsModelId, 'tts-changed-elsewhere');
  });

  test('draft equals settings when nothing is pending, for dirty-checking', () {
    final draft = container.read(pendingSettingsProvider);
    final settings = container.read(settingsProvider);
    expect(draft, settings);
  });

  test('draft differs from settings once something is pending', () {
    container.read(pendingSettingsProvider.notifier).updateDraft(
          (s) => s.copyWith(ttsSpeed: 1.5),
        );
    final draft = container.read(pendingSettingsProvider);
    final settings = container.read(settingsProvider);
    expect(draft == settings, isFalse);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/voice/model_download_service.dart';
import 'package:relagent/widgets/model_management_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reports a fixed set of models as downloaded, no async filesystem I/O.
class _FakeModelDownloadService extends ModelDownloadService {
  final Set<String> downloaded;
  _FakeModelDownloadService(this.downloaded);

  @override
  Future<Set<String>> listDownloadedModels() async => downloaded;

  @override
  Future<int> totalStorageUsed() async => 0;

  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {}

  @override
  void cancelDownload(String modelId) {}

  @override
  Future<void> deleteModel(String modelId) async {}
}

const _kokoroEn = 'kokoro-en-v0_19-int8';
const _piperDe = 'piper-de-thorsten-medium-int8';

Future<ProviderContainer> _pumpBrowser(
  WidgetTester tester, {
  Set<String> downloaded = const {_kokoroEn, _piperDe},
  ModelType type = ModelType.tts,
  String searchQuery = '',
}) async {
  // Tall enough that every catalog TTS card fits without scrolling —
  // ListView.builder never builds (and find.text can't see) an item
  // positioned past the viewport.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Real file I/O must run inside runAsync — the automated test binding's
  // fake clock otherwise deadlocks waiting on it.
  await tester.runAsync(() async {
    final fixture = await File(
      'test/fixtures/voice-models.json',
    ).readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  SharedPreferences.setMockInitialValues({
    'user_settings':
        '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour"}',
  });
  final sharedPreferences = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      modelDownloadServiceProvider.overrideWithValue(
        _FakeModelDownloadService(downloaded),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ModelCatalogBrowser(initialType: type)),
    ),
  );
  await tester.pump();

  if (searchQuery.isNotEmpty) {
    await tester.enterText(find.byType(TextField), searchQuery);
    await tester.pump();
  }

  return container;
}

void main() {
  group('Model catalog browser — TTS language controls', () {
    testWidgets(
      'checking the checkbox assigns the model to its language',
      (tester) async {
        final container = await _pumpBrowser(tester);

        final checkbox = find.byType(Checkbox).first;
        await tester.tap(checkbox);
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.ttsLanguagePreferences['en'], _kokoroEn);
      },
    );

    testWidgets(
      'unchecking the checkbox removes the assignment',
      (tester) async {
        final container = await _pumpBrowser(tester);
        await container
            .read(settingsProvider.notifier)
            .assignTtsModelToLanguage('en', _kokoroEn);
        await tester.pump();

        final checkbox = find.byType(Checkbox).first;
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);

        await tester.tap(checkbox);
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.ttsLanguagePreferences.containsKey('en'), isFalse);
      },
    );

    testWidgets('tapping the wildcard marks the model as default', (
      tester,
    ) async {
      final container = await _pumpBrowser(tester);

      await tester.tap(find.byIcon(Icons.star_border).first);
      await tester.pump();

      final settings = container.read(settingsProvider);
      expect(settings.defaultTtsModelId, isNotNull);
    });

    testWidgets(
      'tapping the wildcard again on the default model clears it',
      (tester) async {
        final container = await _pumpBrowser(tester);
        await container
            .read(settingsProvider.notifier)
            .setDefaultTtsModel(_kokoroEn);
        await tester.pump();

        // Catalog entries also show a plain (non-interactive) star badge for
        // "recommended" models, so target the wildcard button specifically
        // by its tooltip rather than by icon (which the badge shares).
        final wildcardButton = find.byTooltip('Remove as default TTS voice');
        expect(wildcardButton, findsOneWidget);

        await tester.tap(wildcardButton);
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.defaultTtsModelId, isNull);
      },
    );

    testWidgets(
      '"Selected" filter shows only assigned/default models',
      (tester) async {
        await _pumpBrowser(tester);

        // Both downloaded TTS models are visible before filtering.
        expect(find.text('English - Kokoro'), findsOneWidget);
        expect(find.text('German - Thorsten'), findsOneWidget);

        await _chooseFilter(tester, 'Selected');

        // Nothing is assigned/default yet — the list is empty.
        expect(find.text('English - Kokoro'), findsNothing);
        expect(find.text('German - Thorsten'), findsNothing);
      },
    );

    testWidgets(
      '"Selected" filter shows a model once it is assigned',
      (tester) async {
        final container = await _pumpBrowser(tester);
        await container
            .read(settingsProvider.notifier)
            .setDefaultTtsModel(_kokoroEn);
        await tester.pump();

        await _chooseFilter(tester, 'Selected');

        expect(find.text('English - Kokoro'), findsOneWidget);
        expect(find.text('German - Thorsten'), findsNothing);
      },
    );
  });

  group('Model catalog browser — ASR quick-pick controls', () {
    const zipformerEn = 'zipformer-en-kroko';
    const zipformerDe = 'zipformer-de-kroko';
    const parakeetMulti = 'nemo-parakeet-tdt-0.6b-v3-int8';
    const omnilingual = 'omnilingual-asr-300m-ctc-int8';

    testWidgets(
      'checking the quick-pick checkbox enables a single-language model',
      (tester) async {
        final container = await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {zipformerEn},
          searchQuery: 'zipformer-en',
        );

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.asrQuickPickModelIds, [zipformerEn]);
      },
    );

    testWidgets(
      'a multi-language model gets the exact same single checkbox, no per-language chips',
      (tester) async {
        final container = await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {parakeetMulti},
          searchQuery: 'parakeet',
        );

        // One checkbox, regardless of the model declaring 25 languages —
        // and no per-language chips at all, unlike TTS.
        expect(find.byType(Checkbox), findsOneWidget);
        expect(find.byType(FilterChip), findsNothing);

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.asrQuickPickModelIds, [parakeetMulti]);
      },
    );

    testWidgets(
      'the unenumerable "multi" sentinel model still gets a quick-pick checkbox',
      (tester) async {
        final container = await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {omnilingual},
          searchQuery: 'omnilingual',
        );

        expect(find.byType(Checkbox), findsOneWidget);
        expect(find.byType(FilterChip), findsNothing);

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.asrQuickPickModelIds, [omnilingual]);
      },
    );

    testWidgets(
      'unchecking the quick-pick checkbox disables the model',
      (tester) async {
        final container = await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {zipformerEn},
          searchQuery: 'zipformer-en',
        );
        await container
            .read(settingsProvider.notifier)
            .setAsrQuickPickEnabled(zipformerEn, true);
        await tester.pump();

        final checkbox = find.byType(Checkbox).first;
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);

        await tester.tap(checkbox);
        await tester.pump();

        final settings = container.read(settingsProvider);
        expect(settings.asrQuickPickModelIds, isEmpty);
      },
    );

    testWidgets(
      'the default star works the same way it does for TTS',
      (tester) async {
        final container = await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {zipformerEn},
          searchQuery: 'zipformer-en',
        );

        await tester.tap(find.byIcon(Icons.star_border).first);
        await tester.pump();

        var settings = container.read(settingsProvider);
        expect(settings.defaultAsrModelId, zipformerEn);

        final wildcardButton = find.byTooltip('Remove as default ASR model');
        await tester.tap(wildcardButton);
        await tester.pump();

        settings = container.read(settingsProvider);
        expect(settings.defaultAsrModelId, isNull);
      },
    );

    testWidgets(
      'no Select button, checkmark, or whole-card tap exists on ASR cards',
      (tester) async {
        await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {zipformerEn, zipformerDe},
        );

        expect(find.text('Select'), findsNothing);
        expect(find.byIcon(Icons.check_circle), findsNothing);
      },
    );

    testWidgets(
      '"Selected" filter picks up quick-pick and default ASR models',
      (tester) async {
        final container = await _pumpBrowser(
          tester,
          type: ModelType.asr,
          downloaded: {zipformerEn, zipformerDe},
        );

        await _chooseFilter(tester, 'Selected');
        expect(find.text('English - Zipformer'), findsNothing);
        expect(find.text('German - Zipformer'), findsNothing);

        await container
            .read(settingsProvider.notifier)
            .setAsrQuickPickEnabled(zipformerEn, true);
        await tester.pump();

        expect(find.text('English - Zipformer'), findsOneWidget);
        expect(find.text('German - Zipformer'), findsNothing);
      },
    );
  });
}

/// Opens the All/Downloaded/Selected dropdown and picks [label]. The
/// dropdown's value type is a private enum, so match by predicate rather
/// than a concrete generic `DropdownButton<...>` type.
Future<void> _chooseFilter(WidgetTester tester, String label) async {
  await tester.tap(find.byWidgetPredicate((w) => w is DropdownButton));
  await tester.pump();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

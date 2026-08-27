import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/providers/recording_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/voice_service_provider.dart';
import 'package:relagent/speech_recognition/mic_selection_widgets.dart';
import 'package:relagent/speech_recognition/widgets.dart';
import 'package:relagent/voice/model_download_service.dart';
import 'package:relagent/voice/voice_service.dart';
import 'package:relagent/voice/voice_service_stub.dart';
import 'package:relagent/widgets/voice_mode_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _zipformerDe = 'zipformer-de-kroko';
const _zipformerFr = 'zipformer-fr-kroko';

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

const _builtin = MicDevice(
  id: 1,
  category: MicDeviceCategory.builtin,
  name: 'Phone microphone',
);
const _bluetooth = MicDevice(
  id: 3,
  category: MicDeviceCategory.bluetooth,
  name: 'BT Headset',
  address: 'AA:BB',
);

class _FakeVoiceService extends NoOpVoiceService {
  final deviceEvents = StreamController<void>.broadcast();
  MicPreference? lastPreference;
  MicSelectionResult selection = const MicSelectionResult(
    MicSelectionStatus.ok,
    _bluetooth,
  );
  bool inputSelectionAvailable = true;

  @override
  bool get isInputSelectionAvailable => inputSelectionAvailable;

  @override
  Future<List<MicDevice>> listInputDevices() async => [_builtin, _bluetooth];

  @override
  void setInputDevicePreference(MicPreference preference) {
    lastPreference = preference;
  }

  @override
  Future<MicSelectionResult> queryInputSelection() async => selection;

  @override
  Stream<void> get deviceChangedEvents => deviceEvents.stream;
}

void main() {
  late _FakeVoiceService voiceService;

  setUpAll(() async {
    final fixture = await File(
      'test/fixtures/voice-models.json',
    ).readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_settings':
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour"}',
    });
    voiceService = _FakeVoiceService();
  });

  Future<void> pumpButton(
    WidgetTester tester, {
    List<String> asrQuickPickModelIds = const [],
    Set<String> downloadedAsrModels = const {},
  }) async {
    // Tall enough that the mic picker's device + model sections both fit
    // without scrolling — the modal sheet's ListView is a sliver and only
    // lazily builds items within the viewport, same as the model catalog
    // browser's ListView.builder.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'user_settings': jsonEncode({
        'simpleChatBaseUrl': 'http://localhost:1234/api/v1',
        'simpleChatModel': 'test-model',
        'primeMessage': 'test',
        'ttsSpeakerId': 0,
        'ttsSpeed': 1.0,
        'voiceMode': 'silent',
        'backgroundListeningDuration': 'oneHour',
        'asrQuickPickModelIds': asrQuickPickModelIds,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          voiceServiceProvider.overrideWithValue(voiceService),
          modelDownloadServiceProvider.overrideWithValue(
            _FakeModelDownloadService(downloadedAsrModels),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RecorderButton())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('button shows Bluetooth badge for active BT input', (
    tester,
  ) async {
    await pumpButton(tester);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
  });

  testWidgets('symbol updates when input falls back to built-in', (
    tester,
  ) async {
    await pumpButton(tester);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);

    voiceService.selection = const MicSelectionResult(
      MicSelectionStatus.ok,
      null,
    );
    voiceService.deviceEvents.add(null);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bluetooth), findsNothing);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('long-press opens picker and pins the chosen device', (
    tester,
  ) async {
    await pumpButton(tester);

    await tester.longPress(find.byType(RecorderButton));
    await tester.pumpAndSettle();

    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Phone microphone'), findsOneWidget);
    expect(find.text('BT Headset'), findsOneWidget);

    await tester.tap(find.text('Phone microphone'));
    await tester.pumpAndSettle();

    // Picker closed, preference pinned and pushed to the voice service.
    expect(find.byType(MicPickerSheet), findsNothing);
    expect(voiceService.lastPreference?.isAuto, false);
    expect(voiceService.lastPreference?.category, MicDeviceCategory.builtin);
  });

  testWidgets('picker marks the current selection', (tester) async {
    await pumpButton(tester);
    await tester.longPress(find.byType(RecorderButton));
    await tester.pumpAndSettle();

    // Default preference is automatic.
    final automaticTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Automatic'),
    );
    expect(automaticTile.trailing, isNotNull);
  });

  testWidgets('unsupported platform: plain mic and long-press is a no-op', (
    tester,
  ) async {
    voiceService.inputSelectionAvailable = false;
    await pumpButton(tester);

    expect(find.byIcon(Icons.bluetooth), findsNothing);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);

    await tester.longPress(find.byType(RecorderButton));
    await tester.pumpAndSettle();
    expect(find.byType(MicPickerSheet), findsNothing);
  });

  group('recognition model quick-pick', () {
    testWidgets(
      'no badge or picker section with fewer than two quick-pick models',
      (tester) async {
        await pumpButton(
          tester,
          asrQuickPickModelIds: [_zipformerDe],
          downloadedAsrModels: {_zipformerDe},
        );

        expect(find.byIcon(Icons.translate), findsNothing);

        await tester.longPress(find.byType(RecorderButton));
        await tester.pumpAndSettle();

        expect(find.text('Recognition Model'), findsNothing);
      },
    );

    testWidgets(
      'badge and picker section appear with two or more quick-pick models',
      (tester) async {
        await pumpButton(
          tester,
          asrQuickPickModelIds: [_zipformerDe, _zipformerFr],
          downloadedAsrModels: {_zipformerDe, _zipformerFr},
        );

        expect(find.byIcon(Icons.translate), findsOneWidget);

        await tester.longPress(find.byType(RecorderButton));
        await tester.pumpAndSettle();

        expect(find.text('Recognition Model'), findsOneWidget);
        expect(find.text('German - Zipformer'), findsOneWidget);
        expect(find.text('French - Zipformer'), findsOneWidget);
      },
    );

    testWidgets(
      'a quick-pick model that is not downloaded is not offered',
      (tester) async {
        await pumpButton(
          tester,
          asrQuickPickModelIds: [_zipformerDe, _zipformerFr],
          downloadedAsrModels: {_zipformerDe},
        );

        // Only one of the two quick-pick entries is actually usable.
        expect(find.byIcon(Icons.translate), findsNothing);
      },
    );

    testWidgets(
      'selecting a model sets a session-only override, not a persisted setting',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({
          'user_settings': jsonEncode({
            'simpleChatBaseUrl': 'http://localhost:1234/api/v1',
            'simpleChatModel': 'test-model',
            'primeMessage': 'test',
            'ttsSpeakerId': 0,
            'ttsSpeed': 1.0,
            'voiceMode': 'silent',
            'backgroundListeningDuration': 'oneHour',
            'asrQuickPickModelIds': [_zipformerDe, _zipformerFr],
          }),
        });
        final prefs = await SharedPreferences.getInstance();

        final testContainer = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            voiceServiceProvider.overrideWithValue(voiceService),
            modelDownloadServiceProvider.overrideWithValue(
              _FakeModelDownloadService({_zipformerDe, _zipformerFr}),
            ),
          ],
        );
        addTearDown(testContainer.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: testContainer,
            child: const MaterialApp(home: Scaffold(body: RecorderButton())),
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.byType(RecorderButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('French - Zipformer'));
        await tester.pumpAndSettle();

        expect(
          testContainer.read(activeAsrModelOverrideProvider),
          _zipformerFr,
        );
        // Settings has no field for the active override at all — it's
        // session-only (design D17), not just unset.
        expect(
          testContainer.read(settingsProvider).toJson().containsKey(
            'activeAsrModelId',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'selecting the already-active model clears the override',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({
          'user_settings': jsonEncode({
            'simpleChatBaseUrl': 'http://localhost:1234/api/v1',
            'simpleChatModel': 'test-model',
            'primeMessage': 'test',
            'ttsSpeakerId': 0,
            'ttsSpeed': 1.0,
            'voiceMode': 'silent',
            'backgroundListeningDuration': 'oneHour',
            'asrQuickPickModelIds': [_zipformerDe, _zipformerFr],
          }),
        });
        final prefs = await SharedPreferences.getInstance();

        final testContainer = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            voiceServiceProvider.overrideWithValue(voiceService),
            modelDownloadServiceProvider.overrideWithValue(
              _FakeModelDownloadService({_zipformerDe, _zipformerFr}),
            ),
          ],
        );
        addTearDown(testContainer.dispose);
        testContainer
            .read(activeAsrModelOverrideProvider.notifier)
            .set(_zipformerFr);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: testContainer,
            child: const MaterialApp(home: Scaffold(body: RecorderButton())),
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.byType(RecorderButton));
        await tester.pumpAndSettle();

        await tester.tap(find.text('French - Zipformer'));
        await tester.pumpAndSettle();

        expect(testContainer.read(activeAsrModelOverrideProvider), isNull);
      },
    );

    testWidgets(
      'long-press still opens the picker for models alone, even without input selection',
      (tester) async {
        voiceService.inputSelectionAvailable = false;
        await pumpButton(
          tester,
          asrQuickPickModelIds: [_zipformerDe, _zipformerFr],
          downloadedAsrModels: {_zipformerDe, _zipformerFr},
        );

        await tester.longPress(find.byType(RecorderButton));
        await tester.pumpAndSettle();

        expect(find.byType(MicPickerSheet), findsOneWidget);
        expect(find.text('Recognition Model'), findsOneWidget);
        expect(find.text('Microphone'), findsNothing);
      },
    );
  });

  group('continuous recording surfaces show the active device', () {
    testWidgets(
      'continuous listening indicator keeps its live icon and badges it',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RecordingStateIndicator(
                recordingState: RecordingState(isRecording: true),
                voiceMode: VoiceMode.listening,
                micCategory: MicDeviceCategory.bluetooth,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
        expect(find.byIcon(Icons.bluetooth), findsOneWidget);
      },
    );

    testWidgets(
      'continuous listening indicator is unbadged for the built-in mic',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RecordingStateIndicator(
                recordingState: RecordingState(isRecording: true),
                voiceMode: VoiceMode.listening,
                micCategory: MicDeviceCategory.builtin,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
        expect(find.byIcon(Icons.bluetooth), findsNothing);
      },
    );

    Future<void> pumpSelector(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'user_settings':
            '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","voiceMode":"listening","continuousVoiceEnabled":true}',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            voiceServiceProvider.overrideWithValue(voiceService),
          ],
          child: const MaterialApp(home: Scaffold(body: VoiceModeSelector())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('continuous recording toggle badges the mic with the device', (
      tester,
    ) async {
      await pumpSelector(tester);

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    });

    testWidgets(
      'continuous recording toggle is unbadged where selection is unsupported',
      (tester) async {
        voiceService.inputSelectionAvailable = false;
        await pumpSelector(tester);

        expect(find.byIcon(Icons.mic), findsOneWidget);
        expect(find.byIcon(Icons.bluetooth), findsNothing);
      },
    );

    testWidgets('the playback toggle never carries a mic badge', (
      tester,
    ) async {
      await pumpSelector(tester);

      // Playback is off in this state, so its icon is volume_off; the single
      // bluetooth badge present belongs to the mic toggle, not this one.
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    });
  });
}

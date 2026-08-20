import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/recording_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/voice_service_provider.dart';
import 'package:relagent/speech_recognition/mic_selection_widgets.dart';
import 'package:relagent/speech_recognition/widgets.dart';
import 'package:relagent/voice/voice_service.dart';
import 'package:relagent/voice/voice_service_stub.dart';
import 'package:relagent/widgets/voice_mode_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_settings':
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour"}',
    });
    voiceService = _FakeVoiceService();
  });

  Future<void> pumpButton(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          voiceServiceProvider.overrideWithValue(voiceService),
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

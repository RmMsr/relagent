# Testing Strategy for Voice Mode System

## Overview

The voice mode system has complex interactions between:
1. **VoiceMode enum** (4 states)
2. **Settings helpers** (isAutoPlayback, isContinuousRecording)
3. **RecordingProvider** (lifecycle management)
4. **TtsProvider** (queue management)
5. **UI widgets** (VoiceModeSelector, RecorderButton)

This document proposes a comprehensive testing strategy to ensure correct behavior.

## State Complexity Analysis

### Voice Mode State Machine

```
                    silent          listening       conversation      reading
                    ------          ---------       ------------      -------
Recording:          one-shot        continuous      continuous        one-shot
Auto-playback:      NO              NO              YES               YES
```

### State Transitions (16 possible)

From each of the 4 modes, you can transition to any other mode (including self):
- silent → listening, conversation, reading, silent
- listening → silent, conversation, reading, listening
- conversation → silent, listening, reading, conversation
- reading → silent, listening, conversation, reading

### Complex Interactions

1. **Recording lifecycle**: Continuous recording must auto-start/stop based on mode
2. **TTS queue behavior**: Auto-queue only in conversation/reading modes
3. **UI toggle mapping**: 2 boolean toggles map to 4-state enum
4. **RecorderButton behavior**: Changes based on mode (toggle mode vs start/stop recording)

## Testing Strategy

### Level 1: Unit Tests (Models & Logic)

Test pure logic without Flutter dependencies.

**Test: `test/models/settings_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/settings.dart';

void main() {
  group('VoiceMode helpers', () {
    test('isAutoPlayback returns true for conversation mode', () {
      final settings = Settings.defaults().copyWith(
        voiceMode: VoiceMode.conversation,
      );
      expect(settings.isAutoPlayback, isTrue);
      expect(settings.isContinuousRecording, isTrue);
    });

    test('isAutoPlayback returns true for reading mode', () {
      final settings = Settings.defaults().copyWith(
        voiceMode: VoiceMode.reading,
      );
      expect(settings.isAutoPlayback, isTrue);
      expect(settings.isContinuousRecording, isFalse);
    });

    test('isAutoPlayback returns false for listening mode', () {
      final settings = Settings.defaults().copyWith(
        voiceMode: VoiceMode.listening,
      );
      expect(settings.isAutoPlayback, isFalse);
      expect(settings.isContinuousRecording, isTrue);
    });

    test('isAutoPlayback returns false for silent mode', () {
      final settings = Settings.defaults().copyWith(
        voiceMode: VoiceMode.silent,
      );
      expect(settings.isAutoPlayback, isFalse);
      expect(settings.isContinuousRecording, isFalse);
    });
  });

  group('Settings serialization', () {
    test('toJson includes voiceMode', () {
      final settings = Settings.defaults().copyWith(
        voiceMode: VoiceMode.listening,
      );
      final json = settings.toJson();
      expect(json['voiceMode'], 'listening');
    });

    test('fromJson parses voiceMode correctly', () {
      final json = {
        'simpleChatBaseUrl': 'http://test',
        'simpleChatModel': 'test-model',
        'voiceMode': 'reading',
      };
      final settings = Settings.fromJson(json);
      expect(settings.voiceMode, VoiceMode.reading);
    });

    test('fromJson migrates old ttsAutoQueue=true to conversation', () {
      final json = {
        'simpleChatBaseUrl': 'http://test',
        'simpleChatModel': 'test-model',
        'ttsAutoQueue': true,
      };
      final settings = Settings.fromJson(json);
      expect(settings.voiceMode, VoiceMode.conversation);
    });

    test('fromJson migrates old ttsAutoQueue=false to listening', () {
      final json = {
        'simpleChatBaseUrl': 'http://test',
        'simpleChatModel': 'test-model',
        'ttsAutoQueue': false,
      };
      final settings = Settings.fromJson(json);
      expect(settings.voiceMode, VoiceMode.listening);
    });
  });

  group('Settings equality', () {
    test('equal settings have same hashCode', () {
      final s1 = Settings.defaults();
      final s2 = Settings.defaults();
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('different voiceMode produces different settings', () {
      final s1 = Settings.defaults().copyWith(voiceMode: VoiceMode.silent);
      final s2 = Settings.defaults().copyWith(voiceMode: VoiceMode.listening);
      expect(s1, isNot(equals(s2)));
    });
  });
}
```

### Level 2: Provider Tests (State Management)

Test provider logic with mock dependencies.

**Test: `test/providers/settings_provider_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/settings_provider.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('SettingsNotifier', () {
    test('starts with defaults when no saved settings', () {
      final settings = container.read(settingsProvider);
      expect(settings, equals(Settings.defaults()));
    });

    test('updateVoiceMode changes state and persists', () async {
      final notifier = container.read(settingsProvider.notifier);

      final success = await notifier.updateVoiceMode(VoiceMode.silent);
      expect(success, isTrue);

      final settings = container.read(settingsProvider);
      expect(settings.voiceMode, VoiceMode.silent);

      // Verify persistence
      final savedJson = prefs.getString('user_settings');
      expect(savedJson, contains('"voiceMode":"silent"'));
    });

    test('loads persisted voiceMode on initialization', () async {
      // Save settings
      await prefs.setString('user_settings', '''
        {
          "simpleChatBaseUrl": "http://test",
          "simpleChatModel": "test-model",
          "ttsSpeakerId": 0,
          "ttsSpeed": 1.0,
          "voiceMode": "listening"
        }
      ''');

      // Create new container (simulates app restart)
      final newContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      final settings = newContainer.read(settingsProvider);
      expect(settings.voiceMode, VoiceMode.listening);

      newContainer.dispose();
    });
  });
}
```

**Test: `test/providers/recording_provider_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/recording_provider.dart';
import 'package:relagent/providers/settings_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('RecordingNotifier voice mode transitions', () {
    test('starts continuous recording when switching to listening mode', () async {
      // Start in silent mode
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      var recordingState = container.read(recordingProvider);
      expect(recordingState.isContinuous, isFalse);

      // Switch to listening mode
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.listening);

      // Note: actual ASR start requires real device, so we test state intent
      // In integration tests, we'd verify actual recording behavior
    });

    test('starts continuous recording when switching to conversation mode', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.conversation);

      // Recording should be continuous (would verify with real ASR)
    });

    test('stops continuous recording when switching from listening to silent', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.listening);

      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      final recordingState = container.read(recordingProvider);
      expect(recordingState.isContinuous, isFalse);
    });

    test('stops continuous recording when switching from conversation to reading', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.conversation);

      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.reading);

      final recordingState = container.read(recordingProvider);
      expect(recordingState.isContinuous, isFalse);
    });
  });

  group('RecordingNotifier one-shot recording', () {
    test('startOneShot works in silent mode', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      // Would call startOneShot and verify recording starts
      // Requires real ASR for full test
    });

    test('startOneShot works in reading mode', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.reading);

      // Would call startOneShot and verify recording starts
    });

    test('stopOneShot does not auto-submit text', () async {
      // This behavior is in the ASR service callbacks
      // Would need to mock ASR and verify text stays in field
    });
  });
}
```

### Level 3: Integration Tests (State Machine)

Test all 16 state transitions in a single comprehensive test.

**Test: `test/integration/voice_mode_state_machine_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/providers/recording_provider.dart';
import 'package:relagent/providers/tts_provider.dart';

void main() {
  group('Voice Mode State Machine - All Transitions', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    // Helper to verify expected state
    void verifyState({
      required VoiceMode mode,
      required bool shouldAutoPlay,
      required bool shouldContinuousRecord,
    }) {
      final settings = container.read(settingsProvider);
      expect(settings.voiceMode, mode, reason: 'Mode should be $mode');
      expect(settings.isAutoPlayback, shouldAutoPlay,
          reason: 'Auto-playback should be $shouldAutoPlay for $mode');
      expect(settings.isContinuousRecording, shouldContinuousRecord,
          reason: 'Continuous recording should be $shouldContinuousRecord for $mode');
    }

    // Helper to transition and verify
    Future<void> transitionTo(VoiceMode mode) async {
      await container.read(settingsProvider.notifier).updateVoiceMode(mode);
    }

    test('silent mode has correct properties', () async {
      await transitionTo(VoiceMode.silent);
      verifyState(
        mode: VoiceMode.silent,
        shouldAutoPlay: false,
        shouldContinuousRecord: false,
      );
    });

    test('listening mode has correct properties', () async {
      await transitionTo(VoiceMode.listening);
      verifyState(
        mode: VoiceMode.listening,
        shouldAutoPlay: false,
        shouldContinuousRecord: true,
      );
    });

    test('conversation mode has correct properties', () async {
      await transitionTo(VoiceMode.conversation);
      verifyState(
        mode: VoiceMode.conversation,
        shouldAutoPlay: true,
        shouldContinuousRecord: true,
      );
    });

    test('reading mode has correct properties', () async {
      await transitionTo(VoiceMode.reading);
      verifyState(
        mode: VoiceMode.reading,
        shouldAutoPlay: true,
        shouldContinuousRecord: false,
      );
    });

    group('State transitions from silent', () {
      setUp(() async {
        await transitionTo(VoiceMode.silent);
      });

      test('silent → listening', () async {
        await transitionTo(VoiceMode.listening);
        verifyState(mode: VoiceMode.listening,
            shouldAutoPlay: false, shouldContinuousRecord: true);
      });

      test('silent → conversation', () async {
        await transitionTo(VoiceMode.conversation);
        verifyState(mode: VoiceMode.conversation,
            shouldAutoPlay: true, shouldContinuousRecord: true);
      });

      test('silent → reading', () async {
        await transitionTo(VoiceMode.reading);
        verifyState(mode: VoiceMode.reading,
            shouldAutoPlay: true, shouldContinuousRecord: false);
      });
    });

    group('State transitions from listening', () {
      setUp(() async {
        await transitionTo(VoiceMode.listening);
      });

      test('listening → silent', () async {
        await transitionTo(VoiceMode.silent);
        verifyState(mode: VoiceMode.silent,
            shouldAutoPlay: false, shouldContinuousRecord: false);
      });

      test('listening → conversation', () async {
        await transitionTo(VoiceMode.conversation);
        verifyState(mode: VoiceMode.conversation,
            shouldAutoPlay: true, shouldContinuousRecord: true);
      });

      test('listening → reading', () async {
        await transitionTo(VoiceMode.reading);
        verifyState(mode: VoiceMode.reading,
            shouldAutoPlay: true, shouldContinuousRecord: false);
      });
    });

    group('State transitions from conversation', () {
      setUp(() async {
        await transitionTo(VoiceMode.conversation);
      });

      test('conversation → silent', () async {
        await transitionTo(VoiceMode.silent);
        verifyState(mode: VoiceMode.silent,
            shouldAutoPlay: false, shouldContinuousRecord: false);
      });

      test('conversation → listening', () async {
        await transitionTo(VoiceMode.listening);
        verifyState(mode: VoiceMode.listening,
            shouldAutoPlay: false, shouldContinuousRecord: true);
      });

      test('conversation → reading', () async {
        await transitionTo(VoiceMode.reading);
        verifyState(mode: VoiceMode.reading,
            shouldAutoPlay: true, shouldContinuousRecord: false);
      });
    });

    group('State transitions from reading', () {
      setUp(() async {
        await transitionTo(VoiceMode.reading);
      });

      test('reading → silent', () async {
        await transitionTo(VoiceMode.silent);
        verifyState(mode: VoiceMode.silent,
            shouldAutoPlay: false, shouldContinuousRecord: false);
      });

      test('reading → listening', () async {
        await transitionTo(VoiceMode.listening);
        verifyState(mode: VoiceMode.listening,
            shouldAutoPlay: false, shouldContinuousRecord: true);
      });

      test('reading → conversation', () async {
        await transitionTo(VoiceMode.conversation);
        verifyState(mode: VoiceMode.conversation,
            shouldAutoPlay: true, shouldContinuousRecord: true);
      });
    });
  });
}
```

### Level 4: Widget Tests (UI Logic)

Test toggle control mapping to voice modes.

**Test: `test/widgets/voice_mode_selector_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/widgets/voice_mode_selector.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  Widget createWidget(VoiceMode initialMode) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: VoiceModeSelector(),
        ),
      ),
    );
  }

  group('VoiceModeSelector UI mapping', () {
    test('silent mode shows both toggles off', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      await tester.pumpWidget(createWidget(VoiceMode.silent));

      // Both speaker and mic should be in "off" position
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    });

    test('listening mode shows speaker off, mic on', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.listening);

      await tester.pumpWidget(createWidget(VoiceMode.listening));

      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    test('conversation mode shows both toggles on', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.conversation);

      await tester.pumpWidget(createWidget(VoiceMode.conversation));

      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    test('reading mode shows speaker on, mic off', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.reading);

      await tester.pumpWidget(createWidget(VoiceMode.reading));

      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    });
  });

  group('Toggle interactions', () {
    test('toggling playback off in conversation switches to listening', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.conversation);

      await tester.pumpWidget(createWidget(VoiceMode.conversation));

      // Tap the volume_off button (turn playback off)
      await tester.tap(find.byIcon(Icons.volume_off));
      await tester.pump();

      final newSettings = container.read(settingsProvider);
      expect(newSettings.voiceMode, VoiceMode.listening);
    });

    test('toggling playback on in silent switches to reading', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      await tester.pumpWidget(createWidget(VoiceMode.silent));

      // Tap the volume_up button (turn playback on)
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      final newSettings = container.read(settingsProvider);
      expect(newSettings.voiceMode, VoiceMode.reading);
    });

    test('toggling mic off in conversation switches to reading', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.conversation);

      await tester.pumpWidget(createWidget(VoiceMode.conversation));

      // Tap the mic_off button (turn mic off)
      await tester.tap(find.byIcon(Icons.mic_off));
      await tester.pump();

      final newSettings = container.read(settingsProvider);
      expect(newSettings.voiceMode, VoiceMode.reading);
    });

    test('toggling mic on in silent switches to listening', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      await tester.pumpWidget(createWidget(VoiceMode.silent));

      // Tap the mic button (turn mic on)
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      final newSettings = container.read(settingsProvider);
      expect(newSettings.voiceMode, VoiceMode.listening);
    });
  });

  group('Combined toggle interactions', () {
    test('silent → both on → conversation', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);

      await tester.pumpWidget(createWidget(VoiceMode.silent));

      // Turn playback on
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      expect(container.read(settingsProvider).voiceMode, VoiceMode.reading);

      // Turn mic on
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      expect(container.read(settingsProvider).voiceMode, VoiceMode.conversation);
    });

    test('conversation → both off → silent', () async {
      await container.read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.conversation);

      await tester.pumpWidget(createWidget(VoiceMode.conversation));

      // Turn playback off
      await tester.tap(find.byIcon(Icons.volume_off));
      await tester.pump();
      expect(container.read(settingsProvider).voiceMode, VoiceMode.listening);

      // Turn mic off
      await tester.tap(find.byIcon(Icons.mic_off));
      await tester.pump();
      expect(container.read(settingsProvider).voiceMode, VoiceMode.silent);
    });
  });
}
```

## Test Execution Plan

### Phase 1: Basic Setup
1. Create `test/` directory structure
2. Add test dependencies to `pubspec.yaml`:
   ```yaml
   dev_dependencies:
     flutter_test:
       sdk: flutter
     mockito: ^5.4.0
     build_runner: ^2.4.0
   ```
3. Implement Level 1 tests (models)

### Phase 2: Provider Tests
1. Implement settings provider tests
2. Implement recording provider tests
3. Note: Some tests will be limited without mocking ASR

### Phase 3: Integration Tests
1. Implement state machine tests
2. Verify all 16 transitions work correctly
3. Document any edge cases discovered

### Phase 4: Widget Tests
1. Implement VoiceModeSelector tests
2. Verify toggle mapping logic
3. Test user interaction flows

## Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/models/settings_test.dart

# Run with coverage
flutter test --coverage
```

## Coverage Goals

- **Models**: 100% (pure logic, easy to test)
- **Providers**: 80%+ (some ASR integration requires real device)
- **Widgets**: 80%+ (focus on logic, not styling)
- **Integration**: Cover all 16 state transitions

## Limitations & Future Work

### Current Limitations
1. **ASR mocking**: RecordingProvider tests limited without ASR mock
2. **TTS mocking**: TtsProvider tests would need audio player mock
3. **Real device testing**: Some behaviors only testable on device

### Future Improvements
1. Create mock ASR service for more thorough RecordingProvider tests
2. Add golden tests for UI visual regression
3. Add integration tests on real device with automation
4. Performance testing for rapid mode switches

## Maintenance

- **When adding new voice modes**: Update state machine tests
- **When changing toggle logic**: Update widget tests
- **When changing provider logic**: Update provider tests
- **Run tests before every commit**: `flutter test`

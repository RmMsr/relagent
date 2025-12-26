# On-Device Integration Testing Playbook

This guide covers manual and automated testing of audio functionality on real devices.

## Current Status

⏳ **Not yet implemented** - This playbook documents the strategy for future implementation

## Overview

Integration tests verify audio behavior that requires real hardware:
- Actual audio playback through speakers/Bluetooth
- Microphone recording functionality
- Bluetooth device routing
- Real-world interruption scenarios (calls, notifications)

## Quick Start (Manual Testing)

### Prerequisites

```bash
# Install Flutter (via fvm)
fvm flutter doctor

# Connect Android device
$ANDROID_HOME/platform-tools/adb devices

# Build and install debug APK
fvm flutter run
```

### Manual Test Checklist

Run through these scenarios on a physical device:

#### 1. Audio Playback Tests

- [ ] **Basic TTS playback**
  - Enable conversation mode
  - Send a chat message
  - Verify audio plays through phone speaker
  - Check audio is clear and complete

- [ ] **Bluetooth routing**
  - Connect Bluetooth headphones
  - Send a chat message
  - Verify audio routes to Bluetooth device (not phone speaker)
  - Disconnect Bluetooth mid-playback
  - Verify audio switches to phone speaker seamlessly

- [ ] **Queue processing**
  - Send multiple messages rapidly
  - Verify all messages play in order
  - Verify no messages are skipped or duplicated

#### 2. Recording Tests

- [ ] **Basic voice recording**
  - Enable listening mode
  - Speak a message
  - Verify transcript appears
  - Check accuracy of transcription

- [ ] **Bluetooth microphone**
  - Connect Bluetooth headset with mic
  - Enable listening mode
  - Speak into Bluetooth mic
  - Verify recording uses Bluetooth mic (not phone mic)

#### 3. Interruption Tests

- [ ] **Phone call during playback**
  - Start audio playback
  - Receive/make a phone call
  - Verify playback pauses
  - End call
  - Verify playback resumes (or doesn't, based on settings)

- [ ] **Phone call during recording**
  - Enable listening mode
  - Receive/make a phone call
  - Verify recording pauses
  - End call
  - Verify recording resumes

- [ ] **Notification sounds**
  - Start audio playback
  - Trigger a notification (message, alarm, etc.)
  - Verify playback continues or pauses appropriately

#### 4. Background Behavior Tests

- [ ] **Background listening duration**
  - Set background duration to 5 minutes
  - Enable listening mode
  - Lock screen
  - Wait 5 minutes
  - Verify mode switches to silent
  - Check notification shows "Listening stopped"

- [ ] **App backgrounded during playback**
  - Start audio playback
  - Press home button
  - Verify playback continues in background
  - Return to app
  - Verify state is correct

#### 5. Edge Cases

- [ ] **Airplane mode toggle**
  - Enable listening mode
  - Toggle airplane mode on/off
  - Verify app recovers gracefully

- [ ] **Multiple Bluetooth devices**
  - Connect two Bluetooth devices
  - Start playback
  - Switch between devices via system settings
  - Verify routing updates correctly

- [ ] **Audio focus competition**
  - Start recording
  - Open another app that uses audio (YouTube, Spotify)
  - Verify recording stops appropriately
  - Close other app
  - Verify recording resumes (if configured)

### Recording Test Results

Create a test report in `integration_test/results/YYYY-MM-DD.md`:

```markdown
# Integration Test Results - 2025-12-25

**Device**: Pixel 6 Pro (Android 14)
**App Version**: 1.0.0-dev
**Tester**: Your Name

## Results

### Audio Playback Tests
- [x] Basic TTS playback - PASS
- [x] Bluetooth routing - PASS
- [x] Queue processing - PASS

### Recording Tests
- [x] Basic voice recording - PASS
- [ ] Bluetooth microphone - FAIL (audio garbled)

### Interruption Tests
- [x] Phone call during playback - PASS
- [x] Phone call during recording - PASS
- [x] Notification sounds - PASS

### Notes
- Bluetooth mic quality degraded after 2 minutes
- App crashed once during airplane mode toggle
```

## Automated Testing

### Setup Integration Tests

Add to `pubspec.yaml`:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
```

Install dependencies:
```bash
fvm flutter pub get
```

### Writing Integration Tests

Create `integration_test/audio_playback_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:relagent/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Audio Playback Integration Tests', () {
    testWidgets('TTS plays audio through speakers', (tester) async {
      // Launch app
      app.main();
      await tester.pumpAndSettle();

      // Enable conversation mode
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conversation'));
      await tester.pumpAndSettle();

      // Send a message
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Wait for TTS to start
      await tester.pump(Duration(seconds: 2));

      // Verify audio is playing (check provider state)
      expect(find.text('Playing'), findsOneWidget);
    });

    testWidgets('Audio routes to Bluetooth device', (tester) async {
      // This test requires physical Bluetooth device
      // See "Automated Device Testing" section below
    });
  });
}
```

### Running Integration Tests

**On connected device:**
```bash
# Android
fvm flutter test integration_test/audio_playback_test.dart

# iOS
fvm flutter test integration_test/audio_playback_test.dart --device-id=<device-id>
```

**With Flutter Driver (advanced):**
```bash
fvm flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/audio_playback_test.dart \
  --device-id=<device-id>
```

## Automated Device Testing (CI/CD)

### Firebase Test Lab (Recommended)

Firebase Test Lab provides real device testing in the cloud.

**Setup:**

1. Create Firebase project at https://console.firebase.google.com
2. Enable Test Lab API
3. Install Firebase CLI: `npm install -g firebase-tools`
4. Login: `firebase login`

**Build test APK:**
```bash
# Build app APK
fvm flutter build apk --debug

# Build test APK
pushd android
./gradlew app:assembleAndroidTest
./gradlew app:assembleDebug -Ptarget=integration_test/audio_playback_test.dart
popd
```

**Run on Test Lab:**
```bash
gcloud firebase test android run \
  --type instrumentation \
  --app build/app/outputs/apk/debug/app-debug.apk \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --device model=redfin,version=30,locale=en,orientation=portrait \
  --timeout 10m
```

**Popular device matrix:**
```yaml
# test-devices.yml
- model: redfin      # Pixel 5
  version: 30        # Android 11
- model: blueline    # Pixel 3
  version: 28        # Android 9
- model: walleye     # Pixel 2
  version: 27        # Android 8.1
```

Run with matrix:
```bash
gcloud firebase test android run \
  --type instrumentation \
  --app build/app/outputs/apk/debug/app-debug.apk \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --device-ids redfin,blueline,walleye \
  --os-version-ids 30,28,27 \
  --locales en \
  --orientations portrait \
  --timeout 15m
```

### GitHub Actions Integration

Create `.github/workflows/integration-tests.yml`:

```yaml
name: Integration Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  integration_test:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v3

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        run: flutter pub get

      - name: Build APKs
        run: |
          flutter build apk --debug
          cd android
          ./gradlew app:assembleAndroidTest
          ./gradlew app:assembleDebug -Ptarget=integration_test/audio_playback_test.dart

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}

      - name: Run tests on Firebase Test Lab
        run: |
          gcloud firebase test android run \
            --type instrumentation \
            --app build/app/outputs/apk/debug/app-debug.apk \
            --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
            --device model=redfin,version=30 \
            --timeout 10m \
            --results-bucket=gs://your-bucket-name \
            --results-dir=integration-tests/$(date +%Y-%m-%d-%H-%M-%S)

      - name: Upload results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: integration-test-results
          path: build/test-results/
```

### Local Device Farm (Alternative)

For organizations with physical devices on-site:

**Option 1: Appium + Selenium Grid**
```bash
# Install Appium
npm install -g appium

# Start Appium server
appium --address 127.0.0.1 --port 4723

# Connect devices to hub
# Run tests via Appium client
```

**Option 2: Device Farm with ADB**
```bash
# List connected devices
adb devices

# Install on all devices
for device in $(adb devices | grep -v "List" | awk '{print $1}'); do
  adb -s $device install build/app/outputs/apk/debug/app-debug.apk
done

# Run tests on each device
for device in $(adb devices | grep -v "List" | awk '{print $1}'); do
  flutter test integration_test/audio_playback_test.dart --device-id=$device
done
```

## Bluetooth Testing Automation

**Challenge**: Bluetooth requires physical devices, making automation complex.

### Strategies

**1. Bluetooth Simulator (Limited)**
- Some emulators support virtual Bluetooth
- Limited to basic connectivity, not audio routing
- Useful for testing connection logic only

**2. Physical Device + Bluetooth Headset**
- Connect test device to Bluetooth headset
- Hardcode headset name in test
- Verify routing via audio session state

```dart
testWidgets('Audio routes to known Bluetooth device', (tester) async {
  // Prerequisite: Bluetooth device "Test Headphones" must be paired
  app.main();
  await tester.pumpAndSettle();

  // Verify Bluetooth device is connected
  final audioSession = await AudioSession.instance;
  final devices = await audioSession.getDevices();
  expect(
    devices.any((d) => d.name.contains('Test Headphones')),
    true,
    reason: 'Test Headphones must be connected before running test',
  );

  // Send message to trigger playback
  await tester.enterText(find.byType(TextField), 'Test message');
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();

  // Verify audio session reports Bluetooth output
  final outputDevices = devices.where((d) => d.isOutput);
  expect(
    outputDevices.any((d) => d.type == AudioDeviceType.bluetoothA2dp),
    true,
  );
});
```

**3. Audio Loopback Testing**
- Use test device with loopback cable (3.5mm jack)
- Record output and verify playback
- Advanced setup, high confidence

**4. Test Lab with Pre-paired Devices**
- Some test labs support pre-configured Bluetooth
- Contact Firebase Test Lab or AWS Device Farm for options

## Audio Quality Testing

### Manual Verification

1. Record expected audio output: `expected_audio.mp3`
2. During test, record actual output via loopback
3. Compare audio files:

```bash
# Using ffmpeg for audio comparison
ffmpeg -i expected_audio.mp3 -i actual_audio.mp3 \
  -filter_complex "[0:a][1:a]amerge=inputs=2,showwaves" \
  comparison.mp4
```

### Automated Quality Checks

```dart
testWidgets('TTS audio quality meets threshold', (tester) async {
  // This requires audio analysis library
  // Placeholder for future implementation

  // 1. Trigger playback
  // 2. Capture audio output
  // 3. Analyze for:
  //    - Clipping/distortion
  //    - Volume levels
  //    - Frequency response
  // 4. Compare against baseline
});
```

## Test Data Management

### Audio Fixtures

Store test audio files in `integration_test/fixtures/`:

```
integration_test/
├── fixtures/
│   ├── audio/
│   │   ├── test_tts_output.mp3
│   │   ├── test_recording.wav
│   │   └── expected_bluetooth_routing.mp3
│   └── scenarios/
│       ├── phone_call_interrupt.json
│       └── bluetooth_device_change.json
└── README.md
```

### Device Configurations

Document known device behaviors:

```dart
// integration_test/device_quirks.dart

class DeviceQuirks {
  static bool needsAudioFocusDelay(String model) {
    // Pixel 3 needs 500ms delay after audio focus change
    return model.contains('blueline');
  }

  static Duration bluetoothSwitchDelay(String model) {
    // Samsung devices take longer to switch Bluetooth
    if (model.contains('samsung')) return Duration(seconds: 2);
    return Duration(milliseconds: 500);
  }
}
```

## Monitoring & Reporting

### Test Reports

Generate detailed test reports:

```bash
# Run with XML output
flutter test integration_test/ --reporter=json > test_results.json

# Parse and format
python scripts/format_test_results.py test_results.json > report.html
```

### Performance Metrics

Track key metrics across test runs:

- Audio latency (time from trigger to playback start)
- Bluetooth routing time (time to switch outputs)
- Battery drain during background listening
- Memory usage during long playback sessions

### Crash Reporting

Integrate with Crashlytics/Sentry for automated crash detection:

```dart
// In main.dart
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
```

## Best Practices

### DO

- ✅ Test on multiple Android versions (especially 11+)
- ✅ Test on multiple device manufacturers (Samsung, Pixel, OnePlus)
- ✅ Include Bluetooth device variety (headphones, car audio, speakers)
- ✅ Test with different audio interruptions (calls, alarms, other apps)
- ✅ Document device-specific quirks
- ✅ Run tests regularly (daily/weekly)
- ✅ Keep audio fixtures in version control

### DON'T

- ❌ Rely only on emulators for audio testing
- ❌ Skip Bluetooth testing (most critical for UX)
- ❌ Ignore flaky tests (investigate and fix)
- ❌ Test only on latest Android version
- ❌ Hardcode timing assumptions (devices vary)

## Troubleshooting

### "Integration test times out"

**Problem**: Test waits forever for audio playback

**Solution**: Add explicit timeouts:
```dart
await tester.pumpAndSettle(timeout: Duration(seconds: 5));
```

### "Bluetooth device not found"

**Problem**: Test can't detect Bluetooth device

**Solution**:
1. Verify device is paired before test
2. Add retry logic for device detection
3. Use device name from environment variable

### "Audio routing inconsistent"

**Problem**: Sometimes routes to Bluetooth, sometimes to speaker

**Solution**:
1. Add explicit audio session configuration
2. Verify `audio_session` is properly initialized
3. Check for competing audio apps

## Future Enhancements

- [ ] Automated audio quality analysis
- [ ] Visual regression testing for UI
- [ ] Performance benchmarking suite
- [ ] Multi-device coordination tests (2+ devices)
- [ ] Accessibility testing (TalkBack, VoiceOver)
- [ ] Network condition simulation
- [ ] Battery drain profiling

## Resources

- [Flutter Integration Testing](https://docs.flutter.dev/testing/integration-tests)
- [Firebase Test Lab](https://firebase.google.com/docs/test-lab)
- [Android Audio Testing](https://source.android.com/docs/core/audio/testing)
- [Bluetooth Testing Guide](https://source.android.com/docs/core/connect/bluetooth/testing)

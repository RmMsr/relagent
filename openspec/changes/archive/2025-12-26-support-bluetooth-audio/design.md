# support-bluetooth-audio Design Document

## Problem Statement

The Relagent app currently does not reliably route audio through Bluetooth headsets for speech recognition (ASR) input or text-to-speech (TTS) output. Previous experiments showed Bluetooth playback never worked seamlessly. This is a critical usability issue because:

1. **Hands-free usage** is the primary use case - users expect Bluetooth to "just work"
2. **Privacy** - Bluetooth headsets allow private conversations in public
3. **Mobility** - Users need to move freely while using voice features
4. **Standard expectations** - All voice apps (calls, assistants) support Bluetooth automatically

## Root Cause Analysis

### Recording (ASR) Issue

**File:** `/home/roman/projects/relagent-bluetooth/apps/lib/speech_recognition/services.dart:99`

**Current Code:**
```dart
androidConfig: AndroidRecordConfig(
  audioManagerMode: AudioManagerMode.modeNormal,  // ❌ WRONG
),
```

**Why This Breaks Bluetooth Microphone:**
- `AudioManagerMode.modeNormal` is for general audio (music, games)
- Uses A2DP profile (Advanced Audio Distribution Profile) for high-quality stereo
- A2DP is **one-way** - playback only, no microphone input
- Bluetooth microphones require SCO (Synchronous Connection-Oriented) for two-way audio
- SCO is activated by `AudioManagerMode.communication` mode

**Bluetooth Profiles:**
- **A2DP**: High-quality stereo (music) - `modeNormal`
- **HFP/HSP**: Voice calls (mono, echo cancellation) - `communication`

### Playback (TTS) Issue

**File:** `/home/roman/projects/relagent-bluetooth/apps/lib/providers/background_service_provider.dart:135-138`

**Current Code:**
```dart
final session = await AudioSession.instance;
await session.configure(const AudioSessionConfiguration.speech());
```

**Why This Is Insufficient:**
1. **One-time configuration**: Only runs at app startup, doesn't adapt to mode changes
2. **Generic defaults**: `AudioSessionConfiguration.speech()` doesn't explicitly enable Bluetooth
3. **No activation**: `session.setActive(true)` never called
4. **No mode distinction**: Recording and playback use same session config
5. **Missing Android attributes**: No `AndroidAudioUsage.voiceCommunication` for Bluetooth SCO

**AudioSessionConfiguration.speech() Defaults:**
```dart
// iOS defaults (good)
avAudioSessionCategory: AVAudioSessionCategory.playAndRecord
avAudioSessionMode: AVAudioSessionMode.spokenAudio

// Android defaults (insufficient)
// Does NOT explicitly set:
// - androidAudioAttributes (uses plugin defaults)
// - Bluetooth-specific configuration
```

### Device Change Detection Gap

**Missing:** No listener for Bluetooth connect/disconnect events

**Impact:**
- Audio continues on phone speaker if Bluetooth disconnects mid-session
- No automatic switch to Bluetooth when headset connects mid-session
- User must restart recording/playback to pick up new device

## Solution Architecture

### Design Principles

1. **Minimal Changes**: Fix configuration, don't rewrite audio stack
2. **Preserve Existing Patterns**: Keep audio coordinator, health monitoring, focus handling unchanged
3. **Platform Best Practices**: Match OS behavior for voice apps
4. **Graceful Degradation**: Fall back to phone audio if Bluetooth unavailable
5. **No User Configuration**: Automatic routing like calls and assistants

### Component Responsibilities

#### 1. Recording Configuration (`speech_recognition/services.dart`)

**Responsibility:** Use correct audio mode for Bluetooth microphone

**Change:**
```dart
androidConfig: AndroidRecordConfig(
  audioManagerMode: AudioManagerMode.communication,  // ✅ Enables Bluetooth SCO
),
```

**Why This Works:**
- `communication` mode tells Android AudioManager to route to voice communication devices
- Automatically enables Bluetooth SCO when headset connected
- Includes echo cancellation (important for Bluetooth)
- Switches to phone mic if Bluetooth unavailable

**No iOS Changes Needed:**
- `record` package handles iOS Bluetooth routing automatically
- iOS respects audio session category options

#### 2. Audio Session Configuration (`providers/background_service_provider.dart`)

**Responsibility:** Configure audio session per mode with explicit Bluetooth enablement

**New Methods:**

```dart
Future<void> _configureAudioSessionForRecording() async {
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration(
    // iOS Configuration
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    avAudioSessionCategoryOptions:
      AVAudioSessionCategoryOptions.allowBluetooth |
      AVAudioSessionCategoryOptions.defaultToSpeaker,

    // Android Configuration
    androidAudioAttributes: const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.voiceCommunication,  // ✅ Key for Bluetooth SCO
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    androidWillPauseWhenDucked: false,
  ));

  await session.setActive(true);  // ✅ Activate session
}

Future<void> _configureAudioSessionForPlayback() async {
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration(
    // iOS Configuration
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,

    // Android Configuration
    androidAudioAttributes: const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.assistant,  // ✅ Decision: use assistant for consistency
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    androidWillPauseWhenDucked: false,
  ));

  await session.setActive(true);  // ✅ Activate session
}
```

**Why Two Configurations:**
- **Recording**: Needs `playAndRecord` category, `voiceCommunication` usage
- **Playback**: Can use `playback` category, `media` usage
- Different iOS category options (defaultToSpeaker for recording only)
- Separation allows optimization per use case

**Integration Point:**

Update `_syncServiceWithAudioMode()`:
```dart
// Before starting recording
if (mode == AudioMode.recording) {
  await _configureAudioSessionForRecording();
  // ... existing recording logic
}

// Before starting playback
if (mode == AudioMode.playing) {
  await _configureAudioSessionForPlayback();
  // ... existing playback logic
}
```

**Why This Works:**
- Reconfigures audio session when switching modes
- Explicitly enables Bluetooth on iOS via category options
- Explicitly enables Bluetooth SCO on Android via `voiceCommunication` usage
- Activation ensures configuration takes effect

#### 3. Device Change Detection (`providers/background_service_provider.dart`)

**Responsibility:** Detect Bluetooth connect/disconnect and adapt routing

**New Code in `_initAudioSession()`:**

```dart
session.devicesChangedEventStream.listen((event) {
  debugPrint('BackgroundServiceProvider: Audio devices changed');
  debugPrint('  Input devices: ${event.inputDevices}');
  debugPrint('  Output devices: ${event.outputDevices}');

  // Optionally reconfigure audio session to pick up new devices
  final currentMode = ref.read(audioCoordinatorProvider).mode;
  if (currentMode == AudioMode.recording) {
    _configureAudioSessionForRecording();
  } else if (currentMode == AudioMode.playing) {
    _configureAudioSessionForPlayback();
  }
});
```

**Why This Works:**
- `devicesChangedEventStream` fires on Bluetooth connect/disconnect
- Provides list of available input/output devices
- Allows reconfiguration to adapt to new device
- Logging helps debugging device-specific issues

**Trade-off:**
- Reconfiguration might be unnecessary (OS may auto-switch)
- Test both with/without reconfiguration to determine necessity
- Logging provides diagnostic value regardless

#### 4. Android Permissions (`android/app/src/main/AndroidManifest.xml`)

**Responsibility:** Grant Bluetooth connection permission for Android 12+

**Addition:**
```xml
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

**Why Needed:**
- Android 12 (API 31+) requires runtime permission for Bluetooth operations
- Includes detecting connected devices, establishing connections
- Without it, Bluetooth routing may silently fail on newer devices

**Existing Permissions (Already Correct):**
```xml
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```
- Required for Bluetooth SCO on all Android versions
- Already present, no changes needed

### Data Flow

#### Bluetooth Microphone (ASR)

```
User speaks into Bluetooth microphone
  ↓
Bluetooth headset captures audio
  ↓
Android AudioManager (in communication mode)
  ↓ (via Bluetooth SCO)
record package (AudioManagerMode.communication)
  ↓
Audio stream to RecordingProvider
  ↓
Sherpa-ONNX ASR processing
  ↓
Recognized text to ChatProvider
```

**Key Points:**
- `communication` mode tells AudioManager to use Bluetooth SCO
- `audio_session` configuration ensures focus and Bluetooth enablement
- No changes to ASR processing - transparent routing

#### Bluetooth Speakers (TTS)

```
TTS provider generates audio bytes
  ↓
PlaybackProvider enqueues audio
  ↓
just_audio player receives audio source
  ↓
audio_session (configured for playback with Bluetooth)
  ↓
Android AudioManager routes to Bluetooth A2DP
  ↓
Bluetooth headset plays audio
```

**Key Points:**
- `audio_session` configuration enables Bluetooth routing
- `just_audio` respects audio session configuration
- A2DP profile used for playback (higher quality than SCO)
- No changes to TTS processing - transparent routing

#### Device Change Handling

```
Bluetooth headset connects/disconnects
  ↓
Android/iOS OS fires device change event
  ↓
audio_session.devicesChangedEventStream
  ↓
BackgroundServiceProvider listener
  ↓
Log device change
  ↓
(Optional) Reconfigure audio session for current mode
  ↓
OS routes audio to new device
```

**Key Points:**
- OS handles actual routing, we just reconfigure if needed
- Logging provides debugging information
- Reconfiguration may be unnecessary but low-cost

### Error Handling

#### Bluetooth Connection Failures

**Scenario:** Bluetooth headset fails to connect or drops mid-session

**Handling:**
1. Recording: Continues with phone microphone (automatic fallback)
2. Playback: Continues with phone speaker (automatic fallback)
3. Health monitoring: Not affected (works with any audio device)

**User Impact:** Transparent - no errors, just switches device

#### Audio Session Configuration Failures

**Scenario:** `session.configure()` throws exception

**Handling:**
```dart
try {
  await session.configure(...);
  await session.setActive(true);
} catch (e) {
  debugPrint('Audio session configuration failed: $e');
  // Continue with previous configuration
  // Audio will work, just might not prefer Bluetooth
}
```

**User Impact:** App continues to work, may not route to Bluetooth

#### Permission Denial (Android 12+)

**Scenario:** User denies `BLUETOOTH_CONNECT` permission

**Handling:**
- Android AudioManager falls back to phone audio
- No app crash or errors
- Bluetooth simply unavailable

**User Impact:** Can still use app with phone audio

### Testing Strategy

#### Unit Testing

**Not Applicable:**
- Bluetooth routing is OS-level behavior
- Cannot mock Bluetooth devices in unit tests
- Configuration changes testable only via integration testing

#### Integration Testing (Manual)

**Test Matrix:**

| Device State | Recording | Playback | Expected Behavior |
|-------------|-----------|----------|------------------|
| No Bluetooth | Phone mic | Phone speaker | Baseline |
| Bluetooth connected at start | Bluetooth mic | Bluetooth speaker | Primary use case |
| Bluetooth connects mid-recording | Switch to Bluetooth mic | - | Seamless transition |
| Bluetooth disconnects mid-recording | Switch to phone mic | - | Seamless transition |
| Bluetooth connects mid-playback | - | Switch to Bluetooth speaker | Seamless transition |
| Bluetooth disconnects mid-playback | - | Switch to phone speaker | Seamless transition |
| Phone call interrupts Bluetooth recording | Pause, call on Bluetooth | - | Audio focus handling |
| Phone call interrupts Bluetooth playback | - | Pause, call on Bluetooth | Audio focus handling |

**Device Coverage:**
- Minimum: 1 Android device (Google Pixel or Samsung)
- Recommended: 2+ Android devices (different manufacturers)
- iOS: 1 iPhone for platform verification

**Headset Coverage:**
- Minimum: 1 Bluetooth headset (any type)
- Recommended: 2+ types (earbuds, over-ear, car system)

#### Performance Testing

**Metrics:**
1. **Bluetooth connection delay**: Time from recording start to first audio data
   - Target: < 500ms
   - Acceptable: < 1000ms
   - Action if exceeded: Add configurable delay

2. **ASR accuracy**: Compare Bluetooth mic vs phone mic
   - Method: Same test phrases, both devices
   - Acceptable: > 90% of phone mic accuracy
   - If worse: Document as known limitation

3. **Battery drain**: Compare Bluetooth vs phone audio
   - Method: 1-hour continuous listening session
   - Acceptable: < 10% additional drain
   - If worse: Document in troubleshooting

#### Regression Testing

**Ensure No Breaks:**
- Audio coordinator state transitions (recording ↔ playback)
- Health monitoring (30s checks, recovery attempts)
- Audio focus handling (calls, notifications, permanent loss)
- Background listening duration limits
- Wake lock management

**Test Plan:**
- Run existing manual test scenarios with phone audio (no Bluetooth)
- Should behave identically to pre-change behavior
- Any differences indicate regression

### Platform-Specific Considerations

#### Android

**Key Files:**
- `apps/android/app/src/main/AndroidManifest.xml` - Permissions
- `apps/android/app/src/main/kotlin/org/venkado/relagent/AudioBackgroundService.kt` - No changes needed

**Android Versions:**
- API 23-30: `MODIFY_AUDIO_SETTINGS` sufficient
- API 31+: Also requires `BLUETOOTH_CONNECT`
- No version-specific code needed (permission system handles it)

**Bluetooth Profiles:**
- SCO: Voice calls, mono, echo cancellation (`communication` mode)
- A2DP: Music/media, stereo, high quality (`normal` mode)
- App uses both: SCO for recording, A2DP for playback

**Known Android Issues:**
- Some devices have Bluetooth SCO connection delay (100-500ms)
- Samsung devices may have aggressive battery optimization affecting Bluetooth
- Solution: Test on multiple manufacturers, document quirks

#### iOS

**Key Files:**
- `apps/ios/Runner/Info.plist` - Verify background audio mode
- No platform-specific code changes needed

**Info.plist Requirements:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**iOS Audio Session Categories:**
- `playAndRecord`: Allows simultaneous recording and playback
- `playback`: Playback only
- App uses both depending on mode

**iOS Bluetooth Behavior:**
- More restrictive than Android (user preference in Settings)
- "Call Audio Routing" setting affects Bluetooth routing
- Some users set to "Automatic" vs "Bluetooth Headset"
- App must respect user preference

**Known iOS Issues:**
- Bluetooth routing respects user's "Call Audio Routing" preference
- Cannot override user's choice programmatically
- Solution: Document in troubleshooting guide

### Security and Privacy

**No New Privacy Concerns:**
- Bluetooth routing doesn't change data handling
- Audio still processed locally (Sherpa-ONNX)
- No audio sent to cloud
- Bluetooth is more private than phone speaker (confined to user's ears)

**Permission Transparency:**
- `BLUETOOTH_CONNECT` permission clearly for Bluetooth audio
- User can deny and app still works (phone audio fallback)
- No hidden Bluetooth usage

### Backward Compatibility

**No Breaking Changes:**
- Existing audio coordinator API unchanged
- Voice mode behavior unchanged
- Settings unchanged (no new user configuration)
- Health monitoring unchanged

**Migration:**
- No data migration needed
- No user action required
- Bluetooth routing automatic on update

### Rollback Strategy

**Phase 1 Rollback:**
```dart
// Revert to previous mode
androidConfig: AndroidRecordConfig(
  audioManagerMode: AudioManagerMode.modeNormal,
),
```

**Phase 2 Rollback:**
- Remove `_configureAudioSessionForRecording()` and `_configureAudioSessionForPlayback()`
- Restore single `AudioSessionConfiguration.speech()` call
- Remove `session.setActive(true)` calls

**Phase 3 Rollback:**
- Remove `devicesChangedEventStream` listener
- No other changes to revert

**Verification:**
- Test audio with phone audio (no Bluetooth)
- Should match pre-change behavior exactly

## Alternative Approaches Rejected

### 1. Use flutter_sound Package

**Considered Because:**
- More control over audio routing
- Unified API for recording and playback
- Explicit device selection API

**Rejected Because:**
- Heavier package (larger app size)
- Breaking change (replace entire audio stack)
- Current `record` + `just_audio` sufficient with correct configuration
- Not worth migration risk for same end result

### 2. Platform Channels for Direct AudioManager Access

**Considered Because:**
- Full control over Bluetooth SCO lifecycle
- Can handle manufacturer-specific edge cases
- Direct access to AudioManager APIs

**Rejected Because:**
- High implementation complexity (Java/Kotlin + Swift/Objective-C)
- Maintenance burden (Android/iOS version compatibility)
- Duplicates functionality already in `audio_session` package
- Only consider if package approach fails in testing

### 3. Manual Device Selection UI

**Considered Because:**
- Users have explicit control
- Clear visual feedback of active device
- Can override automatic routing

**Rejected Because:**
- Not standard behavior for voice apps (calls, assistants auto-route)
- More complex UX (extra settings screen)
- Additional development time
- Can be added later as enhancement if users request it

**Decision:** Automatic routing first, manual selection as future enhancement

### 4. Separate Audio Coordinator Modes for Bluetooth

**Considered Because:**
- Could optimize per device type
- More granular state tracking
- Could handle device-specific quirks

**Rejected Because:**
- Adds complexity to audio coordinator
- Users don't care about internal device distinction
- Current mutual exclusivity (recording vs playback) sufficient
- Transparency better UX (one behavior regardless of device)

## Design Decisions (Resolved)

### 1. AndroidAudioUsage for TTS Playback

**Decision: Use `AndroidAudioUsage.assistant`** ✅

**Rationale:**
- **Consistency**: Same SCO/HFP profile for both recording and playback
- **Conversation flow**: No Bluetooth profile switching between ASR → TTS → ASR
- **Voice-optimized**: TTS is speech content, not music - voice optimization appropriate
- **Lower latency**: No profile switching delay between conversation turns
- **Simpler state**: Bluetooth stays in SCO mode throughout conversation

**Implementation:**
```dart
androidAudioAttributes: const AndroidAudioAttributes(
  contentType: AndroidAudioContentType.speech,
  usage: AndroidAudioUsage.assistant,  // ✅ Decision locked
),
```

**Fallback:** If testing reveals unacceptable audio quality with `assistant`, can switch to `media` in Phase 4 refinement.

### 2. Bluetooth SCO Connection Delay

**Decision: No delay initially, add instrumentation to measure** ✅

**Rationale:**
- **Better UX**: Immediate response to user action (especially push-to-talk)
- **Modern devices**: Most establish SCO in <100ms
- **Health monitoring**: Existing system will detect and recover from failures
- **Data-driven**: Measure actual delays before adding artificial delay

**Implementation:**
```dart
// Add instrumentation in Phase 2
final startTime = DateTime.now();
await _recorder.start(...);
// On first audio data:
final delay = DateTime.now().difference(startTime);
debugPrint('Bluetooth SCO connection delay: ${delay.inMilliseconds}ms');
if (delay.inMilliseconds > 300) {
  debugPrint('WARNING: High Bluetooth SCO delay detected');
}
```

**Contingency:** If testing shows consistent >300ms delays with audio dropouts, add configurable delay in Phase 4.

### 3. Audio Session Reconfiguration on Device Change

**Decision: Log only, trust OS routing** ✅

**Rationale:**
- **OS handles routing**: Modern Android/iOS automatically route to newly connected devices
- **Lower risk**: No audio glitches from reconfiguration during active audio
- **Simpler code**: Single subscription, just logging
- **Diagnostic value**: Logs help debug device-specific issues
- **Testable**: Can add reconfiguration in Phase 4 if testing reveals issues

**Implementation:**
```dart
session.devicesChangedEventStream.listen((event) {
  debugPrint('BackgroundServiceProvider: Audio devices changed');
  debugPrint('  Input devices: ${event.inputDevices}');
  debugPrint('  Output devices: ${event.outputDevices}');
  // Trust OS to handle routing - no reconfiguration needed
});
```

**Contingency:** If testing shows OS doesn't auto-switch reliably, add reconfiguration logic in Phase 4.

### 4. audio_session Package Version

**Decision: Keep current version 0.2.2** ✅

**Rationale:**
- **Already latest**: Version 0.2.2 is the current stable release (published 7 months ago)
- **Version 0.2.3 doesn't exist**: No newer version available
- **No action needed**: Current version is appropriate for Bluetooth support

**No changes required.**

## Success Metrics

**Functional Success:**
- [ ] Bluetooth microphone used for ASR when headset connected
- [ ] Bluetooth speakers used for TTS when headset connected
- [ ] Seamless transitions during Bluetooth connect/disconnect
- [ ] No regressions in audio focus handling
- [ ] No regressions in health monitoring

**Quality Success:**
- [ ] ASR accuracy with Bluetooth ≥ 90% of phone mic accuracy
- [ ] No audio dropouts during Bluetooth transitions
- [ ] Bluetooth connection delay < 500ms
- [ ] Battery drain increase < 10% vs phone audio

**User Experience Success:**
- [ ] Behavior matches phone calls and voice assistants
- [ ] No manual configuration required
- [ ] Works transparently in background listening mode
- [ ] Graceful fallback to phone audio when Bluetooth unavailable

**Code Quality Success:**
- [ ] All analysis warnings resolved
- [ ] No code duplication
- [ ] Inline comments explain Bluetooth-specific choices
- [ ] Debug logging adequate for troubleshooting

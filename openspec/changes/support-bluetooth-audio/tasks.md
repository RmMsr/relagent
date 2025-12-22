# support-bluetooth-audio Implementation Tasks

## Pre-Implementation Research

- [ ] Review `audio_session` 0.2.3 changelog and assess upgrade safety
- [ ] Verify iOS Info.plist contains required audio background mode
- [ ] Review current Bluetooth-related logs from existing manual testing (flutter_logs_android.txt)
- [ ] Document current audio routing behavior (which device is used now)

## Phase 1: Critical Fixes (Immediate Bluetooth Support)

### Recording Configuration

- [ ] Update `apps/lib/speech_recognition/services.dart` line 99
  - Change `audioManagerMode: AudioManagerMode.modeNormal` to `AudioManagerMode.communication`
  - Add inline comment explaining Bluetooth SCO routing
- [ ] Test recording with Bluetooth headset connected
  - Verify microphone input comes from Bluetooth device
  - Check ASR accuracy with Bluetooth microphone
  - Validate no audio dropouts or delays

### Android Permissions

- [ ] Add `BLUETOOTH_CONNECT` permission to `apps/android/app/src/main/AndroidManifest.xml`
  - Add `<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />` after line 65
  - Add comment explaining Android 12+ requirement
- [ ] Verify permission request at runtime (if needed for target SDK 31+)
- [ ] Test on Android 12+ device to confirm permission works

### Initial Testing

- [ ] Test basic Bluetooth microphone routing with headset connected
- [ ] Test fallback to phone microphone when Bluetooth disconnects
- [ ] Verify existing health monitoring still functions correctly
- [ ] Check that audio focus interrupts (calls) still work properly

## Phase 2: Audio Session Enhancement (Robust Routing)

### Audio Session Configuration Methods

- [ ] Create `_configureAudioSessionForRecording()` in `apps/lib/providers/background_service_provider.dart`
  - Use `AVAudioSessionCategory.playAndRecord` for iOS
  - Use `AVAudioSessionMode.spokenAudio` for iOS
  - Add `AVAudioSessionCategoryOptions.allowBluetooth | defaultToSpeaker`
  - Use `AndroidAudioContentType.speech` with `AndroidAudioUsage.voiceCommunication`
  - Use `AndroidAudioFocusGainType.gain`
  - Set `androidWillPauseWhenDucked: false`
  - Add debug logging for audio session configuration

- [ ] Create `_configureAudioSessionForPlayback()` in `apps/lib/providers/background_service_provider.dart`
  - Use `AVAudioSessionCategory.playback` for iOS
  - Use `AVAudioSessionMode.spokenAudio` for iOS
  - Add `AVAudioSessionCategoryOptions.allowBluetooth`
  - Use `AndroidAudioContentType.speech` with `AndroidAudioUsage.media` (or test `assistant`)
  - Use `AndroidAudioFocusGainType.gain`
  - Set `androidWillPauseWhenDucked: false`
  - Add debug logging for audio session configuration

### Audio Session Activation

- [ ] Update `_syncServiceWithAudioMode()` to call configuration methods
  - Call `_configureAudioSessionForRecording()` before requesting recording mode
  - Call `_configureAudioSessionForPlayback()` before requesting playback mode
  - Call `await session.setActive(true)` after each configuration
  - Ensure proper sequencing with service state updates

- [ ] Add error handling for audio session configuration failures
  - Catch and log configuration errors
  - Fallback to previous session configuration if new one fails
  - Notify user if Bluetooth routing unavailable

### Testing

- [ ] Test Bluetooth speaker routing for TTS playback
  - Verify audio plays through Bluetooth headphones
  - Compare quality to phone speaker playback
  - Test with various message lengths

- [ ] Test audio session transitions
  - Recording → Playback: Verify no audio session conflicts
  - Playback → Recording: Verify smooth transition
  - Idle → Recording: Verify Bluetooth immediately active
  - Idle → Playback: Verify Bluetooth immediately active

- [ ] Test audio focus interrupts with new configuration
  - Phone call during recording: Should pause and switch to call audio
  - Phone call during playback: Should pause TTS
  - Notification sound: Should duck or pause appropriately
  - Resume after interrupt: Should return to Bluetooth device

## Phase 3: Device Change Detection (Seamless UX)

### Device Change Listener

- [ ] Add `devicesChangedEventStream` listener to `_initAudioSession()` in `apps/lib/providers/background_service_provider.dart`
  - Subscribe to stream in initialization
  - Log input devices and output devices on each change
  - Add debug print statements for device change events

- [ ] Implement adaptive reconfiguration on device changes
  - Detect current audio mode from `audioCoordinatorProvider`
  - Call appropriate configuration method when devices change
  - Skip reconfiguration if mode is idle
  - Add delay if needed for Bluetooth SCO connection establishment

### Testing

- [ ] Test Bluetooth connect during recording
  - Start recording with phone microphone
  - Connect Bluetooth headset mid-recording
  - Verify seamless switch to Bluetooth microphone
  - Check for audio dropouts or gaps

- [ ] Test Bluetooth disconnect during recording
  - Start recording with Bluetooth microphone
  - Disconnect Bluetooth headset mid-recording
  - Verify seamless switch to phone microphone
  - Validate health monitoring doesn't trigger false recovery

- [ ] Test Bluetooth connect during playback
  - Start TTS playback on phone speaker
  - Connect Bluetooth headset mid-playback
  - Verify seamless switch to Bluetooth speakers
  - Check for audio interruptions

- [ ] Test Bluetooth disconnect during playback
  - Start TTS playback on Bluetooth speakers
  - Disconnect Bluetooth headset mid-playback
  - Verify seamless switch to phone speaker
  - Check for playback continuation

## Phase 4: Testing & Refinement

### Comprehensive Device Testing

- [ ] Test on multiple Android devices
  - Google Pixel (stock Android)
  - Samsung Galaxy (One UI)
  - Other manufacturer (if available)
  - Document any device-specific quirks

- [ ] Test on iOS devices
  - iPhone (latest iOS version)
  - Verify Info.plist configuration sufficient
  - Test Bluetooth routing behavior matches Android

- [ ] Test with multiple Bluetooth headset types
  - True wireless earbuds (AirPods, Galaxy Buds, etc.)
  - Over-ear headphones
  - Car Bluetooth system (if available)
  - Document any headset-specific issues

### Quality & Performance Validation

- [ ] Measure Bluetooth SCO connection delay
  - Time from recording start to first audio data
  - Optimize delay if > 500ms
  - Add configurable delay if needed

- [ ] Validate ASR accuracy with Bluetooth microphone
  - Compare transcription quality: Bluetooth vs phone mic
  - Test in various noise environments
  - Document any quality degradation

- [ ] Validate TTS audio quality
  - Test `AndroidAudioUsage.media` vs `AndroidAudioUsage.assistant`
  - Choose based on quality vs consistency tradeoff
  - Document chosen approach and reasoning

- [ ] Check battery impact of Bluetooth audio
  - Compare battery drain: Bluetooth vs phone audio
  - Verify wake lock behavior unchanged
  - Ensure health monitoring overhead minimal

### Edge Case Testing

- [ ] Test airplane mode toggle during Bluetooth session
  - Verify graceful handling of Bluetooth disconnect
  - Check health monitoring response
  - Validate recovery when airplane mode disabled

- [ ] Test low Bluetooth battery
  - Verify behavior when headset battery critically low
  - Check for proper error messages
  - Validate fallback to phone audio

- [ ] Test Bluetooth audio with background duration limits
  - Verify timeout works correctly with Bluetooth devices
  - Check notification end time display accuracy
  - Test wake lock release on timeout

- [ ] Test rapid connect/disconnect cycles
  - Connect and disconnect Bluetooth repeatedly
  - Verify no state corruption or crashes
  - Check for memory leaks in device change listener

### Integration Testing

- [ ] Test full conversation flow with Bluetooth
  - Enable continuous listening mode
  - Perform multiple conversation turns
  - Verify seamless ASR → TTS → ASR cycles
  - Check audio coordinator state transitions

- [ ] Test background listening with Bluetooth
  - Enable background listening (1hr duration)
  - Lock screen and background app
  - Verify Bluetooth microphone stays active
  - Check wake lock prevents disconnection

- [ ] Test audio focus scenarios with Bluetooth
  - Incoming call during Bluetooth recording
  - Music app started during Bluetooth playback
  - Notification sounds during Bluetooth session
  - Verify correct audio routing for each scenario

### Documentation & Cleanup

- [ ] Update `apps/AGENTS.md` with Bluetooth audio behavior
  - Document automatic Bluetooth routing
  - Add troubleshooting section for Bluetooth issues
  - Note any known device-specific limitations

- [ ] Update inline code comments
  - Explain Bluetooth-specific configuration choices
  - Document AndroidAudioUsage rationale
  - Note device change detection purpose

- [ ] Add debug logging for production troubleshooting
  - Log active audio device on session start
  - Log device changes with timestamps
  - Log Bluetooth connection delays if significant

- [ ] Run `dart-flutter_analyze_files` and fix any issues
  - Address new warnings from code changes
  - Verify no deprecation warnings
  - Ensure lint compliance

## Validation Criteria

Before completing this change, verify:

- [ ] All tests pass with Bluetooth headset connected
- [ ] All tests pass with phone audio (no Bluetooth)
- [ ] All tests pass during Bluetooth connect/disconnect transitions
- [ ] No regressions in existing audio focus handling
- [ ] No regressions in health monitoring functionality
- [ ] No new crashes or errors in production logs
- [ ] Battery drain remains within acceptable limits
- [ ] User experience matches phone calls and voice assistants
- [ ] Code analysis passes with no warnings
- [ ] Documentation updated with Bluetooth behavior

## Notes

**Testing Priority:**
1. Phase 1 (critical fixes) should be tested and validated before proceeding to Phase 2
2. Phase 2 can ship without Phase 3 if device change detection proves problematic
3. Phase 3 is enhancement for seamless UX, not strictly required

**Rollback Plan:**
- If Bluetooth routing causes regressions, revert Phase 1 changes
- Audio session enhancements (Phase 2) can be reverted independently
- Device change detection (Phase 3) can be disabled without affecting Phases 1-2

**Known Limitations to Accept:**
- No manual device selection UI (automatic routing only)
- No Bluetooth connection indicators (future enhancement)
- Bluetooth microphone quality may be lower than phone mic (user choice)
- Device-specific quirks may require per-device testing

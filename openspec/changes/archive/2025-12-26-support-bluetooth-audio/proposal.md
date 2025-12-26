# support-bluetooth-audio Change Proposal

## Summary

Add seamless Bluetooth audio support to the Relagent app for both speech recognition (ASR) and text-to-speech (TTS) playback. When a Bluetooth headset is connected, the app should automatically route microphone input from the Bluetooth microphone and audio output to the Bluetooth speakers/headphones, matching user expectations from other voice apps.

## Motivation

**User Problem:**
Currently, the app does not reliably use Bluetooth headsets for audio input/output. Previous experiments showed Bluetooth playback never worked seamlessly. Users expect that when they connect a Bluetooth headset, all voice interactions should automatically route through that device - just like phone calls or voice assistants.

**Business Value:**
- **Hands-free usability**: Essential for the primary use case of hands-free voice interaction
- **Privacy**: Bluetooth headsets allow private conversations in public spaces
- **Mobility**: Users can move around freely while using the app
- **Professional use**: Required for reliable use during walking, driving, or other activities

**Current Gaps:**
1. Recording uses `AudioManagerMode.modeNormal` which routes to A2DP (music) instead of SCO (voice) - Bluetooth microphone doesn't work
2. Audio session configuration doesn't explicitly enable Bluetooth routing or configure per-mode
3. No detection of Bluetooth device connect/disconnect events
4. No user feedback about which audio device is active

## Scope

**In Scope:**
- Automatic Bluetooth microphone routing for ASR when Bluetooth headset is connected
- Automatic Bluetooth speaker routing for TTS playback when Bluetooth headset is connected
- Detection and adaptation to Bluetooth device connections/disconnections
- Proper audio session configuration for voice communication vs media playback
- Platform-specific configuration (Android permissions, iOS Info.plist)
- Seamless transitions between Bluetooth and phone audio devices
- Research and validation of current audio stack (record, just_audio, audio_session)

**Out of Scope:**
- Manual device selection UI (system handles routing automatically)
- Support for multiple simultaneous Bluetooth devices
- Bluetooth device pairing functionality (handled by OS)
- Audio quality tuning beyond default Bluetooth codec
- Support for Bluetooth classic vs BLE audio distinction
- Recording from phone microphone while playing to Bluetooth speakers (mutual exclusivity maintained)

**Affected Components:**
- Audio recording configuration (`speech_recognition/services.dart`)
- Audio session management (`providers/background_service_provider.dart`)
- Android manifest permissions
- iOS Info.plist configuration (if needed)
- Audio coordinator (minimal - detection of device changes)

**No Breaking Changes:**
- Existing audio coordination and health monitoring remain unchanged
- Voice mode behavior unchanged (only routing changes)
- API compatibility maintained

## Success Criteria

**Functional Requirements:**
- [ ] ASR uses Bluetooth microphone when Bluetooth headset connected
- [ ] TTS plays through Bluetooth speakers when Bluetooth headset connected
- [ ] Seamless transition when Bluetooth connects mid-session
- [ ] Seamless transition when Bluetooth disconnects mid-session
- [ ] No audio dropouts during Bluetooth switching
- [ ] Health monitoring doesn't trigger false recoveries during device changes

**Technical Requirements:**
- [ ] Android: Recording uses `AudioManagerMode.communication` for Bluetooth SCO
- [ ] Audio session configured per mode (recording vs playback) with explicit Bluetooth enablement
- [ ] Device change detection via `audio_session.devicesChangedEventStream`
- [ ] Android: `BLUETOOTH_CONNECT` permission added for API 31+
- [ ] iOS: Bluetooth category options properly configured

**User Experience:**
- [ ] Works identically to phone calls and voice assistants regarding Bluetooth
- [ ] No manual configuration required - automatic routing
- [ ] Existing audio focus handling continues to work
- [ ] Background listening works with Bluetooth devices

**Non-Goals:**
- Device selection UI
- Bluetooth connection indicators (future enhancement)
- Support for recording from phone mic while playing to Bluetooth

## Implementation Approach

### Research Phase

1. **Validate Current Stack** (record, just_audio, audio_session)
   - Confirm packages support Bluetooth routing
   - Identify configuration requirements
   - Review package documentation and known issues

2. **Consult Mobile Expert**
   - Platform-specific Bluetooth audio requirements
   - Common pitfalls and debugging strategies
   - Best practices for seamless transitions

3. **Web Research**
   - Latest Flutter Bluetooth audio patterns (2025)
   - Known issues with current package versions
   - Alternative approaches if current stack insufficient

### Implementation Phases

**Phase 1: Critical Fixes (Immediate Impact)**
- Change `AudioManagerMode.modeNormal` to `AudioManagerMode.communication`
- Add `BLUETOOTH_CONNECT` permission for Android 12+
- Test basic Bluetooth routing

**Phase 2: Audio Session Enhancement (Robust Routing)**
- Implement mode-specific audio session configuration
  - `_configureAudioSessionForRecording()` with SCO/voiceCommunication
  - `_configureAudioSessionForPlayback()` with media/assistant usage
- Activate audio session explicitly after configuration
- Call configuration methods from `_syncServiceWithAudioMode()`

**Phase 3: Device Change Detection (Seamless UX)**
- Subscribe to `devicesChangedEventStream`
- Log device changes for debugging
- Optionally reconfigure audio session on device changes
- Test connect/disconnect scenarios

**Phase 4: Testing & Refinement**
- Test on physical devices with various Bluetooth headsets
- Verify recording quality through Bluetooth microphone
- Verify playback routing to Bluetooth speakers
- Test interrupt scenarios (calls, disconnects, focus loss)
- Validate health monitoring doesn't interfere

## Risks and Mitigations

**Technical Risks:**
1. **Risk:** Package limitations prevent proper Bluetooth routing
   - **Mitigation:** Research confirmed `record` + `audio_session` support Bluetooth with correct configuration
   - **Fallback:** Use platform channels for direct AudioManager access (high complexity)

2. **Risk:** Audio session changes break existing focus handling
   - **Mitigation:** Preserve existing interrupt handlers, only enhance configuration
   - **Testing:** Comprehensive interrupt testing (calls, notifications, etc.)

3. **Risk:** Bluetooth SCO connection delays cause audio dropouts
   - **Mitigation:** Add small delay before starting recording if Bluetooth detected
   - **Testing:** Measure and optimize delay timing

4. **Risk:** Device-specific Bluetooth quirks (manufacturers vary)
   - **Mitigation:** Test on multiple devices (Samsung, Google, etc.)
   - **Fallback:** Document known device issues

**User Experience Risks:**
1. **Risk:** Users confused by automatic routing (expect manual control)
   - **Mitigation:** Match OS behavior - automatic routing is standard
   - **Future:** Add optional Bluetooth indicator in settings

2. **Risk:** Bluetooth microphone quality worse than phone mic
   - **Mitigation:** Use `AudioManagerMode.communication` for echo cancellation
   - **Acceptance:** Users choosing Bluetooth accept quality tradeoff

**Timeline Risks:**
1. **Risk:** Testing on physical devices takes longer than expected
   - **Mitigation:** Prioritize Phase 1 (quick win), defer Phase 3 if needed
   - **Plan:** Phase 1 can ship independently

## Dependencies

**External Dependencies:**
- Current package versions (already in `pubspec.yaml`):
  - `record: ^6.1.2` - Supports Bluetooth with correct configuration
  - `audio_session: ^0.2.2` - Provides Bluetooth category options (consider upgrade to 0.2.3)
  - `just_audio: ^0.10.5` - Respects audio session configuration
- No new package dependencies required

**Platform Dependencies:**
- Android 12+ (API 31+) requires `BLUETOOTH_CONNECT` permission
- Android SCO Bluetooth requires `MODIFY_AUDIO_SETTINGS` (already present)
- iOS requires `UIBackgroundModes: audio` (likely already present)

**Internal Dependencies:**
- Existing audio coordination (`AudioCoordinatorProvider`)
- Existing background service (`BackgroundServiceProvider`)
- Existing health monitoring (`RecordingProvider`)
- No changes to these components required

**Test Dependencies:**
- Physical Android/iOS devices with Bluetooth capability
- Bluetooth headsets for testing (multiple brands recommended)
- Manual testing required (automated Bluetooth testing infeasible)

## Alternatives Considered

### Alternative 1: Use flutter_sound instead of record
**Pros:**
- More control over audio routing
- Unified recording + playback API

**Cons:**
- Heavier package (larger app size)
- Breaking change (replace entire recording stack)
- Current `record` package sufficient with correct configuration

**Decision:** Rejected - stick with current stack

### Alternative 2: Manual device selection UI
**Pros:**
- User has explicit control
- Clear which device is active

**Cons:**
- More complex UX
- Not standard OS behavior (calls/assistants auto-route)
- Additional development time

**Decision:** Deferred - automatic routing first, manual selection as future enhancement

### Alternative 3: Platform channels for direct AudioManager access
**Pros:**
- Full control over Bluetooth SCO lifecycle
- Can handle edge cases not supported by packages

**Cons:**
- High complexity (Java/Kotlin and Swift/Objective-C code)
- Maintenance burden (OS version compatibility)
- Duplicates functionality already in packages

**Decision:** Rejected - only consider if package approach fails

### Alternative 4: Separate audio modes for Bluetooth vs phone
**Pros:**
- Could optimize per device type
- More granular control

**Cons:**
- Adds complexity to audio coordinator
- Users don't care about internal distinction
- Current mutual exclusivity (recording vs playback) sufficient

**Decision:** Rejected - transparency is better UX

## Design Decisions (Resolved)

All technical decisions have been made and documented in `design.md`:

1. **audio_session package version:** ✅ Keep 0.2.2 (already latest stable)
2. **TTS audio usage:** ✅ Use `AndroidAudioUsage.assistant` for consistency and low latency
3. **Bluetooth SCO delay:** ✅ No delay initially, add instrumentation to measure actual delays
4. **Device change handling:** ✅ Log only, trust OS routing (add reconfiguration if testing shows issues)
5. **iOS configuration:** ✅ Add required Info.plist entries (microphone description, background audio mode)

See `design.md` section "Design Decisions (Resolved)" for detailed rationale.

## Related Changes

**Existing Changes:**
- `differentiate-build-types` (0/52 tasks) - Independent, no conflicts

**Existing Specs:**
- `background-audio-management` - Not modified (health monitoring unchanged)
- `user-settings` - Not modified (no new user settings for Bluetooth)

**Future Enhancements:**
- Bluetooth connection indicator (visual feedback of active device)
- Manual device selection UI (override automatic routing)
- Audio quality settings per device type
- Bluetooth reconnection handling (when device goes out of range)

# Implementation Tasks

## Status Summary

**Last Updated:** 2025-12-15
**Overall Progress:** 40/86 tasks completed (47%)

### Implementation Commits
- `b4a5e80` - Implement dynamic wake lock timeout based on user duration settings
- `fd55c9f` - Add polling-based interruption detection for audio focus (fix for phone calls)
- `aafe561` - Update tasks.md with completion status
- `540ff64` - Detect audio interruptions via RecordState changes (initial attempt)
- `a86ef27` - Fix notification update logic for waiting state
- `4162a37` - Add listener for waiting state changes
- `b2adc41` - Fix missing notification on initial app start
- `73cba84` - Fix type casting for duration parameter in MainActivity

### Related Work Completed (Not Part of This Change)
The following infrastructure improvements have been made but are not part of the tasks below:
- ✅ Migrated background service to Riverpod 3.x API (commit ea66e61)
- ✅ Added notification controls with unified stop action (commits 9b25846, 45be8da)
- ✅ Implemented audio interruption handling with audio_session (commit eb4bd9b)
- ✅ Added audio focus change handling (commit 37e3ecf)

### Tasks Breakdown
- Section 1 (Settings): ✅ 5/5 complete
- Section 2 (Error Handling): ✅ 5/5 complete
- Section 3 (Health Monitoring): ✅ 5/5 complete
- Section 4 (Auto-Recovery): ✅ 5/5 complete
- Section 5 (Auto-Shutoff): ✅ 5/5 complete
- Section 6 (Wake Lock): ✅ 5/5 complete
- Section 7 (Time Display): ✅ 5/5 complete
- Section 8 (Notifications): ✅ 5/5 complete
- Section 9 (Testing): 0/10 complete (requires manual testing)
- Section 10 (Documentation): 0/4 complete

---

## 1. Settings Model and UI ✅

- [x] 1.1 Add `BackgroundListeningDuration` enum to settings.dart with options (5min-24h, unlimited)
- [x] 1.2 Add `backgroundListeningDuration` field to Settings class with default oneHour
- [x] 1.3 Update SettingsProvider to persist/restore new setting
- [x] 1.4 Add UI dropdown in settings_page.dart for duration selection
- [x] 1.5 Update settings UI tests

## 2. Audio Stream Error Handling ✅

- [x] 2.1 Add `onAudioDataReceived` callback parameter to ASR class
- [x] 2.2 Add onError handler to stream.listen() in ASR.start() that logs and notifies failure
- [x] 2.3 Add onDone handler to stream.listen() that detects unexpected closure
- [x] 2.4 Call `onAudioDataReceived` callback on each audio chunk received
- [x] 2.5 Add error field to RecordingState for displaying stream errors

## 3. Health Monitoring System ✅

- [x] 3.1 Add RecordingHealthMonitor class to recording_provider.dart
- [x] 3.2 Implement startMonitoring() that creates Timer (every 30s)
- [x] 3.3 Implement checkHealth() that verifies recordState and lastAudioDataTime
- [x] 3.4 Track lastAudioDataTime via ASR callback
- [x] 3.5 Implement stopMonitoring() that cancels Timer and resets state

## 4. Auto-Recovery Logic ✅

- [x] 4.1 Implement attemptRecovery() with exponential backoff (0s, 2s, 5s)
- [x] 4.2 Track recoveryAttempts counter (reset on successful recording)
- [x] 4.3 After 3 failed attempts, call gracefulDegradation()
- [x] 4.4 Implement gracefulDegradation() that switches to Silent and shows notification
- [x] 4.5 Add debug logging for all recovery events

## 5. Duration-Based Auto-Shutoff ✅

- [x] 5.1 Add duration Timer to RecordingProvider (started when entering continuous recording)
- [x] 5.2 Calculate timeout from settings.backgroundListeningDuration
- [x] 5.3 On timeout, call settingsProvider.updateVoiceMode(VoiceMode.silent)
- [x] 5.4 Cancel timer when leaving continuous recording
- [x] 5.5 Skip timer creation for unlimited setting

## 6. Native Service Wake Lock Updates ✅

- [x] 6.1 Update AudioBackgroundService.kt to accept duration parameter in intent
- [x] 6.2 Calculate wake lock timeout as setting duration + 5 minutes
- [x] 6.3 For unlimited setting, use 24 hour timeout
- [x] 6.4 Update BackgroundServiceProvider to pass duration when starting service
- [x] 6.5 Remove hardcoded 10-minute timeout

## 7. Notification Time Display ✅

- [x] 7.1 Add end time calculation to AudioBackgroundService
- [x] 7.2 Update notification text to include "ends at HH:MM" for limited durations
- [x] 7.3 Schedule notification updates every 60 seconds
- [x] 7.4 Skip time display for unlimited setting
- [x] 7.5 Cancel scheduled updates when service stops

## 8. User Notification for Failures ✅

- [x] 8.1 Add notification helper method in AudioBackgroundService for failure alerts
- [x] 8.2 Create notification channel for error notifications (separate from service channel)
- [x] 8.3 Call notification from gracefulDegradation() via platform channel
- [x] 8.4 Add "Open Settings" action to notification
- [x] 8.5 Test notification on Android 12+ with background restrictions

## 9. Testing and Validation

- [ ] 9.1 Test health monitoring detects and recovers from simulated audio stream failure
- [ ] 9.2 Test duration timeout transitions to Silent at correct time for each setting
- [ ] 9.3 Test unlimited setting doesn't timeout
- [ ] 9.4 Test graceful degradation shows notification after 3 failed recoveries
- [ ] 9.5 Test wake lock persists for setting duration + buffer
- [ ] 9.6 Test notification time display updates correctly
- [ ] 9.7 Verify no battery regression from health monitoring Timer
- [ ] 9.8 Test on device backgrounded for multiple hours
- [ ] 9.9 Test recovery from airplane mode toggle (audio hardware disruption)
- [ ] 9.10 Run full regression test suite

## 10. Documentation

- [ ] 10.1 Update apps/CLAUDE.md with health monitoring architecture
- [ ] 10.2 Update settings documentation with new duration setting
- [ ] 10.3 Add troubleshooting guide for "listening stopped" notification
- [ ] 10.4 Document recovery attempt logging for debugging

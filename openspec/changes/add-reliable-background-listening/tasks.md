# Implementation Tasks

## Status Summary

**Last Updated:** 2025-12-13
**Overall Progress:** 0/86 tasks completed (0%)

### Related Work Completed (Not Part of This Change)
The following infrastructure improvements have been made but are not part of the tasks below:
- ✅ Migrated background service to Riverpod 3.x API (commit ea66e61)
- ✅ Added notification controls with unified stop action (commits 9b25846, 45be8da)
- ✅ Implemented audio interruption handling with audio_session (commit eb4bd9b)
- ✅ Added audio focus change handling (commit 37e3ecf)

### Critical Remaining Issue
⚠️ **AudioBackgroundService.kt line 178** still contains the hardcoded 10-minute wake lock timeout that this change aims to make configurable.

### Tasks Breakdown
- Section 1 (Settings): 0/5 complete
- Section 2 (Error Handling): 0/5 complete
- Section 3 (Health Monitoring): 0/5 complete
- Section 4 (Auto-Recovery): 0/5 complete
- Section 5 (Auto-Shutoff): 0/5 complete
- Section 6 (Wake Lock): 0/5 complete
- Section 7 (Time Display): 0/5 complete
- Section 8 (Notifications): 0/5 complete
- Section 9 (Testing): 0/10 complete
- Section 10 (Documentation): 0/4 complete

---

## 1. Settings Model and UI

- [ ] 1.1 Add `BackgroundListeningDuration` enum to settings.dart with options (30min, 1h, 2h, 4h, unlimited)
- [ ] 1.2 Add `backgroundListeningDuration` field to Settings class with default oneHour
- [ ] 1.3 Update SettingsProvider to persist/restore new setting
- [ ] 1.4 Add UI dropdown in settings_page.dart for duration selection
- [ ] 1.5 Update settings UI tests

## 2. Audio Stream Error Handling

- [ ] 2.1 Add `onAudioDataReceived` callback parameter to ASR class
- [ ] 2.2 Add onError handler to stream.listen() in ASR.start() that logs and notifies failure
- [ ] 2.3 Add onDone handler to stream.listen() that detects unexpected closure
- [ ] 2.4 Call `onAudioDataReceived` callback on each audio chunk received
- [ ] 2.5 Add error field to RecordingState for displaying stream errors

## 3. Health Monitoring System

- [ ] 3.1 Add RecordingHealthMonitor class to recording_provider.dart
- [ ] 3.2 Implement startMonitoring() that creates Timer (every 30s)
- [ ] 3.3 Implement checkHealth() that verifies recordState and lastAudioDataTime
- [ ] 3.4 Track lastAudioDataTime via ASR callback
- [ ] 3.5 Implement stopMonitoring() that cancels Timer and resets state

## 4. Auto-Recovery Logic

- [ ] 4.1 Implement attemptRecovery() with exponential backoff (0s, 2s, 5s)
- [ ] 4.2 Track recoveryAttempts counter (reset on successful recording)
- [ ] 4.3 After 3 failed attempts, call gracefulDegradation()
- [ ] 4.4 Implement gracefulDegradation() that switches to Silent and shows notification
- [ ] 4.5 Add debug logging for all recovery events

## 5. Duration-Based Auto-Shutoff

- [ ] 5.1 Add duration Timer to RecordingProvider (started when entering continuous recording)
- [ ] 5.2 Calculate timeout from settings.backgroundListeningDuration
- [ ] 5.3 On timeout, call settingsProvider.updateVoiceMode(VoiceMode.silent)
- [ ] 5.4 Cancel timer when leaving continuous recording
- [ ] 5.5 Skip timer creation for unlimited setting

## 6. Native Service Wake Lock Updates

- [ ] 6.1 Update AudioBackgroundService.kt to accept duration parameter in intent
- [ ] 6.2 Calculate wake lock timeout as setting duration + 5 minutes
- [ ] 6.3 For unlimited setting, use 24 hour timeout
- [ ] 6.4 Update BackgroundServiceProvider to pass duration when starting service
- [ ] 6.5 Remove hardcoded 10-minute timeout

## 7. Notification Time Display (Optional)

- [ ] 7.1 Add remaining time calculation to AudioBackgroundService
- [ ] 7.2 Update notification text to include "Xh Ym remaining" for limited durations
- [ ] 7.3 Schedule notification updates every 60 seconds
- [ ] 7.4 Skip time display for unlimited setting
- [ ] 7.5 Cancel scheduled updates when service stops

## 8. User Notification for Failures

- [ ] 8.1 Add notification helper method in AudioBackgroundService for failure alerts
- [ ] 8.2 Create notification channel for error notifications (separate from service channel)
- [ ] 8.3 Call notification from gracefulDegradation() via platform channel
- [ ] 8.4 Add "Open Settings" action to notification
- [ ] 8.5 Test notification on Android 12+ with background restrictions

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

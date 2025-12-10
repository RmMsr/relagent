# Design: Reliable Time-Limited Background Listening

## Context

The current background audio implementation lacks robustness for long-running sessions:
- After ~10 minutes, wake lock expires and Android can stop recording
- No detection or recovery when audio stream dies
- State diverges from reality (app thinks it's recording, but hardware has stopped)
- Users have no control over battery consumption from unlimited listening

This affects:
- **RecordingProvider** - Manages ASR lifecycle
- **ASR class** - Audio stream and Sherpa-ONNX interface
- **BackgroundServiceProvider** - Native foreground service coordination
- **AudioBackgroundService** (Kotlin) - Android wake lock and notification
- **Settings** - User preferences

## Goals / Non-Goals

### Goals
- Detect when audio recording unexpectedly stops
- Automatically recover from transient failures
- Gracefully degrade to Silent mode when recovery fails
- Allow users to limit background listening duration for battery conservation
- Maintain synchronization between app state and actual recording status
- Provide clear user feedback when failures occur

### Non-Goals
- Audio quality improvements
- Multi-language ASR support
- Recording audio to disk for debugging
- Advanced power management metrics/analytics
- Recovery from system-level audio device failures (headphones unplugged, etc.)

## Decisions

### 1. Health Monitoring Architecture

**Decision**: Implement two-level health monitoring - stream-level and periodic checks

**Rationale**:
- Stream-level (onError, onDone): Immediate detection of stream failures
- Periodic checks (Timer): Catch silent failures where stream is open but no data flows

**Implementation**:
- Add onError/onDone handlers to `stream.listen()` in ASR.start()
- Add Timer in RecordingProvider that runs every 30 seconds
- Track `lastAudioDataTime` in ASR, exposed via callback
- Health check verifies: RecordState matches expected && audio data received recently

**Alternatives considered**:
- Single approach (only stream handlers OR only periodic): Misses either immediate failures or silent ones
- More frequent checks (every 5s): Unnecessary overhead, 30s is sufficient
- Less frequent checks (every 2min): Too slow to detect issues

### 2. Time Limit Setting

**Decision**: Add enum-based `backgroundListeningDuration` setting with predefined options

**Rationale**:
- Predefined durations (30min, 1h, 2h, 4h, unlimited) cover common use cases
- Simpler UX than free-form time input
- Default 1 hour balances usability and battery conservation
- Enum is easier to validate and display in UI

**Implementation**:
- Add `BackgroundListeningDuration` enum to settings.dart
- Default: `oneHour`
- Timer starts when entering Recording mode, cancelled when leaving
- On timeout: transition to Silent mode via settingsProvider.updateVoiceMode()

**Alternatives considered**:
- Free-form minutes input: More flexible but harder to use, prone to errors
- No time limit: Original problem of battery drain
- Fixed durations without unlimited: Restricts power users

### 3. Wake Lock Timeout Strategy

**Decision**: Set wake lock timeout to user's setting + 5 minute buffer

**Rationale**:
- Aligns with user's expected background duration
- 5 minute buffer prevents race conditions at timeout boundary
- For "unlimited" setting, use 24 hour wake lock with renewal mechanism

**Implementation**:
- In AudioBackgroundService.kt, read duration from intent extra
- Calculate timeout: `settingDuration + 5 minutes` (or 24h for unlimited)
- For unlimited: Set 24h timeout, renew every 20 hours via scheduled check

**Alternatives considered**:
- Fixed long timeout (e.g., always 24h): Wastes resources when user wants shorter duration
- No wake lock: Android will kill recording unpredictably
- Infinite wake lock: Android may kill it anyway, safety timeout is better

### 4. Auto-Recovery Strategy

**Decision**: Three-strike recovery with exponential backoff, then graceful degradation

**Rationale**:
- Transient failures (brief audio focus loss, momentary resource constraint) should auto-recover
- Persistent failures (broken audio hardware, permissions revoked) should notify user and stop
- Exponential backoff prevents CPU/battery drain from rapid retry loops

**Implementation**:
```
Attempt 1: Immediate restart
Attempt 2: 2 second delay, restart
Attempt 3: 5 second delay, restart
Failure 3: Switch to Silent, show notification
```

**Alternatives considered**:
- Unlimited retries: Battery drain, poor UX if truly broken
- No retries: Too aggressive, fails on transient issues
- Linear backoff: Doesn't adapt to failure severity

### 5. User Notification Strategy

**Decision**: Minimal notifications - only when auto-recovery fails and going Silent

**Rationale**:
- Successful auto-recovery is transparent (desired behavior)
- Failed recovery requires user attention (needs notification)
- Don't spam notifications during temporary issues

**Implementation**:
- Show Android notification when switching to Silent due to irrecoverable failure
- Notification content: "Listening stopped - could not recover audio recording"
- Action: "Open Settings" to re-enable or troubleshoot

**Alternatives considered**:
- Notify on every recovery attempt: Noisy, distracting
- No notifications ever: User may not realize listening stopped
- In-app only notification: User may not see if app is backgrounded

### 6. Remaining Time Display (Optional)

**Decision**: Show remaining time in notification content when non-unlimited

**Rationale**:
- Helps users know when timeout will occur
- Simple to implement - format duration and update every minute
- Only shown for limited durations (not "unlimited")

**Implementation**:
- In AudioBackgroundService, when mode=recording and duration!=unlimited:
  - Calculate remaining = (startTime + duration) - now
  - Format as "Listening... (1h 23m remaining)"
  - Update notification every 60 seconds

**Alternatives considered**:
- Always show even for unlimited: Redundant ("unlimited" is clear)
- Don't show at all: Less user awareness of when timeout occurs
- Show in seconds: Too granular, distracting

## Data Model Changes

### Settings Model (apps/lib/models/settings.dart)

```dart
enum BackgroundListeningDuration {
  thirtyMinutes(Duration(minutes: 30)),
  oneHour(Duration(hours: 1)),
  twoHours(Duration(hours: 2)),
  fourHours(Duration(hours: 4)),
  unlimited(null);

  final Duration? duration;
  const BackgroundListeningDuration(this.duration);
}

class Settings {
  // ... existing fields
  final BackgroundListeningDuration backgroundListeningDuration;

  Settings({
    // ... existing params
    this.backgroundListeningDuration = BackgroundListeningDuration.oneHour,
  });
}
```

### Health Monitoring State (apps/lib/providers/recording_provider.dart)

```dart
class RecordingHealthMonitor {
  Timer? _healthCheckTimer;
  int _recoveryAttempts = 0;
  DateTime? _lastAudioDataTime;

  void startMonitoring();
  void stopMonitoring();
  Future<void> checkHealth();
  Future<void> attemptRecovery();
}
```

## Component Interactions

```
User changes voice mode to Listening/Conversation
  → SettingsProvider updates voiceMode
  → RecordingProvider detects change, starts continuous recording
  → RecordingProvider starts health monitoring Timer
  → RecordingProvider starts duration Timer (based on setting)
  → AudioCoordinator transitions to Recording mode
  → BackgroundServiceProvider syncs with mode, starts service
  → AudioBackgroundService acquires wake lock (duration + 5min)
  → ASR starts audio stream, sets lastAudioDataTime on each chunk

Health check (every 30s)
  → RecordingProvider.checkHealth()
  → Verify: recordState == RecordState.record
  → Verify: (now - lastAudioDataTime) < 2 minutes
  → If either fails: attemptRecovery()

Recovery attempt
  → Stop ASR (internalStop)
  → Wait exponential backoff (0s, 2s, 5s)
  → Restart ASR (internalStart)
  → Increment recoveryAttempts
  → If 3 attempts exhausted: gracefulDegradation()

Graceful degradation
  → SettingsProvider.updateVoiceMode(VoiceMode.silent)
  → Show notification: "Listening stopped - could not recover"
  → Stop health monitoring
  → Release audio resources

Duration timeout
  → Duration Timer fires
  → SettingsProvider.updateVoiceMode(VoiceMode.silent)
  → Normal shutdown flow (health monitoring stops, resources released)
```

## Risks / Trade-offs

### Risk: Health check overhead
- **Impact**: Timer running every 30s might impact battery
- **Mitigation**: 30s is infrequent enough to be negligible. Health check is lightweight (2 comparisons).
- **Trade-off**: Accepted - reliability is more important than minimal battery savings

### Risk: Wake lock renewal complexity
- **Impact**: For unlimited setting, renewing 24h wake lock every 20h adds complexity
- **Mitigation**: Use Android's AlarmManager to schedule renewal intent. If renewal fails, user notification.
- **Trade-off**: Accepted - unlimited mode is opt-in for users who need it

### Risk: False positives in health check
- **Impact**: Audio data might briefly pause (user not speaking) triggering false recovery
- **Mitigation**: 2-minute threshold for "no audio data" is long enough to avoid false positives
- **Trade-off**: Accepted - 2 minutes of silence is reasonable, user unlikely to be speaking continuously that long

### Risk: Recovery loop during actual failure
- **Impact**: Three retries with delays might take 7+ seconds before giving up
- **Mitigation**: Exponential backoff (0s, 2s, 5s) = 7s total is acceptable for background failure
- **Trade-off**: Accepted - better than failing on first transient error

### Risk: Notification spam if failures frequent
- **Impact**: If audio repeatedly fails, user gets multiple "stopped" notifications
- **Mitigation**: Once in Silent mode, don't retry unless user explicitly re-enables listening
- **Trade-off**: Accepted - frequent failures indicate serious problem needing attention

## Migration Plan

### Phase 1: Backwards Compatible Introduction
1. Add new setting with default=1 hour (most users get battery savings automatically)
2. Implement health monitoring (improves reliability for everyone)
3. Existing unlimited users: continue working as before (can opt-in to unlimited)

### Phase 2: Monitoring and Adjustment
1. Log health check failures and recovery attempts (for debugging)
2. Monitor analytics for:
   - How often recovery succeeds vs fails
   - Whether 30s/2min thresholds are appropriate
   - Battery impact of monitoring
3. Adjust thresholds if needed based on real-world data

### Rollback Plan
- If health monitoring causes issues:
  - Feature flag to disable health checks
  - Keep time limit feature (less risky)
- If time limit causes confusion:
  - Default to "unlimited" temporarily
  - Improve UI/documentation

## Open Questions

1. **Should we add a visual indicator (icon/color) in notification when recovery is attempted?**
   - Pro: User awareness of transient issues
   - Con: Might be alarming even when recovery succeeds
   - Decision: Start without, add if user feedback requests it

2. **Should health check pause when app is in foreground?**
   - Pro: Unnecessary when user can see UI state
   - Con: Failure might not be detected until backgrounded
   - Decision: Run health checks always (consistent behavior)

3. **Should recovery attempts be configurable (advanced setting)?**
   - Pro: Power users might want different thresholds
   - Con: Adds complexity, most users don't need it
   - Decision: No - fixed strategy is simpler, revisit if requested

4. **Should we persist recovery failure count across app restarts?**
   - Pro: Persistent audio issues get detected faster after restart
   - Con: Transient issues (e.g., temporary permission denial) might block future sessions
   - Decision: No - reset on app restart (fresh start is clearer)

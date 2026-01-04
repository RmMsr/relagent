# Audio Architecture and Invariants

This document describes the critical design constraints for the audio subsystem. **Violating these invariants will cause audio routing bugs, duplicate playback, and state machine corruption.**

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Audio Coordinator                        │
│  (Central state machine - SINGLE SOURCE OF TRUTH)           │
│                                                              │
│  States: idle ↔ recording, idle ↔ playing                   │
│  Lock semantics: Only one mode active at a time             │
└──────────────────┬──────────────────────────────────────────┘
                   │
         ┌─────────┴─────────┐
         │                   │
         ▼                   ▼
┌────────────────┐   ┌──────────────────┐
│   Recording    │   │    Playback      │
│   Provider     │   │    Provider      │
│                │   │                  │
│ - Requests     │   │ - Requests       │
│   recording    │   │   playback       │
│   lock         │   │   lock           │
│ - Releases     │   │ - Releases       │
│   when done    │   │   when done      │
└────────────────┘   └──────────────────┘
```

## Critical Invariants

### 1. Mutual Exclusion

**Only ONE audio mode active at any time**: `idle`, `recording`, or `playing`.

**Why**: Android audio system uses a single session. Both recording and playback require `MODE_IN_COMMUNICATION` for Bluetooth SCO - they cannot coexist.

**Enforcement**: Single `AudioMode` enum, transitions through `idle` state.

### 2. Lock Ownership

**Only the component that acquired the lock can release it.**

```dart
// CORRECT:
final granted = await requestPlayback();
if (granted) {
  // ... do playback ...
  await releasePlayback();  // OK - we own the lock
}

// INCORRECT:
if (!granted) {
  await releasePlayback();  // BUG! We don't own the lock!
}
```

**Why**: Releasing a lock you don't own interrupts the current audio holder and corrupts state.

**Bug History**: Duplicate playback bug was caused by releasing after denial.

### 3. State Transitions

**All transitions go through `idle` state** (star topology):

```
    recording
        ↕
      idle
        ↕
     playing
```

**Why**: Audio session must be reset between modes to clear Bluetooth SCO routing.

### 4. Pause/Resume Semantics

**Pause does NOT release the lock.** The lock represents session ownership, not playback state.

```dart
PlaybackStatus.paused   // Local: paused
AudioMode.playing       // Global: lock still held
```

### 5. Audio Mode Management (Android)

**Playback/recording require `MODE_IN_COMMUNICATION`** for Bluetooth SCO routing.

`MODE_NORMAL` routes to phone speaker or A2DP. AudioBackgroundService sets the mode when entering playback/recording.

## Component Responsibilities

- **AudioCoordinator**: Central state machine, enforces mutual exclusion and transitions
- **PlaybackProvider**: Queue management, player control, respects lock ownership
- **RecordingProvider**: ASR recording, health monitoring, auto-resume
- **BackgroundServiceProvider**: Mirrors state to native, manages audio_session
- **AudioBackgroundService**: Android foreground service, sets audio mode, notifications

**Key Rule**: All audio operations go through AudioCoordinator. Never bypass it.

## Common Pitfalls

1. **Releasing locks you don't own** - Only release if `request*()` returned true
2. **Bypassing AudioCoordinator** - Always use `requestRecording()`/`requestPlayback()`
3. **Releasing lock on pause** - Pause is local state, keep the lock
4. **Direct state transitions** - Always go through `idle` between modes

See code for detailed examples.

## Testing

- **Unit**: `audio_coordinator_test.dart` (state machine), `playback_provider_test.dart` (lock safety)
- **Integration**: Full flows, Bluetooth switching, interruptions
- **Manual**: Connect Bluetooth, verify routing, test pause/resume

## Debugging

**Audio routing**: Check `adb logcat -s AudioBackgroundService:D` for audio mode (should be `IN_COMMUNICATION`) and Bluetooth SCO state.

**Duplicate playback**: Look for denied playback releasing the lock.

**State corruption**: Run unit tests, verify transitions go through idle.

## Version History

- **2025-12**: Fixed duplicate playback (lock release on denial), Bluetooth routing (audio mode), pause/resume (preserve lock)

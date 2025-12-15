# Change: Add Reliable Time-Limited Background Listening

## Why

The user wants to be able to speak to the app and receive responses even if the app is in the background or the device is locked. This is already working on a basic level. Now we want the user to know and trust how long the app will be listening.

Improvements from a user eprspective:

- **Privacy transparency**: The user should know when and how long the microphone is recording
- **Battery concerns**: Users may want to limit how long background listening runs to conserve battery
- **Minimal notification noise**: The amount of appearing notification should be minimal. We need one to keep background activity (using the mic), but it should be re-used instead of being re-created every time the state changes

The current implementation has the following issues:

- **State desynchronization**: The app's internal state might shows recording is active, but the audio input stream has died
- **No user feedback**: Users have no indication that their speech is not being recognized if recording is stopped outside the app
- **No automatic recovery**: The app doesn't detect or recover from the failure

Root causes for fail states:

- Wake lock timeout (10 minutes) causes Android to stop recording after expiration
- No health monitoring of the audio recording stream
- Audio stream errors are not detected or handled
- No user-configurable time limits for background operations

## What Changes

### User-Facing Changes

- Add **Background Listening Duration** setting with options:
  - 5 minutes
  - 15 minutes
  - 30 minutes
  - 1 hour (default)
  - 2 hours
  - 3 hours
  - 6 hours
  - 12 hours
  - 24 hours
  - Unlimited (with caution due to battery drain)
- After time limit expires, app automatically switches to Silent voice mode
- Notification displays time when listening will switch off (listening until)
- If recording fails and cannot be recovered, app switches to Silent with user notification
- Whenever the app switches to Silent mode on itself (without user's request) the user get's a notification about the state change

### Technical Changes

- Implement recording health monitoring system that:
  - Periodically verifies audio stream is active
  - Detects when audio data stops flowing
  - Attempts automatic recovery when failures detected
  - Falls back to Silent mode with notification if recovery fails
- Add time-based auto-shutoff tied to user setting
- Add error handling to audio stream listener (onError, onDone handlers)
- Replace fixed wake lock timeout with setting-driven duration
- Track audio stream health metrics (time since last data)

## Impact

- **Affected specs**:

  - background-audio-management (NEW capability)
  - user-settings (MODIFIED - add time limit setting)

- **Affected code**:

  - `apps/lib/providers/background_service_provider.dart` - Remove hardcoded wake lock timeout
  - `apps/android/app/src/main/kotlin/.../AudioBackgroundService.kt` - Dynamic wake lock timeout, notification time display
  - `apps/lib/providers/recording_provider.dart` - Add health monitoring and auto-recovery
  - `apps/lib/speech_recognition/services.dart` - Add error handlers and data flow tracking
  - `apps/lib/models/settings.dart` - Add backgroundListeningDuration field
  - `apps/lib/pages/settings_page.dart` - Add UI for duration setting

- **User experience**: Better reliability and battery control, no more silent failures

- **Breaking changes**: None - existing unlimited listening behavior is still available

## Why

Continuous voice modes (continuous recording, auto-playback, background audio services) are unreliable — they frequently fail, produce confusing notifications, and don't work on macOS or iOS. The current default (`VoiceMode.conversation`) immediately activates these problematic features, frustrating new users. By gating continuous voice modes behind an opt-in experimental toggle, users get a stable default experience (dictation-only) while early adopters can still access continuous features with clear expectations about reliability and platform support.

## What Changes

- **New "Features" tab in settings** — a dedicated place for feature toggles. Both stable and experimental features will live here over time. The continuous voice mode toggle is the first entry, marked as experimental with a brief explanation that it is not yet reliable and noting that the background service is currently only implemented on Android.
- **Default voice mode changes from `conversation` to `silent`** — new installs start in dictation-only mode regardless of the toggle.
- **Chat UI hides the `VoiceModeSelector`** (playback/listening toggles in the app bar) when continuous voice modes are disabled. Only the dictation `RecorderButton` remains available.
- **Voice mode enforcement**: when the toggle is off, only `silent` and `reading` modes are available (dictation-based). Enabling the toggle unlocks `listening` and `conversation` modes. Disabling the toggle while in a continuous mode gracefully transitions to `silent`.
- **Background listening duration setting** moves to / is only visible under the continuous voice toggle, since it only applies to continuous recording.

## Capabilities

### New Capabilities
- `feature-toggles`: A new "Features" settings tab for feature toggles — both stable and experimental. The first entry is the continuous voice mode toggle, marked as experimental with platform support info and a reliability disclaimer.

### Modified Capabilities
- `user-settings`: Add `continuousVoiceEnabled` boolean (default false) to the Settings model with persistence, serialization/migration, and conditional visibility of background listening duration.
- `background-audio-management`: Background audio services, health monitoring, and wake locks only activate when the experimental continuous voice toggle is enabled.

## Impact

- **Settings model** (`lib/models/settings.dart`): New `continuousVoiceEnabled` field, default voice mode change to `silent`, JSON serialization/migration.
- **Settings provider** (`lib/providers/settings_provider.dart`): New method to toggle continuous voice, enforcement logic to clamp voice mode when toggle changes.
- **Settings UI** (`lib/pages/settings_page.dart`): New "Features" tab with continuous voice toggle (marked experimental), explanation text, and platform info. Background listening duration conditionally visible.
- **Chat pages** (`lib/pages/chat_page.dart`, `lib/pages/agentic_chat_page.dart`): Conditionally hide `VoiceModeSelector` when continuous voice is disabled.
- **VoiceModeSelector** (`lib/widgets/voice_mode_selector.dart`): No structural change, but no longer shown when feature is off.
- **Recording provider** (`lib/providers/recording_provider.dart`): Respect the toggle — refuse to enter continuous recording when disabled.
- **Background service provider** (`lib/providers/background_service_provider.dart`): Skip service activation when continuous voice is disabled.
- **Existing users**: Migration path — existing settings deserialize `continuousVoiceEnabled` as `false` (opt-in), and voice mode migrates to `silent` if currently set to a continuous mode while the toggle is off.

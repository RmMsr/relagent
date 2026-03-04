## Why

TTS playback was inaudible when the audio session transitioned from recording to playback. `AudioBackgroundService` was calling `setAudioModeForSpeech()` in `MODE_PLAYING`, which sets Android `AudioManager.MODE_IN_COMMUNICATION` — a mode intended for VoIP that routes audio to the earpiece. `MODE_IDLE` also failed to reset the mode, so `IN_COMMUNICATION` leaked from any preceding recording session into TTS playback.

## What Changes

- `AudioBackgroundService.kt`: Replace `setAudioModeForSpeech()` with `resetAudioMode()` in `MODE_PLAYING` handler so TTS plays through the loudspeaker (`MODE_NORMAL`).
- `AudioBackgroundService.kt`: Add `resetAudioMode()` call to `MODE_IDLE` handler to clear any `IN_COMMUNICATION` mode left over from a previous recording session.

## Capabilities

### New Capabilities

None — this is a bug fix within existing capabilities.

### Modified Capabilities

- `background-audio-management`: Requirement clarified — when transitioning to playback or idle mode, the Android audio mode must be reset to `NORMAL` to ensure speaker routing. `IN_COMMUNICATION` mode must only be active during active microphone recording.

## Impact

- `apps/android/app/src/main/kotlin/org/venkado/relagent/AudioBackgroundService.kt` — two-line change in mode switch handlers
- Android only — no impact on iOS or Linux
- No API changes, no new dependencies

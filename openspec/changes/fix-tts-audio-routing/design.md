## Context

`AudioBackgroundService.kt` handles Android audio mode transitions via a `MODE_*` message protocol from Flutter. In the `MODE_PLAYING` handler, `setAudioModeForSpeech()` was called — a function that sets `AudioManager.MODE_IN_COMMUNICATION` (intended for VoIP/earpiece routing). This caused TTS audio to route to the earpiece instead of the loudspeaker.

Additionally, the `MODE_IDLE` handler did not reset the audio mode, so `IN_COMMUNICATION` leaked from any preceding recording session into subsequent TTS playback.

## Goals / Non-Goals

**Goals:**
- TTS plays through the loudspeaker on Android
- `IN_COMMUNICATION` audio mode is only active during active microphone recording

**Non-Goals:**
- Changing iOS audio routing (not affected)
- Changing recording audio mode behavior (correct as-is)

## Decisions

### 1. Call `resetAudioMode()` in `MODE_PLAYING` and `MODE_IDLE` handlers

**Decision:** Replace `setAudioModeForSpeech()` with `resetAudioMode()` in the `MODE_PLAYING` handler. Add `resetAudioMode()` to the `MODE_IDLE` handler.

**Why:** `resetAudioMode()` sets `AudioManager.MODE_NORMAL`, which routes audio through the loudspeaker — the correct behavior for TTS. The `MODE_IDLE` handler must also reset to clear any `IN_COMMUNICATION` mode left by a previous recording session. This is a minimal two-line change with no API impact.

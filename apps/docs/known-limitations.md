# Known Limitations

This document describes known limitations in the Relagent app.

## Background Audio Interruptions (Phone Calls)

### Current Behavior

When a phone call or other audio interruption occurs while the app is recording or playing TTS:

- **Audio operation pauses correctly** (handled by `record` and `just_audio` packages)
- **Notification may not update** to show "Waiting..." status
- Notification continues showing "Listening..." or "Speaking..." during the call
- Audio automatically resumes when call ends (via `AudioInterruptionMode.pauseResume`)

### Why This Happens

We cannot reliably detect phone call interruptions:

1. **RecordState polling doesn't work**
   - The `record` package handles audio focus internally
   - It pauses/resumes automatically but doesn't emit RecordState change events
   - Polling `recordState` always shows `RecordState.record` even when paused

2. **audio_session interruptions are unreliable**
   - Phone calls during playback: Send `AudioInterruptionType.pause` ✅
   - Phone calls during recording: No event received ❌
   - Internal transitions (TTS→recording): Send `AudioInterruptionType.unknown` (false positive)

3. **No unified detection mechanism**
   - Different behavior for recording vs playback
   - Cannot distinguish real interruptions from app transitions

### User Impact

**Low**: Audio behaves correctly (pauses during call, resumes after), but notification state may be misleading. Users can still see the notification is active, just not that it's temporarily paused.

### Future Improvements

Potential approaches to investigate:

- Monitor Android system broadcasts for phone state changes
- Use platform channels to detect telephony state directly
- Contribute to `record` package to emit state change events on audio focus changes

### Related Code

- `apps/lib/providers/recording_provider.dart` - Recording state management
- `apps/lib/providers/background_service_provider.dart` - Interruption handling
- `apps/lib/speech_recognition/services.dart` - ASR audio focus configuration

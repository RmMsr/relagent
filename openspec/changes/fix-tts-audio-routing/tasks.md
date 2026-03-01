# Tasks: Fix TTS Audio Routing

## 1. Fix
- [x] 1.1 Replace `setAudioModeForSpeech()` with `resetAudioMode()` in `MODE_PLAYING` handler in `AudioBackgroundService.kt`
- [x] 1.2 Add `resetAudioMode()` call to `MODE_IDLE` handler in `AudioBackgroundService.kt`

## 2. Verification
- [x] 2.1 Build and install on Android device
- [x] 2.2 Manual: TTS plays through loudspeaker after a recording session
- [x] 2.3 Manual: TTS plays through loudspeaker without any preceding recording session

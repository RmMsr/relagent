# Tasks: Fix ASR Model Identity Check

## 1. Fix
- [x] 1.1 Change model comparison in `VoiceServiceNative._startRecording()` from object reference (`!=`) to model ID string (`?.modelId != ?.modelId`)

## 2. Verification
- [x] 2.1 Run `flutter analyze` — zero errors
- [x] 2.2 Run all tests — pass
- [x] 2.3 Manual: second recording starts immediately without model reload delay

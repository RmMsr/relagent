# Tasks: Fix Voice Model Startup Race

## 1. TTS Provider
- [x] 1.1 Add `ref.listen<ModelDownloadState>` in `TtsNotifier.build()` to detect when selected TTS model becomes available
- [x] 1.2 If generation tasks are in-flight when model becomes available, set `_pendingReinit = true` instead of reinitializing
- [x] 1.3 Trigger deferred reinitialization in `finally` blocks of `enqueue()` and `playNow()` when all tasks complete

## 2. Recording Provider
- [x] 2.1 Add `ref.listen<ModelDownloadState>` in `RecordingNotifier.build()` to detect when selected ASR model becomes available
- [x] 2.2 Only restart recording if `state.isContinuous && state.isRecording` when model becomes available

## 3. Verification
- [x] 3.1 Run `flutter analyze` — zero errors
- [x] 3.2 Run all tests — 116 pass

## 1. Local Types and Interfaces

- [x] 1.1 Create `lib/voice/voice_service.dart` with `AudioRecordingStatus` enum, `AudioInterruptionEvent` type, `VoiceCapabilities` mixin, and abstract `VoiceService` interface
- [x] 1.2 Create `lib/voice/model_loader.dart` with abstract `ModelLoader` interface (loadModel, loadModelFile methods)
- [x] 1.3 Create `lib/voice/voice_service_stub.dart` with `NoOpVoiceService` that returns all capabilities as unavailable and no-ops for all methods
- [x] 1.4 Add conditional import factory in `voice_service.dart`: `import 'voice_service_stub.dart' if (dart.library.io) 'voice_service_native.dart'`

## 2. Model Loader Implementation

- [x] 2.1 Create `lib/voice/asset_model_loader.dart` implementing `ModelLoader` — move existing logic from `lib/utils/files.dart` (copyAssetFileToCache, copyAssetDirectoryToCache) into this class
- [x] 2.2 Create `lib/voice/unavailable_model_loader.dart` implementing `ModelLoader` — throws `UnsupportedError` on all methods
- [x] 2.3 Update `lib/utils/files.dart` to remove `dart:io` dependency or delete the file if all logic moved to AssetModelLoader

## 3. Native Voice Service Implementation

- [x] 3.1 Create `lib/voice/voice_service_native.dart` implementing `VoiceService` — wrap existing `ASR` class for recording operations, mapping `RecordState` to `AudioRecordingStatus` at the boundary
- [x] 3.2 Add TTS integration to native `VoiceService` — wrap existing `TtsIsolateWorker` for generateSpeech, using `AssetModelLoader` for model loading
- [x] 3.3 Add audio session integration to native `VoiceService` — wrap `audio_session` package for configure/activate/deactivate and expose interruption events as local `AudioInterruptionEvent`
- [x] 3.4 Add background service integration to native `VoiceService` — wrap `MethodChannel` calls for startBackgroundService, stopBackgroundService, updateNotification, showErrorNotification

## 4. Provider Refactoring

- [x] 4.1 Add `voiceServiceProvider` and `voiceCapabilitiesProvider` Riverpod providers that expose the `VoiceService` instance and its capabilities
- [x] 4.2 Refactor `RecordingProvider` — replace `ASR` dependency with `VoiceService`, replace `RecordState` with `AudioRecordingStatus`, remove `package:record` import, route error notifications through VoiceService
- [x] 4.3 Refactor `AudioCoordinator` — replace direct `AudioSession.instance` calls with `VoiceService` audio session methods, remove `package:audio_session` import
- [x] 4.4 Refactor `BackgroundServiceNotifier` — replace `MethodChannel` and `AudioSession` usage with `VoiceService` methods, remove `package:audio_session` import, listen to `VoiceService.interruptionEvents` instead of session directly
- [x] 4.5 Refactor `TtsNotifier` and `TtsService` — use `VoiceService.generateSpeech()` instead of `TtsIsolateWorker` directly

## 5. Widget and UI Refactoring

- [x] 5.1 Update `RecordingStateIndicator` — replace `RecordState` checks with `AudioRecordingStatus`, remove `package:record` import
- [x] 5.2 Update `RecorderButton` — replace `RecordState` checks with `AudioRecordingStatus`, remove `package:record` import
- [x] 5.3 Add capability guards to chat page — hide RecorderButton, VolumeBarVisualizer, and RecordingStateIndicator when `isAsrAvailable` is false
- [x] 5.4 Add capability guards to settings page — hide voice mode selector, background listening duration, and TTS settings when voice capabilities are unavailable
- [x] 5.5 Add capability guards to message widgets — hide TTS play/pause buttons when `isTtsAvailable` is false

## 6. Configuration Updates

- [x] 6.1 Update `AppConfig` to handle missing model config gracefully on web (model fields optional or guarded)
- [x] 6.2 Verify `pubspec.yaml` dependencies — ensure `sherpa_onnx`, `record`, `audio_session` remain but are never imported on web via conditional imports

## 7. Verification

- [x] 7.1 Run `dart-flutter_analyze_files` and fix all analysis errors — confirm zero imports of `package:record`, `package:sherpa_onnx`, or `package:audio_session` outside `lib/voice/` native implementation files
- [x] 7.2 Build and test on web — verify chat page loads, text chat works, voice UI is hidden, no console errors
- [x] 7.3 Build and test on Android/Linux — verify all existing voice functionality (ASR, TTS, background listening, health monitoring) works identically to before the refactoring

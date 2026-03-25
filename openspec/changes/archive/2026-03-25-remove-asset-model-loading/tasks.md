## 1. Remove Asset-Based Model Loading Code

- [x] 1.1 Delete `apps/lib/voice/asset_model_loader.dart`
- [x] 1.2 Remove `copyAssetDirectoryToCache` from `apps/lib/utils/files.dart` (keep `copyAssetFileToCache` for `silero_vad.onnx`)
- [x] 1.3 Remove `AppConfig.speechRecognitionStreamingAsrModelName` and `AppConfig.ttsModelName` fields; remove their loading from `config.json`; simplify or delete `AppConfig` class and `config.json` if no fields remain
- [x] 1.4 Remove bundled model asset declarations from `apps/pubspec.yaml` (keep `silero_vad.onnx`)

## 2. Remove Legacy Asset Code Paths

- [x] 2.1 Remove `createOnlineRecognizer()` (asset path) from `apps/lib/speech_recognition/sherpa_streaming_asr.dart`; keep `createOnlineRecognizerFromMetadata()`
- [x] 2.2 Remove `preCacheTtsModelFiles()`, `createOfflineTts()`, and `_getAssetOfflineTtsModelConfig()` from `apps/lib/tts/sherpa_tts.dart`; keep `createOfflineTtsFromMetadata()` and `TtsModelMetadata`
- [x] 2.3 Remove asset-based TTS branch (`else` calling `createOfflineTts`) from `apps/lib/tts/tts_isolate_worker.dart`
- [x] 2.4 Remove `preCacheTtsModels()` from `VoiceService` interface, `NativeVoiceService`, and `NoOpVoiceService`
- [x] 2.5 Remove the `preCacheTtsModels()` microtask call from `apps/lib/main.dart`
- [x] 2.6 Remove `AssetModelLoader` field and `modelLoader` getter from `NativeVoiceService`; remove `import` of `asset_model_loader.dart`

## 3. Update Model Resolution Semantics

- [x] 3.1 Update `resolveAsrMetadata()` in `model_resolver.dart` — null return now means "no model available" (remove comments referencing bundled fallback)
- [x] 3.2 Update `resolveTtsModel()` in `model_resolver.dart` — same null semantics change
- [x] 3.3 Update `getSelectedTtsSpeakerCount()` — remove bundled Kokoro fallback (return 0 when no model selected)
- [x] 3.4 Update `_startASR()` in `RecordingProvider` — when `resolveAsrMetadata` returns null, set error state ("No ASR model selected") and don't attempt recording
- [x] 3.5 Update `NativeVoiceService.initializeTts()` — when no resolved model and no `AppConfig.ttsModelName`, log and return without error (already handles this, but remove the `AppConfig` reference)

## 4. Startup Model Validation

- [x] 4.1 Add model validation logic: after `ModelDownloadProvider` completes its initial scan, check `selectedAsrModelId` and `selectedTtsModelId` against `downloadedModels`; clear stale selections to null
- [x] 4.2 Wire validation into app startup (listener in `SettingsProvider` on `ModelDownloadProvider` or startup step in `main.dart`)
- [x] 4.3 Verify the settings page shows "None" when a stale selection is cleared

## 5. Voice Initialization Overlay

- [x] 5.1 Add a full-screen initialization overlay widget (semi-transparent scrim, centered card with spinner and "Initializing voice recognition…" message)
- [x] 5.2 Show the overlay in `chat_page.dart` by watching `recordingProvider.isInitializing`
- [x] 5.3 Ensure overlay renders before the blocking call: use `addPostFrameCallback` to defer `_startASR()` until after the overlay frame is painted
- [x] 5.4 Verify overlay auto-dismisses when initialization completes and does not appear on subsequent recordings

## 6. Cleanup and Verification

- [x] 6.1 Remove or archive the `unify-model-loading` change (superseded)
- [x] 6.2 Run `dart-flutter_analyze_files` and fix all analysis issues
- [x] 6.3 Run tests with `dart-flutter_run_tests` and fix failures
- [x] 6.4 Manual test: fresh app with no downloaded models — verify "No model selected" state, no crashes
- [x] 6.5 Manual test: app with downloaded models — verify recording and TTS work end-to-end
- [x] 6.6 Manual test: delete a selected model's cache files, restart app — verify stale selection is cleared

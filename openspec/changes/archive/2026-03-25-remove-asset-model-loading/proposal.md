## Why

The asset-bundled model loading path (`AssetModelLoader`, `config.json` model fields, `copyAssetFileToCache` for models) was useful before the model download system was stable. Now that download and model management is mature, this path is dead code that adds complexity — two parallel loading paths, branching logic across multiple files, and confusing "bundled vs downloaded" distinctions. Removing it simplifies the codebase and makes model loading easier to reason about.

A secondary problem: when the user starts recording for the first time, the UI freezes for several seconds while the ASR recognizer loads. This happens because model initialization runs on the main isolate. As an immediate fix, the app should show a blocking message so the user understands the delay.

## What Changes

- **BREAKING**: Remove `AssetModelLoader` and all asset-based model loading (copying from `rootBundle` to cache)
- **BREAKING**: Remove `AppConfig` model fields (`speechRecognitionStreamingAsrModelName`, `ttsModelName`) and the corresponding `config.json` entries
- Remove `copyAssetFileToCache` and `copyAssetDirectoryToCache` from `utils/files.dart`
- Remove legacy bundled-model code paths in `sherpa_tts.dart` (`createOfflineTts`, `preCacheTtsModelFiles`, `_getAssetOfflineTtsModelConfig`)
- Remove legacy bundled-model code path in `sherpa_streaming_asr.dart` (`createOnlineRecognizer`)
- Remove bundled-model fallback branches in `model_resolver.dart` (null return = "no model available", not "use bundled")
- Remove `AssetModelLoader` field and getter from `NativeVoiceService`
- Remove `preCacheTtsModels()` from `VoiceService` interface (only needed for asset copying)
- Keep `silero_vad.onnx` as a bundled asset — it's a small utility model with no download source
- Show a blocking "Initializing voice…" message on first ASR use to communicate the startup delay
- Simplify `DownloadModelLoader` to be the single model loading implementation
- On app start, validate that selected ASR/TTS models are still available in downloads — if not, clear the selection so the user sees "no model selected" instead of a broken state

## Capabilities

### New Capabilities

- `voice-init-feedback`: Show a visible blocking message when voice models are being loaded for the first time, so the user understands the delay instead of seeing a frozen UI

### Modified Capabilities

- `model-loading`: Remove `AssetModelLoader` as a runtime loader; remove asset-based requirements; `DownloadModelLoader` becomes the only `ModelLoader` implementation (plus `UnavailableModelLoader` for web); null from resolver means "no model available"
- `speech-recognition`: Remove bundled-model fallback — when no downloaded ASR model is selected, recording is unavailable; remove "fall back to bundled model" scenario
- `user-settings`: On startup, validate selected ASR/TTS model IDs against available downloads; clear stale selections automatically

## Impact

- `apps/lib/voice/asset_model_loader.dart` — **deleted**
- `apps/lib/utils/files.dart` — `copyAssetFileToCache` and `copyAssetDirectoryToCache` removed (keep file if other utilities remain, otherwise delete)
- `apps/lib/config/app_config.dart` — model name fields and their loading removed; class may become minimal or be deleted if only model fields remain
- `apps/lib/voice/voice_service_native.dart` — `AssetModelLoader` field removed, `preCacheTtsModels` removed
- `apps/lib/voice/voice_service.dart` — `preCacheTtsModels()` removed from interface
- `apps/lib/voice/model_resolver.dart` — null return semantics change (no model, not bundled fallback); `getSelectedTtsSpeakerCount` bundled default removed
- `apps/lib/tts/sherpa_tts.dart` — `preCacheTtsModelFiles`, `createOfflineTts`, `_getAssetOfflineTtsModelConfig` removed
- `apps/lib/tts/tts_isolate_worker.dart` — asset-based TTS branch in worker removed
- `apps/lib/speech_recognition/sherpa_streaming_asr.dart` — `createOnlineRecognizer` (asset path) removed
- `apps/lib/speech_recognition/sherpa_vad_asr.dart` — `silero_vad.onnx` loading via `copyAssetFileToCache` kept as special case
- `apps/lib/providers/recording_provider.dart` — show init feedback, handle "no model" state
- `apps/assets/config.json` — model fields removed or file simplified
- `apps/pubspec.yaml` — bundled model asset declarations removed (keep `silero_vad.onnx`)
- Existing change `unify-model-loading` should be archived/dropped — superseded by this simpler approach

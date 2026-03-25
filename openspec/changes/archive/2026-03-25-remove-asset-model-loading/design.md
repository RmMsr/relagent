## Context

The app has two parallel model loading paths:

- **Asset path**: `AssetModelLoader` copies model files from Flutter `rootBundle` to the cache directory on demand. Used by `createOnlineRecognizer()` and `createOfflineTts()` when no downloaded model is selected. Referenced via `NativeVoiceService._modelLoader` and the `copyAssetFileToCache`/`copyAssetDirectoryToCache` utilities.
- **Download path**: `DownloadModelLoader` reads model files directly from the download storage directory (`<cache>/models/<type>/<id>/`). Used when the user selects a downloaded model.

The asset path is no longer used in practice — `config.json` has empty model fields and no models are bundled. The branching "null means use bundled" convention in `model_resolver.dart` adds confusion.

Additionally, the first ASR use freezes the UI for several seconds because `sherpa_onnx.OnlineRecognizer(config)` runs synchronously on the main isolate. The existing `isInitializing` state in `RecordingState` sets a flag, but the UI thread is blocked so the spinner in `RecordingStateIndicator` never renders.

## Goals / Non-Goals

**Goals:**
- Remove `AssetModelLoader` and all asset-copy code paths for voice models
- Remove `AppConfig` model name fields and related `config.json` entries
- Remove `preCacheTtsModels()` from the `VoiceService` interface
- Make `DownloadModelLoader` the single runtime model loading implementation
- Keep `silero_vad.onnx` as a bundled asset (special case — no download source)
- Show a blocking full-screen overlay when ASR initializes for the first time, so the user sees a message instead of a frozen UI

**Non-Goals:**
- Moving ASR initialization to a background isolate (future change — earlier attempts failed)
- Changing `DownloadModelLoader` or `ModelDownloadService` internals
- Modifying the model catalog or download UI
- Changing TTS initialization (already runs in an isolate via `TtsIsolateWorker`)

## Decisions

### D1: Delete `AssetModelLoader` entirely

`AssetModelLoader` implements `ModelLoader` to copy files from `rootBundle` to cache. Since no models are bundled, this class is dead code. Delete the file rather than repurposing it.

- **Alternative — keep as internal utility**: No use case remains. The `BundledModelSeeder` approach from the `unify-model-loading` change is unnecessary when we're not bundling models at all.

### D2: Keep `silero_vad.onnx` via `copyAssetFileToCache`

The Silero VAD model (~2 MB) is bundled as a raw asset and has no download source. It's used only by `VadAsr._buildVad()`. Keep its `copyAssetFileToCache('silero_vad.onnx')` call as-is.

This means `copyAssetFileToCache` in `utils/files.dart` must be retained for this single use case. Remove `copyAssetDirectoryToCache` (no remaining callers).

- **Alternative — move `silero_vad.onnx` into a downloaded model's archive**: The VAD model is architecture-independent and shared across ASR models. Bundling it separately is correct.

### D3: Null from resolver means "no model available"

Currently `resolveAsrMetadata()` and `resolveTtsModel()` return null to mean "use bundled". After this change, null means "no model available — voice feature is unavailable".

Callers must handle this: `_startASR()` in `RecordingProvider` should check for null and set an error state ("No ASR model selected. Download one in Settings.") instead of proceeding with a bundled fallback.

### D4: Remove `preCacheTtsModels()` from `VoiceService`

This method exists solely to copy TTS model files from assets to cache before spawning the TTS isolate. With no bundled TTS model, it's dead code. Remove from:
- `VoiceService` interface
- `NativeVoiceService` implementation
- `NoOpVoiceService` stub
- The `main.dart` microtask call

The `TtsIsolateWorker.initialize()` already handles the downloaded model path without pre-caching.

### D5: Remove legacy asset-path functions from sherpa files

- `sherpa_streaming_asr.dart`: Delete `createOnlineRecognizer()` (asset path). Keep `createOnlineRecognizerFromMetadata()`.
- `sherpa_tts.dart`: Delete `createOfflineTts()`, `preCacheTtsModelFiles()`, and `_getAssetOfflineTtsModelConfig()`. Keep `createOfflineTtsFromMetadata()` and `TtsModelMetadata`.
- `tts_isolate_worker.dart`: Remove the `else` branch that calls `createOfflineTts(modelName: modelName)` — only the resolved-paths branch remains.

### D6: Full-screen blocking overlay for first ASR init

The problem: `RecordingProvider` sets `isInitializing = true`, then calls `_startASR()` which blocks the main thread during ONNX model loading. The UI can't render the `isInitializing` state because it's frozen.

**Solution**: Show a full-screen modal overlay *before* the blocking call using `WidgetsBinding.instance.addPostFrameCallback`. The sequence:

1. `RecordingProvider` sets `isInitializing = true`
2. UI reacts to `isInitializing` by showing a full-screen semi-transparent overlay with "Initializing voice recognition…" text and a spinner
3. After the overlay frame is rendered, `addPostFrameCallback` triggers the actual `_startASR()` call
4. The UI is frozen during model loading, but the overlay message is already visible
5. When `_startASR()` completes, `isInitializing` is set to false, overlay disappears

The overlay should be shown from the widget layer (e.g., `chat_page.dart`) by watching `recordingProvider.isInitializing`, not from the provider itself. This keeps the provider free of UI concerns.

- **Alternative — use `Future.delayed(Duration.zero)` in the provider**: Less reliable — doesn't guarantee the frame is rendered before the blocking call.
- **Alternative — move ASR init to an isolate**: Best UX but higher risk (earlier attempts failed). Planned as a separate future change.

### D7: Validate selected models on startup

On app startup, after the download state scan completes, check that the selected ASR and TTS model IDs (`settings.selectedAsrModelId`, `settings.selectedTtsModelId`) actually correspond to downloaded models. If a selected model is no longer available (deleted cache, corrupted download, missing `.complete` marker), clear the selection to null.

This must happen after `ModelDownloadProvider` finishes its initial scan (which populates `downloadedModels`). The natural place is a listener in `SettingsProvider` or a startup step in `main.dart` that runs after both providers are initialized.

Without bundled fallback, a stale selection would cause `resolveAsrMetadata` / `resolveTtsModel` to return null at recording time — which is handled correctly. But clearing stale selections proactively is better UX: the user sees "No model selected" in settings immediately, not a confusing error when they try to record.

- **Alternative — validate lazily on first use**: Works functionally but leaves stale model names visible in the settings UI, which is confusing.

### D8: Simplify `AppConfig`

Remove `speechRecognitionStreamingAsrModelName` and `ttsModelName` fields. If no other config fields remain, simplify or remove `AppConfig` and `config.json`. The `config.json` file can be kept as an empty object or removed if nothing else uses it.

## Risks / Trade-offs

**Users without downloaded models lose voice features** → Expected. The model download UI already exists and is mature. The app should clearly communicate "No model selected" with a link to settings. This is already the intended flow since `config.json` models are empty.

**`silero_vad.onnx` remains a special case** → Acceptable. It's a small utility model that all offline ASR models need, and there's no download source. The `copyAssetFileToCache` function is retained for this purpose only.

**Init overlay is a workaround, not a fix** → The real fix is isolate-based ASR init. The overlay at least makes the delay understandable to the user. A separate change spec should be created for the isolate approach.

**Dropping `unify-model-loading` change** → That change assumed bundled models would continue to exist (as `.tar.bz2`). This simpler approach removes them entirely. The existing change should be archived.

## Open Questions

- Should `config.json` be kept at all? If no other config fields exist, the file and `AppConfig` class could be deleted entirely.

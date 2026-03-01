## Context

The app currently bundles English-only ASR (zipformer2 transducer, ~55 MB) and TTS (Kokoro, ~305 MB) models as Flutter assets. The `ModelLoader` interface already abstracts model access from loading strategy, with `AssetModelLoader` as the sole implementation. Models are copied from assets to cache on first use. The `sherpa_streaming_asr.dart` hardcodes transducer config (`OnlineTransducerModelConfig`). The `sherpa_tts.dart` hardcodes Kokoro config (`OfflineTtsKokoroModelConfig`).

## Goals / Non-Goals

**Goals:**
- Users can browse, download, and select ASR/TTS models at runtime
- Support CTC model architecture for streaming ASR (enabling omnilingual model)
- Support Piper VITS TTS models alongside existing Kokoro
- Store downloaded models in permanent storage (survives cache cleanup)
- Bundled asset models continue to work as optional fallback
- Voice features degrade gracefully when no models are available

**Non-Goals:**
- Non-streaming (offline) ASR support -- not in this change
- Automatic model updates or version management
- Custom/user-provided model import
- Model training or fine-tuning
- Remote model catalog fetching (catalog is hardcoded for now)

## Decisions

### 1. New `DownloadModelLoader` implementing `ModelLoader`

**Decision**: Create a new `ModelLoader` implementation that loads models from the application support directory (permanent storage).

**Rationale**: The `ModelLoader` interface already exists and is designed for this. `AssetModelLoader` copies from assets to cache; `DownloadModelLoader` serves files from the support directory where the download manager places them. No changes needed to consumers (`VoiceService`, TTS isolate worker) -- they just get a different `ModelLoader` implementation.

**Resolution strategy**: On startup, check if user has selected models in settings. If yes, use `DownloadModelLoader`. If no and bundled assets exist, fall back to `AssetModelLoader`. If neither, voice features are disabled.

### 2. Model catalog as hardcoded Dart data

**Decision**: Define the model catalog as a Dart constant (list of model metadata objects) rather than fetching from a remote source.

**Rationale**: Simpler, no network dependency for browsing models, no API to maintain. Update the catalog with app releases. The catalog is curated (not a full mirror of sherpa-onnx releases), so it changes infrequently.

**Alternatives considered**: JSON asset file (unnecessary indirection), remote API (complexity, availability concerns).

**Catalog entry fields**: `id`, `displayName`, `languages`, `type` (asr/tts), `architecture` (transducer/ctc/vits-piper/kokoro), `supportsStreaming` (for ASR), `downloadUrl`, `downloadSizeMb`, `extractedSizeMb`, `fileStructure` (maps expected files).

### 3. Download to application support directory

**Decision**: Use `getApplicationSupportDirectory()` (not cache, not documents) with a `models/` subdirectory.

**Rationale**: `getApplicationSupportDirectory()` is permanent across app updates and not subject to cache cleanup. On Android this maps to the app's internal storage. On iOS it's backed up. On Linux it's `~/.local/share/<app>`.

**Directory structure**:
```
<support_dir>/models/
  asr/
    <model-name>/
      encoder.onnx
      tokens.txt
      ...
  tts/
    <model-name>/
      model.onnx
      tokens.txt
      espeak-ng-data/
      ...
```

### 4. Download and extraction approach

**Decision**: Download `.tar.bz2` archives via HTTP, extract using a Dart tar/bz2 library, with progress tracking.

**Rationale**: sherpa-onnx releases use `.tar.bz2` format. Dart has the `archive` package or `tar` + `bzip2` from `package:tar` and `dart:io` (bzip2 via process). The `http` package is already a dependency.

**Download flow**:
1. Download to temp file with progress callback
2. Verify download size matches expected
3. Extract to support directory
4. Write a `.complete` marker file
5. Delete temp archive
6. On failure: clean up partial extraction

### 5. ASR model architecture flexibility

**Decision**: Make `sherpa_streaming_asr.dart` configurable to support both transducer and CTC model types based on model metadata.

**Rationale**: The omnilingual CTC model uses `OnlineRecognizer` (same streaming API) but with `OnlineCtcModelConfig` instead of `OnlineTransducerModelConfig`. The streaming audio flow, endpoint detection, and recording provider integration remain identical. Only the model config construction changes.

**Config routing**: Model catalog entry specifies `architecture: 'ctc'` or `architecture: 'transducer'`. The recognizer factory reads this and builds the appropriate config. CTC models only need `encoder.onnx` + `tokens.txt` (no decoder/joiner).

### 6. TTS model type flexibility

**Decision**: Extend `sherpa_tts.dart` to support Piper VITS models alongside Kokoro.

**Rationale**: Piper models use `OfflineTtsVitsModelConfig` (model.onnx + tokens.txt + espeak-ng-data) while Kokoro uses `OfflineTtsKokoroModelConfig` (model.onnx + voices.bin + tokens.txt + espeak-ng-data). The `OfflineTts` API is the same; only the config differs.

**Shared espeak-ng-data**: All Piper models share the same espeak-ng-data directory. Download it once as a shared resource, reference from each model's config.

### 7. Model selection state in settings

**Decision**: Store selected model IDs in `SharedPreferences` via the existing `SettingsProvider`.

**Rationale**: Consistent with how other settings are stored. Two new fields: `selectedAsrModelId` and `selectedTtsModelId`. Null means "use bundled model if available, otherwise voice is disabled."

### 8. Model management UI in settings page

**Decision**: Add a "Voice Models" section to the existing settings page with model browsing and download management.

**Rationale**: Settings page already has voice-related sections. A separate page would fragment the experience. The section shows: current ASR/TTS model, browse/download button, downloaded models list with delete option.

**Alternatives considered**: Dedicated model management page (overkill for curated list), first-run wizard (too opinionated, user may want text-only first).

## Risks / Trade-offs

**Large download sizes on mobile data** → Show download size prominently, warn on cellular. Consider allowing Wi-Fi-only download preference later.

**Extraction time for large archives** → Show progress indicator. The omnilingual model (279 MB compressed) may take 30+ seconds to extract. Run extraction in isolate to avoid blocking UI.

**Storage space on low-end devices** → Show required space before download. Provide delete option for models no longer needed. Show total space used by models.

**Omnilingual CTC model quality unknown** → This is the first non-English ASR model. Quality may vary by language. Accept this risk and iterate based on user feedback. Dedicated per-language models can be added to the catalog later.

**espeak-ng GPL licensing for Piper TTS** → Already documented in `docs/limitations.md`. Piper models require espeak-ng-data which is GPL. Since models are downloaded at runtime (not bundled), the licensing situation may be different than bundling. Document this clearly.

**Interrupted downloads** → Temp file approach with `.complete` marker ensures partial downloads are detectable. Resume support not in scope (restart download on failure).

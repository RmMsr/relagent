## 1. Model Catalog

- [x] 1.1 Create model catalog data model (`lib/models/model_catalog.dart`) with fields: id, displayName, type (asr/tts), languages, architecture, supportsStreaming, downloadUrl, downloadSizeMb, fileStructure
- [x] 1.2 Populate hardcoded catalog with ASR models: omnilingual CTC int8 v2 (1600 langs, 279 MB, streaming), kroko zipformer en/de/fr (55 MB each, streaming)
- [x] 1.3 Populate hardcoded catalog with TTS models: Piper int8 voices for en, de, fr, ru, no, sv (~20 MB each), Kokoro en (99 MB int8)
- [x] 1.4 Add language-based filtering and type-based grouping methods to catalog

## 2. Model Download Manager

- [x] 2.1 Add `tar` and/or `archive` package dependency for `.tar.bz2` extraction
- [x] 2.2 Create download service (`lib/voice/model_download_service.dart`) with HTTP download, progress callback, cancellation support
- [x] 2.3 Implement archive extraction to `<support_dir>/models/<type>/<model-name>/` with `.complete` marker
- [x] 2.4 Implement partial download/extraction cleanup (delete incomplete on retry)
- [x] 2.5 Implement downloaded model scanning (list models with `.complete` marker)
- [x] 2.6 Implement model deletion (remove directory, clear selection if active)
- [x] 2.7 Create model download provider (`lib/providers/model_download_provider.dart`) with Riverpod state for download progress, downloaded models list

## 3. Download Model Loader

- [x] 3.1 Create `DownloadModelLoader` implementing `ModelLoader` that serves files from `<support_dir>/models/`
- [x] 3.2 Add `isModelAvailable(modelName)` method to `ModelLoader` interface
- [x] 3.3 Implement `isModelAvailable` in `AssetModelLoader` and `DownloadModelLoader`
- [x] 3.4 Create model loader resolution logic: downloaded model selected → `DownloadModelLoader`, else bundled assets → `AssetModelLoader`, else unavailable

## 4. ASR CTC Architecture Support

- [x] 4.1 Refactor `sherpa_streaming_asr.dart` to accept model metadata (architecture, file paths) instead of hardcoding transducer config
- [x] 4.2 Add CTC model config branch: when architecture is `ctc`, use `OnlineCtcModelConfig` with encoder-only (no decoder/joiner)
- [x] 4.3 Preserve transducer config branch for existing zipformer models
- [x] 4.4 Update `VoiceService` to pass model metadata from settings/catalog to recognizer factory

## 5. TTS Model Type Flexibility

- [x] 5.1 Refactor `sherpa_tts.dart` to accept model metadata (architecture, file paths) instead of hardcoding Kokoro config
- [x] 5.2 Add Piper VITS config branch: when architecture is `vits-piper`, use `OfflineTtsVitsModelConfig`
- [x] 5.3 Handle shared espeak-ng-data: download once, reference from all Piper models
- [x] 5.4 Update TTS isolate worker to receive model type and paths instead of hardcoded model name

## 6. Settings and Model Selection

- [x] 6.1 Add `selectedAsrModelId` and `selectedTtsModelId` fields to settings model and `SettingsProvider`
- [x] 6.2 Persist model selections in SharedPreferences
- [x] 6.3 Clear selection when selected model is deleted
- [x] 6.4 Add fallback logic: if selected model missing, try bundled assets, then report unavailable

## 7. Model Management UI

- [x] 7.1 Add "Voice Models" section to settings page showing current ASR and TTS model (or "None")
- [x] 7.2 Create model catalog browser UI with language filter and type tabs (ASR/TTS)
- [x] 7.3 Show download status per model: not downloaded (with size), downloading (with progress), downloaded (with delete option)
- [x] 7.4 Show streaming indicator badge for ASR models that support live recognition
- [x] 7.5 Implement download/cancel/delete actions from catalog UI
- [x] 7.6 Implement model selection (tap downloaded model to make it active)
- [x] 7.7 Show total storage used by downloaded models

## 8. Graceful Degradation

- [x] 8.1 Voice mode selector indicates model download required when no ASR model available
- [x] 8.2 Recording provider handles unavailable speech recognition (no model) without crash
- [x] 8.3 TTS provider handles unavailable TTS (no model) without crash
- [x] 8.4 Hide voice settings sections when no voice models are available (keep model management visible)

## 9. Asset Fallback and Config

- [x] 9.1 Make bundled assets optional: app starts without error if asset models are missing from pubspec.yaml
- [x] 9.2 Update `AppConfig` to handle missing model config gracefully (null model names)
- [x] 9.3 Ensure existing asset-based flow works unchanged when assets are present and no download model is selected

## 10. Testing and Verification

- [x] 10.1 Test model catalog filtering by language and type
- [x] 10.2 Test download + extraction + deletion lifecycle
- [x] 10.3 Test ASR with CTC model config (any compatible CTC model — omnilingual was removed as incompatible; update test or skip if no CTC model is in the catalog)
- [x] 10.4 Test TTS with Piper VITS model config
- [x] 10.5 Test fallback chain: downloaded → bundled → unavailable
- [x] 10.6 Test app startup without bundled assets (graceful degradation)

## 11. Clarify Bundled Models as Optional Download Shortcut

- [x] 11.1 Update `AppConfig` comments: replace "Ensure there is a directory…" with language that makes clear bundling is an optional shortcut to skip the download step, not a requirement
- [x] 11.2 Update `apps/assets/config.json` (and `config.template.json` if present): add a comment or field that explains the model name refers to an optionally bundled asset; null means no bundled model and the user downloads via the app
- [x] 11.3 In `sherpa_tts.dart` and `sherpa_streaming_asr.dart`, rename or re-comment the "legacy path" functions to "asset shortcut path" and clarify that bundling a model in assets is a pre-download convenience, not a deprecated pattern
- [x] 11.4 Update `apps/AGENTS.md` Static Configuration section: make explicit that `speech_recognition.streaming_asr_model` and `tts.model` are optional; describe bundling as a way to ship a model pre-installed rather than requiring the user to download it
- [x] 11.5 Update `pubspec.yaml` comment block for bundled assets to explain the trade-off: bundling increases app size but eliminates the first-run download; omitting the asset is the recommended default for distribution builds

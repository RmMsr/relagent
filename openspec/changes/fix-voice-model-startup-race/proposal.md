## Why

`ModelDownloadNotifier.build()` initializes with an empty `downloadedModels = {}` and scans the filesystem asynchronously. Both TTS (`initialize()` on chat page mount) and ASR (`checkAutoStart()` for continuous modes) read the download state before the scan completes, so they always fall back to bundled models at startup — even when the user has selected a downloaded model.

## What Changes

- `tts_provider.dart`: Add `ref.listen<ModelDownloadState>` in `build()` to reinitialize TTS when the selected model transitions from not-downloaded to downloaded. Defers reinit (`_pendingReinit` flag) if a generation is in-flight to avoid killing the active isolate and leaving `responsePort.first` hanging forever.
- `recording_provider.dart`: Add matching `ref.listen<ModelDownloadState>` to restart ASR with the correct model once it becomes available — only if currently recording in continuous mode (to avoid starting recording unexpectedly).

## Capabilities

### New Capabilities

None — this is a bug fix within existing capabilities.

### Modified Capabilities

- `model-loading`: Requirement added — providers must handle the case where the selected model is not yet visible in download state at initialization time, and must reinitialize when it becomes available.
- `speech-recognition`: Requirement added — ASR provider must use the selected downloaded model even when startup scan completes after recording begins.

## Impact

- `apps/lib/providers/tts_provider.dart` — new `_pendingReinit` field, `modelDownloadProvider` listener, deferred reinit in `enqueue()`/`playNow()` finally blocks
- `apps/lib/providers/recording_provider.dart` — new `modelDownloadProvider` listener
- No API changes, no new dependencies

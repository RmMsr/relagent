## Why

Bundled models use a separate runtime loading path (`AssetModelLoader`) from downloaded models (`DownloadModelLoader`), causing branching logic throughout the codebase and showing bundled vs. downloaded as conceptually different things. Treating bundled models as pre-seeded downloads eliminates this split and makes the model list a single unified view.

## What Changes

- Bundled model archives (`.tar.bz2`) are stored in `assets/voice-models/` — one file per bundled model
- On first app launch, each bundled archive is extracted to `getApplicationSupportDirectory()/models/` using the existing `ModelDownloadService` extraction code, then the `.complete` marker is written
- From that point on, `DownloadModelLoader` handles all runtime loading — no special bundled path
- `AssetModelLoader` is removed as a runtime loader (may be retained as an internal seeding utility or deleted entirely)
- **BREAKING**: The multi-file asset directory trees in `pubspec.yaml` are replaced by one `.tar.bz2` line per bundled model
- The two-path branches in `model_resolver.dart`, `voice_service_native.dart`, `sherpa_tts.dart`, and `sherpa_streaming_asr.dart` are removed
- Bundled models appear in the model list as already-installed, indistinguishable from user-downloaded models

## Capabilities

### New Capabilities

_(none — this is a refactor, all new behavior is within existing capabilities)_

### Modified Capabilities

- `model-loading`: Remove `AssetModelLoader` as a runtime loader; add a startup seeding step that extracts bundled `.tar.bz2` assets into download storage; unify all runtime model loading through `DownloadModelLoader`
- `user-settings`: Settings page warns when the selected ASR or TTS model is not loaded and therefore unusable

## Impact

- `apps/lib/voice/asset_model_seeder.dart` — new seeding utility (extracts bundled archives on first launch)
- `apps/lib/voice/asset_model_loader.dart` — removed or repurposed
- `apps/lib/models/model_resolver.dart` — two-path branching removed; always uses `DownloadModelLoader`
- `apps/lib/tts/sherpa_tts.dart` — legacy asset-path branch removed
- `apps/lib/speech_recognition/sherpa_streaming_asr.dart` — legacy asset-path branch removed
- `apps/lib/voice/voice_service_native.dart` — bundled-model path removed
- `apps/lib/main.dart` — add seeding step before `runApp`
- `apps/pubspec.yaml` — asset declarations simplified to one `.tar.bz2` per bundled model
- `apps/assets/voice-models/` — new directory holding bundled model archives

## Why

The app currently bundles ASR and TTS models as Flutter assets, which limits language support to what the developer pre-packages (currently English only). Users cannot choose models for their language, and the ~350 MB of bundled models inflates the app download size. Moving to runtime model download lets users pick models for their languages, keeps the initial app small, and stores models in a permanent location safe from cache cleanup.

## What Changes

- **New model download manager**: Download, extract, and manage sherpa-onnx model archives from GitHub releases to permanent app storage (not cache)
- **Curated model catalog**: Built-in catalog of recommended ASR and TTS models organized by language, with metadata (name, languages, download size, architecture, streaming support for ASR)
- **ASR: Omnilingual CTC streaming support**: Switch from transducer-only to also supporting CTC model architecture via `OnlineRecognizer`, enabling the omnilingual model (~279 MB int8) that covers 1600+ languages including English, German, Norwegian, Swedish, French, and Russian
- **TTS: Per-language Piper voice selection**: Users choose and download Piper VITS voices for their language (~20 MB int8 each), with shared espeak-ng-data downloaded once
- **Model selection UI**: Settings page gains model management section where users browse available models by language, download them, and select active ASR/TTS models
- **Asset models as optional fallback**: Bundled asset models continue to work when present, enabling fast development setup and pre-configured deployments. The app works without them — voice features simply require downloading models first.
- **Graceful degradation without models**: Voice features are disabled until models are available (either bundled or downloaded); app remains functional for text chat

## Capabilities

### New Capabilities
- `model-download`: Downloading, extracting, and storing model archives from remote sources to permanent device storage. Includes progress tracking, integrity verification, and cleanup of partial downloads.
- `model-catalog`: Curated registry of available ASR and TTS models with metadata (languages, size, architecture, download URL, and whether ASR models support streaming/live recognition). Provides language-based filtering and recommendations.

### Modified Capabilities
- `model-loading`: Model loader must support loading from permanent storage in addition to assets/cache. Must handle missing models gracefully when none are bundled or downloaded yet. Asset-based loading remains as optional fallback.
- `speech-recognition`: ASR initialization must support CTC model architecture (not just transducer) to enable the omnilingual streaming model. Model selection becomes dynamic based on what the user has downloaded or what is bundled.
- `user-settings`: Settings page adds model management section for browsing, downloading, and selecting ASR/TTS models. Voice settings conditional on models being available.

## Impact

- **Code**: `speech_recognition/`, `tts/`, `voice/`, `providers/`, `config/`, `pages/settings_page.dart`, `models/settings.dart`
- **Dependencies**: May need `archive` or `tar` package for extracting `.tar.bz2` downloads; `http` package already available for downloads
- **Storage**: Downloaded models stored in `path_provider` application support directory (permanent, survives cache cleanup and app updates)
- **App size**: Can be built without bundled models for a much smaller initial download; bundled models remain optional for development convenience
- **First run**: Without bundled assets, users must download at least one ASR and one TTS model before voice features work
- **Platforms**: Android, iOS, Linux (web already has no voice support)

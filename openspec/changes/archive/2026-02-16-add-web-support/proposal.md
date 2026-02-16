## Why

The app currently only runs on native platforms (Android, iOS, Linux). Adding web support makes it accessible from any browser without installation. Several dependencies (sherpa_onnx, record, audio_session) have no web support, and their types leak across the codebase. Beyond just enabling web, the current tight coupling to specific native libraries needs to be replaced with proper abstractions — making it easier to swap implementations per platform or replace them entirely in the future.

## What Changes

- Introduce a **voice integration abstraction layer** with platform-independent interfaces for speech recognition (ASR), text-to-speech (TTS), audio recording, and audio session management
- Replace all leaked dependency types (e.g., `RecordState` from the `record` package) with **local equivalents** defined within the app
- Introduce a **model loading abstraction** that decouples model access from the current asset-bundling strategy, preparing for future runtime download and management
- Use **conditional imports** to provide native implementations (current code) on mobile/desktop and no-op/unavailable stubs on web
- Add **UI guards** (`kIsWeb` or capability queries) to hide voice-related controls when running on platforms without voice support
- **BREAKING**: Provider and widget code that directly references `record`, `sherpa_onnx`, or `audio_session` types will be refactored to use the new abstractions

## Capabilities

### New Capabilities
- `voice-integration-abstraction`: Platform-independent interfaces for ASR, TTS, audio recording, and audio session coordination. Defines local state types (replacing `RecordState` etc.), capability queries ("is voice available?"), and the contract that platform-specific implementations fulfill.
- `model-loading`: Abstraction for loading AI models (ASR, TTS). Current asset-bundling becomes one strategy behind the interface. Prepares for future runtime download and model management.
- `web-platform`: Web-specific configuration, conditional imports, stub implementations for unavailable features, and UI guards for graceful degradation on browsers.

### Modified Capabilities
- `speech-recognition`: Requirements change from "uses sherpa_onnx directly" to "uses voice integration abstraction; sherpa_onnx becomes a platform-specific implementation detail"
- `user-settings`: Voice-related settings (background listening duration, voice mode) should be hidden or disabled on platforms without voice support

## Impact

**Code (significant refactoring):**
- `lib/speech_recognition/` — services.dart and sherpa_streaming_asr.dart move behind abstraction interfaces
- `lib/tts/` — sherpa_tts.dart and tts_isolate_worker.dart move behind abstraction interfaces
- `lib/providers/recording_provider.dart` — replace `RecordState` with local enum, depend on abstract recording interface
- `lib/providers/audio_coordinator_provider.dart` — abstract audio session management
- `lib/providers/background_service_provider.dart` — abstract or stub platform channel calls
- `lib/speech_recognition/widgets.dart` — replace `RecordState` references with local types
- `lib/utils/files.dart` — guard `dart:io` usage, provide web-compatible alternative
- `lib/pages/chat_page.dart`, `lib/pages/settings_page.dart` — UI guards for voice features
- `lib/config/app_config.dart` — model path config moves behind model loading abstraction

**Dependencies:**
- `sherpa_onnx`, `record`, `audio_session` — remain in pubspec but only imported via conditional imports (never on web)
- `just_audio_media_kit`, `media_kit_libs_linux` — already platform-scoped, no change needed

**Assets:**
- Large model bundles (sherpa-onnx ASR, Kokoro TTS) excluded from web builds via asset configuration or build-time guards

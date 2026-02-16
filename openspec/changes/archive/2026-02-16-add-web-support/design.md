## Context

The app is tightly coupled to native libraries (`sherpa_onnx`, `record`, `audio_session`) with their types leaking into providers, widgets, and state classes. For example, `RecordState` from the `record` package appears in `RecordingState`, `RecordingStateIndicator`, `RecorderButton`, and health monitoring logic. The `audio_session` package is used directly in both `AudioCoordinator` and `BackgroundServiceNotifier`. TTS generation runs in a background `Isolate` with direct `sherpa_onnx` FFI calls. Model files are loaded by copying Flutter assets to the file system via `dart:io`.

None of these work on web. The app currently has zero platform conditionals (`kIsWeb`, conditional imports, etc.).

## Goals / Non-Goals

**Goals:**
- App compiles and runs on web with full chat functionality (text input, API communication, message display, settings)
- Voice features (ASR, TTS, audio recording, background service, audio session management) are cleanly abstracted behind interfaces
- No native dependency types leak beyond the implementation layer — all providers, widgets, and state classes use app-defined types
- Model loading is abstracted so the current asset-bundling strategy is just one implementation
- Future platform-specific voice implementations (e.g., Web Speech API, cloud TTS) can be added by implementing the interfaces
- Web UI gracefully indicates voice features are unavailable rather than showing broken controls

**Non-Goals:**
- Implementing web-based ASR or TTS (only stubs for now)
- Changing the native platform behavior — existing Android/iOS/Linux functionality must remain identical
- Supporting PWA features (service workers, offline mode, push notifications)
- Optimizing web bundle size (model assets are excluded, but no tree-shaking optimization beyond that)

## Decisions

### 1. Abstraction layer location: `lib/voice/`

Create a new `lib/voice/` directory as the single boundary between platform-specific voice code and the rest of the app.

**Structure:**
```
lib/voice/
  voice_service.dart          # Abstract interfaces + local types (always imported)
  voice_service_native.dart   # Native implementation (imports sherpa_onnx, record, audio_session)
  voice_service_stub.dart     # Web stub (no native imports)
```

**Why a new directory instead of refactoring in place:** The existing `lib/speech_recognition/` and `lib/tts/` directories contain implementation details (sherpa model config, isolate workers, audio stream processing). These become the "native backend" behind the abstraction. A new directory makes the boundary explicit.

**Alternative considered:** Refactoring `lib/speech_recognition/services.dart` in place with conditional imports. Rejected because it mixes abstraction definition with implementation and doesn't cleanly separate the model loading concern.

### 2. Local types replace all leaked dependency types

Define app-owned equivalents in `voice_service.dart`:

```dart
/// Replaces RecordState from package:record
enum AudioRecordingStatus { stopped, recording, paused }

/// Capability query — replaces runtime checks
abstract class VoiceCapabilities {
  bool get isAsrAvailable;
  bool get isTtsAvailable;
  bool get isBackgroundListeningAvailable;
}
```

`RecordingState` in `recording_provider.dart` changes from `RecordState recordState` to `AudioRecordingStatus recordingStatus`. All widget references update accordingly.

**Why not just wrap `RecordState`:** The whole point is that no code outside `lib/voice/voice_service_native.dart` should import or know about the `record` package. A wrapper still creates a transitive dependency on the type.

### 3. Conditional imports at the service boundary

Use Dart's conditional import mechanism at exactly one point — the factory/entrypoint that creates the voice service:

```dart
// lib/voice/voice_service.dart
import 'voice_service_stub.dart'
    if (dart.library.io) 'voice_service_native.dart'
    as platform;

VoiceService createVoiceService() => platform.createVoiceService();
```

This is the standard Flutter pattern. The `voice_service_stub.dart` returns a `NoOpVoiceService` that reports all capabilities as unavailable. The `voice_service_native.dart` returns the real implementation wrapping the existing code.

**Why `dart.library.io` not `dart.library.html`:** Convention — `dart:io` is available on native, not on web. This is the more common conditional check in the Flutter ecosystem and correctly distinguishes native vs web.

### 4. Abstract voice service interface

```dart
abstract class VoiceService implements VoiceCapabilities {
  // ASR
  Future<void> initializeAsr();
  Future<void> startRecording({
    required ValueChanged<String> onTextRecognized,
    required VoidCallback onTextFinished,
    ValueChanged<AudioRecordingStatus>? onStatusChanged,
    VoidCallback? onAudioDataReceived,
    ValueChanged<double>? onAmplitudeChanged,
    ValueChanged<Object>? onStreamError,
    VoidCallback? onStreamDone,
  });
  Future<void> stopRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();

  // TTS
  Future<void> initializeTts();
  Future<Uint8List?> generateSpeech(String text, String id);

  // Audio session
  Future<void> configureAudioSession();
  Future<void> activateAudioSession();
  Future<void> deactivateAudioSession();
  Stream<AudioInterruptionEvent> get interruptionEvents;

  // Background service
  Future<void> startBackgroundService(String mode, {int durationMinutes});
  Future<void> stopBackgroundService();
  Future<void> updateNotification(String message);
  Future<void> showErrorNotification(String title, String message);

  void dispose();
}
```

The native implementation wraps the existing `ASR` class, `TtsIsolateWorker`, `AudioSession`, and `MethodChannel` calls. The web stub returns immediately or throws `UnsupportedError` for operations that can't be no-ops.

**Why one interface not many:** The current code has deep coupling between these concerns (e.g., `AudioCoordinator` manages both `AudioSession` and recording/playback transitions). A single interface keeps the boundary simple. If the interface grows too large later, it can be split — but premature splitting would complicate the refactoring.

### 5. Model loading abstraction

```dart
abstract class ModelLoader {
  /// Returns the file system path to the model directory (native)
  /// or throws UnsupportedError (web)
  Future<String> loadModel(String modelName);
  Future<String> loadModelFile(String modelName, String fileName);
}
```

The current asset-to-cache copying logic in `lib/utils/files.dart` becomes `AssetModelLoader implements ModelLoader`. This is injected into the native `VoiceService` implementation.

`AppConfig` remains but becomes optional — on web, model config fields are unused and don't need to resolve to real files.

**Why abstract now:** The user explicitly stated that runtime model downloading is a future direction. Having the interface now means that work is additive, not a refactor.

### 6. Provider refactoring strategy

Providers change what they depend on but not their public API to widgets:

- **`RecordingProvider`**: Replace `ASR` dependency with `VoiceService`. Replace `RecordState` with `AudioRecordingStatus`. Remove `MethodChannel` call for error notification — route through `VoiceService.showErrorNotification()`.
- **`AudioCoordinator`**: Replace direct `AudioSession.instance` calls with `VoiceService.configureAudioSession()` / `deactivateAudioSession()`. On web, these are no-ops.
- **`BackgroundServiceNotifier`**: Replace `MethodChannel` and `AudioSession` usage with `VoiceService` methods. On web, the entire provider becomes effectively inert.
- **`TtsNotifier`**: Replace `TtsService` (which uses `TtsIsolateWorker`) with `VoiceService.generateSpeech()`. No change to the `PlaybackProvider` — `just_audio` supports web.

### 7. UI guards for voice features

Use `VoiceCapabilities` from the `VoiceService` (exposed via a Riverpod provider) rather than `kIsWeb`:

```dart
final isVoiceAvailable = ref.watch(voiceCapabilitiesProvider).isAsrAvailable;
```

**Why not `kIsWeb` directly:** Capability-based checks are more composable. If a native platform later lacks a microphone, the same guard works. It also makes testing easier — mock the capability, not the platform.

**UI changes:**
- `RecorderButton`: Hidden when ASR unavailable
- `VolumeBarVisualizer`: Hidden when ASR unavailable
- Settings page: Voice mode selector and background listening duration hidden when voice unavailable
- TTS play buttons on messages: Hidden when TTS unavailable
- Chat input area: Text-only layout when voice unavailable (no mic button)

### 8. `dart:io` isolation

The only `dart:io` usage is in `lib/utils/files.dart` for model file copying. This moves entirely into the native `ModelLoader` implementation. No other code needs `dart:io`.

### 9. Web asset exclusion

Large model assets (ASR ~50MB, TTS ~300MB) must not be bundled in web builds. Use separate `pubspec.yaml` asset declarations or a build-time approach:

- Define a `web_assets.yaml` or use `--dart-define=PLATFORM=web` to conditionally skip model asset registration
- Simplest approach: keep model assets in pubspec but accept they won't be loaded on web (the stub `ModelLoader` never requests them). Flutter's web build may include them in the asset bundle — if this is a problem, use `flutter build web --dart-define` with a custom asset list.

This is a pragmatic trade-off. If web bundle size becomes a concern, it can be addressed separately.

## Risks / Trade-offs

**Large refactoring surface** — 15+ files change, touching core providers and UI. Risk of regressions on native platforms.
→ Mitigation: Refactor incrementally. Start with type replacements (RecordState → AudioRecordingStatus), then wrap existing code behind interfaces, then add web stubs. Run existing tests after each step.

**Single VoiceService interface may grow too large** — It combines ASR, TTS, audio session, and background service concerns.
→ Mitigation: Accept this for now. The interface is a facade — internally, the native implementation delegates to the existing specialized classes. If it becomes unwieldy, split into `AsrService`, `TtsService`, `AudioSessionService` as a follow-up.

**Web bundle still includes model asset references** — Flutter may bundle asset files even when they're never loaded on web.
→ Mitigation: Verify web build size. If problematic, split assets into a separate package or use `--dart-define` to exclude them.

**Isolate-based TTS not available on web** — Web uses web workers, not `Isolate.spawn`.
→ Mitigation: The web stub doesn't use isolates at all — TTS is simply unavailable. If web TTS is added later, it can use a web worker or run synchronously (cloud API).

**`audio_session` interruption handling is deeply integrated** — The coordinator and background service both listen to session events for phone call handling, Bluetooth routing, etc.
→ Mitigation: On web, `interruptionEvents` returns an empty stream. The coordinator and background service still function but never receive interruption events — which is correct because browsers don't have this concept.

# Project Overview

Relagent frontend — multi-platform Flutter app (Android/iOS/Linux/Web) with on-device speech recognition. Connects to the Relagent Engine or any OpenAI-compatible chat API.

## Technology Stack

- **Flutter** — Multi-platform framework (Android, iOS, Linux)
- **Riverpod** — State management
- **Sherpa-ONNX** — On-device streaming speech recognition

## Flutter MCP Tools

**ALWAYS use MCP tools over shell commands.** Configure the project root first:

```shell
dart-flutter_add_roots --roots '[{"uri": "file:///absolute/path/to/project/apps"}]'
```

Always run `dart-flutter_analyze_files` and fix all issues before completing changes.

Key tools: `dart-flutter_launch_app`, `dart-flutter_list_devices`, `dart-flutter_stop_app`, `dart-flutter_hot_reload`, `dart-flutter_run_tests`, `dart-flutter_analyze_files`, `dart-flutter_resolve_workspace_symbol`, `dart-flutter_dart_format`, `dart-flutter_dart_fix`, `dart-flutter_pub`.

## Engine API Integration

Generate schema: `bin/generate_schema.py` or `curl http://localhost:8000/openapi.json`

When modifying `lib/agentic/services.dart`, verify against the OpenAPI schema. Key schemas: `ChatRequest`, `ChatResponse`, `MessagesResponse`.

## Architecture

### Core Structure

- `lib/main.dart` — Entry point (SharedPreferences + ProviderScope)
- `lib/router/app_router.dart` — go_router (`/` = chat, `/settings` = settings)
- `lib/pages/` — `chat_page.dart`, `settings_page.dart`
- `lib/providers/` — Riverpod state: chat, settings, recording, background service, audio coordinator, playback, TTS
- `lib/chat/` — Chat models, widgets, OpenAI-compatible API services
- `lib/speech_recognition/` — Sherpa-ONNX streaming ASR integration
- `lib/tts/` — Text-to-speech with isolate-based processing
- `lib/config/app_config.dart` — Static config from `assets/config.json`

### Navigation

- **/** (root): Chat page (default)
- **/settings**: Settings page (accessed via menu icon in chat)

## Configuration

### Static Config (Assets)

Located in `apps/assets/config.json` — loaded at app startup:

- **speech_recognition.streaming_asr_model**: Name of Sherpa-ONNX ASR model in `assets/`
- **tts.model**: Name of TTS model in `assets/`

### User Settings

Managed via settings page, persisted to SharedPreferences:

- **Chat Base URL**: OpenAI-compatible API endpoint
- **Chat Model**: Model name
- **Background Listening Duration**: Maximum time for background recording (5min to Unlimited)

## Code Style

- 2-space indentation, LF line endings, UTF-8 encoding
- Use `flutter_lints` with strict-raw-types and strict-inference enabled
- Relative imports with `/` prefix (e.g., `import '/providers/chat_provider.dart'`)
- Use `const` constructors and `copyWith()` pattern for immutable state
- Riverpod 3.x NotifierProvider pattern for state management

## Important Patterns

### State Management

```dart
class MyWidget extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    return ...
  }
}
```

### Adding New Features

1. Create a model in `lib/models/` if needed
2. Create a provider in `lib/providers/` using NotifierProvider (Riverpod 3.x)
3. Access state in widgets using `ref.watch()` or `ref.read()`
4. Trigger actions using `ref.read(provider.notifier).method()`

## Debugging

Use `dart-flutter_get_runtime_errors` or `adb logcat` for system logs.

### Web app

Reproduce web bugs with `dart-flutter_launch_app` on the `chrome` device
first. The `dart-flutter_*` tools only attach to apps they launched, so they
cannot inspect a pre-built bundle served by the engine at `/app/` — for that
the app must be running in dev mode.

- **Dart-level bug** (exception, wrong behaviour): dev mode reproduces it in
  seconds and hot-restarts. `getApplicationSupportDirectory` and other
  `path_provider` / `dart:io` calls throw `MissingPluginException` on web —
  guard startup code with `kIsWeb` *and* a fail-safe (see the platform guards
  in `lib/voice/`). Confirm the fix in a `--wasm` build before closing.
- **Suspected build or serving problem** (blank page, 404, wrong MIME type):
  inspect the served artifact directly. `chromium --dump-dom` and
  `--virtual-time-budget` are unreliable for wasm — virtual time stalls on the
  wasm fetch and returns identical output whether the app works or crashes.
  Drive Chrome DevTools Protocol with real wall-clock waits and trust the
  screenshot, not the DOM (skwasm renders into a shadow-DOM canvas, so
  `querySelectorAll('canvas')` finds nothing in a healthy app).
- `flutter run -d chrome` compiles **dart2js**. Use `--wasm` to reproduce
  renderer (skwasm) or JS-interop issues, since the release build is wasm.

CI runs `flutter test` only (VM platform, `kIsWeb == false`), so web-only
startup crashes are not caught before release — verify web changes manually.
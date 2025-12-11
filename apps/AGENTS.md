# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Flutter app code.

## Project Overview

This is the Relagent ("Relatable Agentic Minion") frontend. A multi-platform Flutter app (Android/iOS/Linux) with speech recognition capabilities that connects to any OpenAI-compatible chat API server.

## Technology Stack

- **Flutter** - Multi-platform framework (Android, iOS, Linux)
- **Riverpod** - State management
- **go_router** - Navigation
- **Sherpa-ONNX** - On-device streaming speech recognition
- **SharedPreferences** - Settings persistence

## Development Commands

```bash
# Setup - create config from template
cp assets/config.template.json assets/config.json
# Edit config.json to configure chat API endpoint and ASR model

# Standard Flutter commands: flutter pub get, flutter run, flutter build, flutter test, flutter analyze
```

### Flutter MCP Tools (Preferred)

When available, use Flutter MCP (Model Context Protocol) tools for app management:

**IMPORTANT: MCP Configuration Required**
Before using Flutter MCP tools, you must configure the project root. The Flutter app is located in the `apps/` directory, not the repository root, so MCP needs to know where to find the Flutter project:

```bash
# Configure MCP to use apps/ directory as Flutter project root
dart-flutter_add_roots --roots '[{"uri": "file://$(pwd)/apps"}]'
```

Or using the MCP tool directly:
```bash
dart-flutter_add_roots --roots '[{"uri": "file:///absolute/path/to/project/apps"}]'
```

**Why this is needed**: MCP tools look for `pubspec.yaml` to identify Flutter projects. Since our Flutter project is in `apps/`, MCP must be pointed to the correct directory.

- **Launch App**: Use `dart-flutter_launch_app` with appropriate device
- **List Devices**: Use `dart-flutter_list_devices` to see available targets
- **Stop App**: Use `dart-flutter_stop_app` with process ID from launch
- **Hot Reload**: Use `dart-flutter_hot_reload` for code changes
- **Run Tests**: Use `dart-flutter_run_tests` for comprehensive testing
- **Code Analysis**: Use `dart-flutter_analyze_files` to check for issues
- **Symbol Resolution**: Use `dart-flutter_resolve_workspace_symbol` to find code locations

**Verification**: Test the configuration by resolving a symbol:
```bash
dart-flutter_resolve_workspace_symbol --query "main"
# Should return main() function from apps/lib/main.dart
```

These tools provide programmatic control and are preferred over bash commands when available.

Logs after manual testing are found in flutter*logs*\*.txt

## Architecture

The Flutter app is located in the `apps/` directory of the repository and uses **Riverpod** for state management:

### Core Structure

- **lib/main.dart**: App entry point, initializes SharedPreferences and ProviderScope
- **lib/router/app_router.dart**: go_router navigation configuration
- **lib/pages/chat_page.dart**: Main chat interface (default page)
- **lib/pages/settings_page.dart**: Settings page for API configuration
- **lib/providers/**: Riverpod state providers
  - **chat_provider.dart**: Chat state (messages, loading, errors)
  - **settings_provider.dart**: User settings (API endpoint, model)
- **lib/models/settings.dart**: Settings data class
- **lib/chat/**: Chat models, widgets, and services for OpenAI-compatible API communication
- **lib/speech_recognition/**: Sherpa-ONNX integration for on-device streaming ASR
- **lib/config/app_config.dart**: Static configuration (ASR model only)

### State Management

The app uses **Riverpod** for state management, providing:

- Compile-time safe state access
- Programmatic action triggering without BuildContext
- Separation of business logic from UI
- Easy testing and maintainability

### Navigation

- **/** (root): Chat page (default)
- **/settings**: Settings page (accessed via menu icon in chat)

## Configuration

### Static Configuration (ASR Model)

Located in `apps/assets/config.json` - loaded at app startup:

- **speech_recognition.streaming_asr_model**: Name of bundled Sherpa-ONNX ASR model directory (not user-editable)

### User Settings (API Configuration)

Managed via settings page, persisted to SharedPreferences:

- **Chat Base URL**: OpenAI-compatible API endpoint (e.g., http://localhost:1234/v1)
- **Chat Model**: Model name to use with that endpoint (e.g., qwen2.5-coder:7b)

Default settings are used on first launch and can be reset via the settings page.

## Development Commands

```bash
# Setup - create config from template
cp assets/config.template.json assets/config.json
# Edit config.json to configure chat API endpoint and ASR model

# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Build for specific platform
flutter build apk        # Android
flutter build ios        # iOS
flutter build linux      # Linux desktop

# Run tests
flutter test

# Lint code
flutter analyze
```

Logs after manual testing are found in flutter*logs*\*.txt

## Repository Structure (Flutter App)

```
apps/
├── lib/                    # Dart source code
│   ├── main.dart          # App entry point
│   ├── providers/         # Riverpod state management
│   ├── pages/             # UI screens
│   ├── chat/              # Chat functionality
│   ├── speech_recognition/ # Sherpa-ONNX ASR integration
│   ├── tts/               # Text-to-speech functionality
│   ├── models/            # Data models
│   ├── widgets/           # Reusable UI components
│   ├── config/            # App configuration
│   ├── router/            # Navigation configuration
│   └── utils/             # Utility functions
├── assets/                # App assets (config, ASR models, icons)
├── android/               # Android-specific configuration
├── ios/                   # iOS-specific configuration
├── linux/                 # Linux desktop configuration
└── web/                   # Web configuration
```

## Code Style Guidelines (Flutter/Dart)

**Formatting:**
- 2-space indentation, LF line endings, UTF-8 encoding
- Trim trailing whitespace, insert final newline
- Use `flutter_lints` with strict-raw-types and strict-inference enabled

**Dart Conventions:**
- Relative imports with `/` prefix (e.g., `import '/providers/chat_provider.dart'`)
- PascalCase for classes, camelCase for variables/methods
- Use `const` constructors and `copyWith()` pattern for immutable state
- Riverpod StateNotifierProvider pattern for state management
- Try-catch blocks for error handling with specific error messages

**Riverpod Patterns:**
- Use `StateNotifierProvider<Notifier, State>` for state management
- Use `Provider<T>` for dependency injection (e.g., SharedPreferences)
- Override providers in `ProviderScope` in main.dart for testing/initialization
- Use `ref.read()` for one-time reads, `ref.watch()` for reactive reads
- Create immutable state classes with `copyWith()` method
- Handle async operations in StateNotifier methods with proper error states
- Use `unawaited()` for fire-and-forget async operations (like TTS pre-caching)

## Important Patterns

### State Management with Riverpod

The app uses Riverpod StateNotifierProvider pattern:

**Accessing State in Widgets:**

```dart
class MyWidget extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for state changes (rebuilds on change)
    final chatState = ref.watch(chatProvider);

    // Read once without watching (for actions)
    final settings = ref.read(settingsProvider);

    return ...
  }
}
```

**Triggering Actions:**

```dart
// From anywhere with WidgetRef:
ref.read(chatProvider.notifier).sendMessage("Hello");
ref.read(settingsProvider.notifier).updateChatBaseUrl("http://...");

// From outside widget tree (using ProviderContainer):
container.read(chatProvider.notifier).clearChat();
```

### Speech Recognition

The app uses Sherpa-ONNX for on-device streaming ASR. Models are downloaded from [k2-fsa/sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models) and bundled in `apps/assets/`. The model directory name must match the static config in `assets/config.json`.

### Configuration Management

Two types of configuration:

1. **Static Config** (`AppConfig`): Loaded from `assets/config.json` at startup, contains ASR model path (not user-editable)
2. **User Settings** (`SettingsProvider`): Managed via Riverpod, persisted to SharedPreferences, editable in settings page

### Adding New Features

When adding features that need state management:

1. Create a model in `lib/models/` if needed
2. Create a provider in `lib/providers/` using StateNotifierProvider
3. Access state in widgets using `ref.watch()` (for reactive updates) or `ref.read()` (for one-time reads)
4. Trigger actions using `ref.read(provider.notifier).method()`

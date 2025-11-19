# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Relagent is a "Relatable Agentic Minion" - a multi-platform Flutter app (Android/iOS/Linux) with speech recognition capabilities that connects to any OpenAI-compatible chat API server.

**Note**: The `experiments/`, `bin/`, and `run/` directories contain experimental/legacy backend code and can be ignored.

## Architecture

The Flutter app is located in the `apps/` directory and uses **Riverpod** for state management:

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

All Flutter development happens in the `apps/` directory:

```bash
cd apps

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
```

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

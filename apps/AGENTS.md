## Project Overview

This is the Relagent ("Relatable Agentic Minion") frontend. A multi-platform Flutter app (Android/iOS/Linux) with speech recognition capabilities that connects to any OpenAI-compatible chat API server.

## Technology Stack

- **Flutter** - Multi-platform framework (Android, iOS, Linux)
- **Riverpod** - State management
- **go_router** - Navigation
- **Sherpa-ONNX** - On-device streaming speech recognition
- **SharedPreferences** - Settings persistence

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

**IMPORTANT**: Always address warnings, deprecations, and analysis issues as part of any iteration. Run `dart-flutter_analyze_files` and fix all issues before completing changes.

- **Launch App**: Use `dart-flutter_launch_app` with appropriate device
- **List Devices**: Use `dart-flutter_list_devices` to see available targets
- **Stop App**: Use `dart-flutter_stop_app` with process ID from launch
- **Hot Reload**: Use `dart-flutter_hot_reload` for code changes
- **Run Tests**: Use `dart-flutter_run_tests` for comprehensive testing (instead of `fvm flutter test`)
- **Code Analysis**: Use `dart-flutter_analyze_files` to check for issues (instead of `fvm flutter analyze`)
- **Symbol Resolution**: Use `dart-flutter_resolve_workspace_symbol` to find code locations
- **Code Formatting**: Use `dart-flutter_dart_format` for code formatting (instead of `fvm flutter format .`)
- **Apply Fixes**: Use `dart-flutter_dart_fix` to apply automated fixes (instead of `fvm dart fix --apply`)
- **Dependency Management**: Use `dart-flutter_pub` for package operations (instead of `fvm flutter pub get/add/remove`)

**Verification**: Test the configuration by resolving a symbol:

```bash
dart-flutter_resolve_workspace_symbol --query "main"
# Should return main() function from apps/lib/main.dart
```

These tools provide programmatic control and are **ALWAYS preferred** over bash commands when available:

- ✅ **USE MCP**: `dart-flutter_run_tests` - Provides structured test output and better error handling
- ❌ **AVOID**: `fvm flutter test` - Shell command with less integration
- ✅ **USE MCP**: `dart-flutter_analyze_files` - Direct integration with codebase analysis
- ❌ **AVOID**: `fvm flutter analyze` - Shell command requiring manual path handling
- ✅ **USE MCP**: `dart-flutter_hot_reload` - Works with connected app instances
- ❌ **AVOID**: Manual hot reload via shell - Less reliable

## Log Files from Manual Testing

**Location**: Log files are created in the Flutter app directory with platform-specific names:

- **Android**: `flutter_android.log` (in `apps/` directory)
- **iOS**: `flutter_ios.log`
- **Linux**: `flutter_linux.log`
- **Web**: `flutter_web.log`

**How to Capture Logs**:

```bash
cd apps
flutter run 2>&1 | tee flutter.log          # Captures both stdout and stderr
# OR for specific platform:
flutter run 2>&1 | tee flutter_android.log  # Android debugging
```

**Log Analysis Tools**:

- Use `grep` to filter specific issues: `grep -E "(ERROR|FATAL|Exception)" flutter.log`
- Use `tail -f` for real-time monitoring: `tail -f flutter.log`
- Use `adb logcat` for Android system logs alongside Flutter logs

**Important**: Always capture logs when testing new features, audio issues, or authentication problems.

**Common Debugging Issues**:

- **Notification not dismissed when switching off continuous listening**: Fixed by calling `stopForeground(STOP_FOREGROUND_REMOVE)` when switching to IDLE mode in AudioBackgroundService

## Engine API Integration

The app connects to the Relagent engine via REST API. The engine exposes an OpenAPI schema that defines the API contract.

### OpenAPI Schema Reference

**Generate/fetch the schema:**

```bash
# From running engine
curl http://localhost:8000/openapi.json > apps/openapi-schema.json

# Or generate from engine source
cd engine && ./bin/generate_schema.py
```

**Verify implementation matches schema:**
When modifying `lib/agentic/services.dart`, always verify against the OpenAPI schema:

1. Fetch current schema: `curl http://localhost:8000/openapi.json | python3 -m json.tool`
2. Check request/response formats match the schema definitions
3. Key schemas: `ChatRequest`, `ChatResponse`, `MessagesResponse`, `UserMessage`, `AssistantMessage`

**Current API endpoints:**

- `GET /health` - Health check, returns `{name, version, status}`
- `GET /api/v1/messages/{session_id}` - Returns `MessagesResponse`
- `POST /api/v1/messages` - Accepts `ChatRequest`, returns `ChatResponse`

**Schema locations:**

- Live: `http://localhost:8000/openapi.json`
- Generated: `engine/openapi-schema.json` (run `engine/bin/generate_schema.py`)

See `lib/agentic/services.dart` for documented request/response formats.

## Architecture

The Flutter app is located in the `apps/` directory of the repository and uses **Riverpod** for state management:

### Core Structure

- **lib/main.dart**: App entry point, initializes SharedPreferences and ProviderScope
- **lib/router/app_router.dart**: go_router navigation configuration
- **lib/pages/chat_page.dart**: Main chat interface (default page)
- **lib/pages/settings_page.dart**: Settings page for API configuration
- **lib/providers/**: Riverpod state providers
  - **chat_provider.dart**: Chat state (messages, loading, errors)
  - **settings_provider.dart**: User settings (API endpoint, model, voice mode, background duration)
  - **recording_provider.dart**: Audio recording state with health monitoring and auto-recovery
  - **background_service_provider.dart**: Native foreground service coordination
  - **audio_coordinator_provider.dart**: Audio session management and focus handling
  - **playback_provider.dart**: TTS audio playback coordination
  - **tts_provider.dart**: Text-to-speech state management
- **lib/models/settings.dart**: Settings data class with background listening duration options
- **lib/chat/**: Chat models, widgets, and services for OpenAI-compatible API communication
- **lib/speech_recognition/**: Sherpa-ONNX integration for on-device streaming ASR with error handling
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

### Static Configuration (Optional Bundled Models)

Located in `apps/assets/config.json` — loaded at app startup:

- **speech_recognition.streaming_asr_model**: *(optional)* Name of a Sherpa-ONNX ASR model directory bundled under `assets/`. Bundling ships the model pre-installed so the user skips the first-run download. Set to `null` or omit to require the user to download an ASR model via the in-app model manager.
- **tts.model**: *(optional)* Name of a TTS model directory bundled under `assets/`. Same trade-off — bundling is a convenience shortcut that increases app size but eliminates the download step. Omit for distribution builds where users should choose their own model.

### User Settings (API Configuration & Voice Settings)

Managed via settings page, persisted to SharedPreferences:

**API Configuration:**

- **Chat Base URL**: OpenAI-compatible API endpoint (e.g., <http://localhost:1234/v1>)
- **Chat Model**: Model name to use with that endpoint (e.g., qwen2.5-coder:7b)

**Voice Settings:**

- **Background Listening Duration**: Maximum time for background recording sessions
  - Options: 5min, 15min, 30min, 1hr (default), 2hr, 3hr, 6hr, 12hr, 24hr, Unlimited
  - Automatically transitions to Silent mode when duration expires
  - Notification shows end time for limited durations
  - Unlimited setting uses 24-hour wake lock with renewal

Default settings are used on first launch and can be reset via the settings page.

## Repository Structure (Flutter App)

```
apps/
├── lib/                    # Dart source code
│   ├── main.dart          # App entry point
│   ├── providers/         # Riverpod state management
│   ├── pages/             # UI screens
│   ├── chat/              # Chat functionality
│   ├── speech_recognition/ # Sherpa-ONNX ASR integration
│   ├── tts/               # Text-to-speech functionality with isolate-based processing
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
- Riverpod 3.x NotifierProvider pattern for state management
- Try-catch blocks for error handling with specific error messages

**Riverpod Patterns:**

- Use `NotifierProvider<Notifier, State>` for state management (Riverpod 3.x)
- Use `Provider<T>` for dependency injection (e.g., SharedPreferences)
- Override providers in `ProviderScope` in main.dart for testing/initialization
- Use `ref.read()` for one-time reads, `ref.watch()` for reactive reads
- Create immutable state classes with `copyWith()` method
- Handle async operations in Notifier methods with proper error states
- Use `unawaited()` for fire-and-forget async operations (like TTS pre-caching)

## Important Patterns

### State Management with Riverpod

The app uses Riverpod 3.x NotifierProvider pattern:

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
2. Create a provider in `lib/providers/` using NotifierProvider (Riverpod 3.x)
3. Access state in widgets using `ref.watch()` (for reactive updates) or `ref.read()` (for one-time reads)
4. Trigger actions using `ref.read(provider.notifier).method()`

## Health Monitoring Architecture

The app includes a robust health monitoring system for background audio recording to ensure reliability and user trust:

### Components

**RecordingHealthMonitor** (`lib/providers/recording_provider.dart`):

- Periodic health checks every 30 seconds when recording is active
- Tracks `lastAudioDataTime` to detect silent stream failures
- Implements exponential backoff recovery strategy (0s, 2s, 5s delays)
- Graceful degradation to Silent mode after 3 failed recovery attempts

**Audio Stream Error Handling** (`lib/speech_recognition/services.dart`):

- `onError` and `onDone` handlers on audio stream listeners
- Immediate detection of stream failures
- Callback mechanism for audio data flow tracking

**Background Service Integration** (`lib/providers/background_service_provider.dart`):

- Dynamic wake lock timeout based on user's background listening duration setting
- Wake lock timeout = user setting + 5 minute buffer
- 24-hour timeout for unlimited setting with renewal mechanism

### User Settings

**BackgroundListeningDuration** enum in `lib/models/settings.dart`:

- Options: 5min, 15min, 30min, 1hr (default), 2hr, 3hr, 6hr, 12hr, 24hr, unlimited
- Automatic transition to Silent mode when duration expires
- Notification shows end time for limited durations

### Recovery Flow

1. **Health Check** (every 30s): Verifies `RecordState.record` and recent audio data
2. **Failure Detection**: Triggers when no audio data for 2+ minutes or stream error
3. **Recovery Attempts**: Up to 3 tries with exponential backoff delays
4. **Graceful Degradation**: Switches to Silent mode and shows user notification
5. **User Notification**: "Listening stopped - could not recover audio recording" with "Open Settings" action

### Battery Optimization

- Health monitoring timer runs infrequently (30s intervals) for minimal battery impact
- Wake lock timeouts align with user preferences to avoid unnecessary battery drain
- Automatic shutoff prevents indefinite background recording

### Debugging

Health monitoring logs recovery attempts and failures for troubleshooting:

**Recovery Logging**:

- Recovery attempt count and timing (Attempt 1: immediate, Attempt 2: +2s, Attempt 3: +5s)
- Audio data flow timestamps (`lastAudioDataTime` updates)
- Stream error details from `onError` and `onDone` handlers
- Graceful degradation triggers and reasons

**Log Messages to Look For**:

```
Health check: Recording active, audio data flowing normally
Health check: No audio data for 2+ minutes, attempting recovery
Recovery attempt 1/3: Restarting audio stream
Recovery attempt 2/3: Waiting 2s before restart
Recovery attempt 3/3: Waiting 5s before restart
Graceful degradation: 3 recovery attempts failed, switching to Silent
Audio stream error: [error details]
Audio stream closed unexpectedly: [reason]
```

**Debugging Tools**:

- **Flutter logs**: `dart-flutter_get_runtime_errors` for Flutter-specific errors, or `adb logcat` for full system logs
- **Notification timing**: Check if "Listening stopped" appears after ~7 seconds of failure
- **Settings verification**: Confirm background duration matches expected timeout behavior
- **Battery stats**: Monitor if wake lock is held for expected duration

**Common Debugging Scenarios**:

- **Frequent recoveries**: Check for audio focus conflicts or hardware issues
- **Immediate failures**: Usually permission or microphone hardware problems
- **Timeout after exact duration**: Normal behavior for time-limited sessions
- **No recovery attempts**: Health monitoring may not be running (check provider initialization)

## Troubleshooting Guide

### "Listening Stopped" Notification

When you see "Listening stopped - could not recover audio recording" notification:

**What this means**: The app detected a failure in audio recording and could not automatically recover after 3 attempts.

**Common causes**:

- **Audio focus loss**: Phone calls, other apps playing audio, system sounds
- **Hardware disruption**: Airplane mode toggle, headphone connection changes
- **System resource constraints**: Low memory or CPU affecting audio processing
- **Permission issues**: Microphone permission revoked or restricted

**Immediate solutions**:

1. **Open Settings** (notification action): Re-enable listening mode
2. **Restart the app**: Clear any transient system issues
3. **Check audio focus**: Stop any other audio-playing apps
4. **Verify permissions**: Ensure microphone permission is granted

**Prevention**:

- Use appropriate **Background Listening Duration** settings to balance battery and reliability
- Avoid frequent airplane mode toggles during active listening sessions
- Close unnecessary apps when using extended background listening

**If the problem persists**:

- Check device storage space (low storage can affect audio processing)
- Restart the device to clear system-level audio issues
- Report the issue with device model and Android version for further investigation

### Background Listening Not Working

**Symptoms**: App stops listening when backgrounded or screen locked

**Solutions**:

1. **Check Background Listening Duration**: Set to desired time limit (not "Unlimited" for testing)
2. **Verify Notification**: Look for "Listening..." notification when backgrounded
3. **Disable Battery Optimization**: In Android settings, allow app to run in background
4. **Check Do Not Disturb**: Ensure it doesn't silence notifications from the app

### Battery Drain Concerns

**If background listening drains battery quickly**:

1. **Reduce Background Listening Duration**: Choose shorter limits (30min-2hr)
2. **Monitor Health**: Check if recovery attempts are frequent (indicates underlying issues)
3. **Close Other Apps**: Reduce background processing load on device

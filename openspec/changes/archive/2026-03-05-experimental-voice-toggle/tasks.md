## 1. Settings Model

- [x] 1.1 Add `continuousVoiceEnabled` field (default `false`) to `Settings` class in `lib/models/settings.dart` with constructor, `copyWith`, `toJson`, `fromJson` (migration: absent → `false`), `==`, `hashCode`
- [x] 1.2 Change `Settings.defaults()` voice mode from `VoiceMode.conversation` to `VoiceMode.silent`

## 2. Settings Provider

- [x] 2.1 Add `updateContinuousVoiceEnabled(bool)` method to `SettingsNotifier` that persists the value and clamps voice mode to `silent` when disabling while in `listening` or `conversation`
- [x] 2.2 Update `updateVoiceMode()` to reject `listening`/`conversation` when `continuousVoiceEnabled` is `false`

## 3. Settings Page Tab Structure

- [x] 3.1 Convert `SettingsPage` from single `ListView` to `DefaultTabController` + `TabBar` with three tabs: "Connection", "Voice", "Features"
- [x] 3.2 Move backend selection, URL/model config, auth settings, and connection test controls into the Connection tab
- [x] 3.3 Move voice model management and TTS settings (speaker, speed) into the Voice tab (conditionally hidden on web)
- [x] 3.4 Create Features tab with continuous voice toggle (`SwitchListTile`), experimental label, description text, platform info, and conditional background listening duration dropdown — only show the toggle when `VoiceCapabilities.isBackgroundListeningAvailable` is `true`

## 4. Chat UI

- [x] 4.1 In `chat_page.dart`, conditionally show `VoiceModeSelector` only when `continuousVoiceEnabled` is `true` (keep existing ASR availability check)
- [x] 4.2 In `agentic_chat_page.dart`, apply same conditional for `VoiceModeSelector`

## 5. Background Service Gating

- [x] 5.1 In `recording_provider.dart`, check `continuousVoiceEnabled` before entering continuous recording mode — skip if disabled
- [x] 5.2 In `background_service_provider.dart`, skip service activation when `continuousVoiceEnabled` is `false`

## 6. Verification

- [x] 6.1 Run `dart-flutter_analyze_files` and fix all analysis issues
- [x] 6.2 Run existing tests to confirm no regressions
- [x] 6.3 Manually verify: fresh install defaults to `silent` mode, no mode selector visible, Features tab shows toggle off
- [x] 6.4 Manually verify: enabling toggle shows mode selector in chat, disabling while in continuous mode transitions to `silent`

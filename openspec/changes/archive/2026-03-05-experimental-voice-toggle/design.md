## Context

The settings page is currently a single `ListView` inside a `Scaffold` with no tab structure. Voice mode defaults to `VoiceMode.conversation` (continuous recording + auto-playback), which immediately activates background services, health monitoring, and foreground notifications. The `VoiceModeSelector` widget in the chat app bar lets users toggle between four modes by combining two independent axes: playback (on/off) and continuous listening (on/off).

Continuous voice features (continuous recording, auto-playback, background audio service, health monitoring) are unreliable and only work on Android and Linux. They need to be gated behind an opt-in toggle.

## Goals / Non-Goals

**Goals:**
- Gate continuous voice modes behind a persisted opt-in toggle, off by default
- Add a "Features" tab to settings for feature toggles (reusable for future features)
- Simplify the chat UI when continuous voice is disabled (hide mode selector)
- Change default voice mode to `silent` for new installs
- Ensure graceful migration for existing users

**Non-Goals:**
- Refactoring the voice mode system itself (the four modes stay as-is)
- Fixing the underlying reliability issues in continuous voice
- Changing the recording or playback providers beyond respecting the toggle

## Decisions

### 1. Settings page gains tab navigation

**Decision:** Convert the settings page from a single `ListView` to a `TabBar` with three tabs: "Connection" (backend config, auth), "Voice" (voice models, TTS settings like speaker/speed), and "Features" (feature toggles starting with continuous voice).

**Rationale:** The settings page is already long. Splitting into logical groups improves discoverability. Voice settings are a natural grouping (model management, TTS config) separate from connection/auth. The Features tab is extensible for future toggles.

**Alternative considered:** Two tabs (Connection + Features) with voice settings staying in Connection — rejected because voice settings are unrelated to connection config and the page would remain cluttered.

### 2. New `continuousVoiceEnabled` boolean in Settings model

**Decision:** Add `continuousVoiceEnabled` field (default `false`) to the `Settings` class with JSON serialization and migration support.

**Rationale:** A single boolean is the simplest mechanism. It controls whether `listening` and `conversation` modes (the two continuous recording modes) are available. When off, only `silent` and `reading` (dictation-based) modes are reachable.

**Alternative considered:** A set of individual feature flags — over-engineered for one toggle; can be added later if needed.

### 3. Default voice mode changes to `silent`

**Decision:** Change `Settings.defaults()` to use `VoiceMode.silent` instead of `VoiceMode.conversation`.

**Rationale:** With continuous voice off by default, the default mode must be dictation-only. `silent` is the least surprising starting state — no recording, no playback.

**Migration:** Existing users who deserialize settings with `continuousVoiceEnabled` absent get `false`. If their saved `voiceMode` is `listening` or `conversation`, the provider clamps it to `silent` on load.

### 4. VoiceModeSelector conditionally shown in chat app bar

**Decision:** Both `chat_page.dart` and `agentic_chat_page.dart` check `settings.continuousVoiceEnabled` before rendering the `VoiceModeSelector`. When disabled, only the dictation `RecorderButton` remains.

**Rationale:** The mode selector's two axes (playback toggle, listening toggle) only make sense when continuous modes are available. Without them, the user has `silent` and `reading` — playback toggling can happen via an existing mechanism or a simpler single toggle if needed. For the initial implementation, hiding the selector entirely keeps the UI clean.

### 5. Enforcement in SettingsNotifier

**Decision:** `updateVoiceMode()` checks `continuousVoiceEnabled` and rejects `listening`/`conversation` when the toggle is off. A new `updateContinuousVoiceEnabled()` method handles the toggle and clamps the current voice mode if needed.

**Rationale:** Centralizing enforcement in the provider prevents invalid state regardless of how voice mode is set (UI, migration, future API).

### 6. Background listening duration moves under the toggle

**Decision:** The background listening duration dropdown is only shown when `continuousVoiceEnabled` is true, inside the Features tab under the continuous voice toggle.

**Rationale:** This setting only applies to continuous recording. Showing it when the feature is off is confusing.

### 7. Platform-aware toggle visibility

**Decision:** The continuous voice toggle in the Features tab is only shown when `VoiceCapabilities.isBackgroundListeningAvailable` is `true` (all native platforms, not web). The platform info text clearly states that background services are currently only implemented on Android. Other native platforms (iOS, macOS, Linux) can enable it but should expect missing functionality (no foreground service, no wake locks, no notifications).

**Rationale:** The codebase already uses `VoiceCapabilities` to guard voice UI. Allowing the toggle on all native platforms avoids blocking users who want to experiment, while the explicit "Currently implemented on Android" messaging sets correct expectations.

### 8. Feature presentation in the UI

**Decision:** When visible, the continuous voice toggle includes:
- A `SwitchListTile` with title "Continuous Voice" and a subtitle badge/label "(Experimental)"
- A brief description below: "Enables continuous recording and auto-playback modes. This feature is experimental and may be unreliable."
- Platform info: "Background service currently implemented on Android only."
- When enabled: the background listening duration dropdown appears below

**Rationale:** Users need to understand what they're opting into, what platforms it works on, and that it may not work perfectly.

## Risks / Trade-offs

- **Existing users lose continuous mode on update** → Acceptable trade-off. The feature was unreliable, and users can re-enable it with one toggle. Migration sets them to `silent` with a smooth path to opt back in.
- **Two places to configure voice** (Features tab toggle + chat app bar selector) → The app bar selector only appears when the toggle is on, so this is a progressive disclosure pattern, not fragmentation.
- **Tab navigation adds complexity to settings page** → Minimal. Flutter's `DefaultTabController` + `TabBarView` is straightforward. Existing connection content moves into the first tab, voice settings (models, TTS speaker/speed) into the second, and features into the third.

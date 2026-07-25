# Proposal: android-mic-routing

## Why

ASR recordings on Android repeatedly capture from the built-in microphone even when a Bluetooth headset is connected — a long-standing, recurring bug. The root cause is structural: routing state is spread across three uncoordinated layers (Dart `audio_session` calls, the `record` plugin's `AudioRecord`, and the Kotlin `AudioBackgroundService`), none of which can await or verify the actual route. The current fix polls global state and remains a timing patch; this change replaces it with a single native owner of microphone routing built on the Android APIs designed for this purpose.

## What Changes

- New native Kotlin `MicRouter` becomes the single writer of Android audio routing state (audio mode, communication device). It selects the input device, awaits the real route-change callback (`onCommunicationDeviceChanged`), and verifies the actual recording route via `AudioRecordingCallback`.
- Bluetooth SCO becomes session-scoped: brought up on first recording, held across consecutive utterances, released after 5 s idle so other apps' A2DP playback resumes promptly. Today it is torn down after every recording, paying ~0.5–1 s reconnect latency each time.
- Users can override the automatic microphone choice via long-press on the recording button; the button shows a symbol matching the active input device (built-in, Bluetooth, wired/USB).
- **BREAKING (behavior):** Bluetooth microphone routing is now Android 12+ (API 31) only. The pre-31 legacy `startBluetoothSco` path is removed; older devices fall back to the built-in microphone. minSdk stays 24.
- All Dart-side `AndroidAudioManager` SCO manipulation in `NativeVoiceService` is deleted; `audio_session` remains for focus/config and iOS.
- `AudioBackgroundService` no longer resets the audio mode (single-writer rule).

## Capabilities

### New Capabilities

- `microphone-selection`: Input device enumeration, automatic Bluetooth-first selection with manual per-device override, override UI via long-press on the recording button, active-device symbol on the button, preference persistence and fallback when a pinned device is absent.

### Modified Capabilities

- `bluetooth-audio-routing`: Routing ownership moves to the native MicRouter. Recording start SHALL await the authoritative route-change callback (not polls or sticky broadcasts) with a bounded timeout; the actual recording route SHALL be verified and logged; SCO is released after 5 s idle instead of per-recording teardown; the pre-API-31 legacy SCO requirement is removed.
- `voice-integration-abstraction`: `VoiceService` gains an input-device surface (list devices, set preference, device-change events, active-device info) so UI can render the picker and symbol; stub/web implementations report the capability as unavailable.
- `chat-input`: The recording button gains long-press (open microphone picker) and a visual indicator of the active input device, in both chat and agentic inputs.

## Impact

- **Android native:** new `MicRouter.kt`; `MainActivity` channel registration; `AudioBackgroundService.kt` loses its audio-mode reset.
- **Dart:** new `lib/voice/mic_router.dart` facade; `lib/voice/voice_service_native.dart` sheds `_activateBluetoothScoIfAvailable`/`_deactivateBluetoothSco`/`_pollUntil` (~120 lines); `voice_service.dart`/`voice_service_stub.dart` interface additions; recording button widgets in `lib/chat/widgets.dart` and `lib/agentic/widgets.dart`; mic preference persisted via existing user settings storage.
- **Dependencies:** none added; `record` and `audio_session` stay at current versions.
- **Tests:** unit tests for the Dart facade (mocked MethodChannel), widget tests for long-press picker and device symbol; on-device verification protocol for BT scenarios.
- **iOS:** unchanged behavior (OS already auto-prefers BT mic); picker backend for iOS is out of scope.

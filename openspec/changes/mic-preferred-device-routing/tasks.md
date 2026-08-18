## 1. Native: narrow MicRouter to enumeration + diagnostics

- [ ] 1.1 Rename `android/app/src/main/kotlin/org/venkado/relagent/MicRouter.kt` to reflect its narrowed role (e.g. `MicDeviceEnumerator.kt`), updating the class name and method-channel name (`com.relagent.mic_router` → e.g. `com.relagent.mic_devices`) to match.
- [ ] 1.2 Delete the routing-decision code: `selectDevice()`, `handleQuerySelection()`/`querySelection`, `handleEnsureReady()`/`ensureReady31()`, `setCommunicationDevice()`/`clearCommunicationDevice()` calls, `scheduleIdleRelease()`/`cancelIdleRelease()`/`releaseNow()`, the `targetDevice`/`routeHeld` state.
- [ ] 1.3 Keep `listInputs()`, `categoryOf()`, `deviceMap()`, `typeToString()` (device enumeration) and the `deviceCallback`/`AudioDeviceCallback` (device-change events) unchanged.
- [ ] 1.4 Keep the `recordingCallback`/`AudioManager.AudioRecordingCallback` diagnostic (logs actual vs. target route) — update its comment to reference `setPreferredDevice()` as the new "target" source instead of `setCommunicationDevice()`.
- [ ] 1.5 Add a method (or reuse existing enumeration) to resolve a stored category+address to the device's *current* numeric ID, for handoff to `record`'s `InputDevice.id` (see design.md - "Keep a slim native device-enumeration helper").

## 2. Dart facade

- [ ] 2.1 Rename `apps/lib/voice/mic_router.dart` to match the native rename; keep `listInputs()`/device-change stream, remove `ensureReady()`/`querySelection()`/`releaseAfterIdle()`/`releaseNow()` and `MicSelectionResult`/`MicSelectionStatus` (or repurpose `MicSelectionStatus` if still needed for the "pinned device absent, fell back to auto" reporting required by `microphone-selection` - "Preference Persistence and Fallback").
- [ ] 2.2 Add a method that, given a `MicPreference`, resolves it against the current device list and returns either `null` (use default/no preferred device) or the matching device's current native ID + display name, ready to build a `record` `InputDevice`.

## 3. Preference resolution

- [ ] 3.1 Update `apps/lib/providers/mic_preference_provider.dart` to resolve `MicPreference` against the new enumeration (task 2.2) instead of the old `MicRouter` candidate list. Preserve existing behavior: auto prefers Bluetooth when connected, pinned falls back to auto (reporting fallback) when the pinned device is absent.
- [ ] 3.2 Update `apps/lib/voice/voice_service.dart` / `voice_service_native.dart` / `voice_service_stub.dart` as needed so `NativeVoiceService` no longer holds a `MicRouter`/`MicSelectionResult`, and exposes whatever the recording paths (task 4) need to build their `RecordConfig`.

## 4. Recording paths

- [ ] 4.1 In `apps/lib/speech_recognition/sherpa_vad_asr.dart`, replace the `MicRouter`-based flow with: resolve preference → build `record`'s `InputDevice` (or `null`) → pass via `RecordConfig(device: ...)`. Set `manageBluetooth: true` (see design.md decision). Keep `audioSource: AndroidAudioSource.voiceCommunication`.
- [ ] 4.2 Apply the same change to `apps/lib/speech_recognition/services.dart`'s streaming `ASR` class, for consistency with `VadAsr` per the proposal's scope (both ASR paths, not just whisper).
- [ ] 4.3 Remove the `isBluetoothRoute` plumbing added for VAD/high-pass tuning (`AsrService.start({bool isBluetoothRoute})`, the `_lastMicSelection`/`MicDeviceCategory.bluetooth` check in `voice_service_native.dart`) only if the new mechanism can no longer reliably determine "is this a Bluetooth recording" the same way — otherwise keep it, sourced from the resolved device instead of `MicSelectionResult`.
- [ ] 4.4 Drop the `configureAudioSessionForRecording()` call into `_micRouter.ensureReady()` and any `_micRouter.releaseAfterIdle()`/`releaseNow()` calls in `voice_service_native.dart`, per design.md's decision not to replace the idle-hold cycle.

## 5. UI

- [ ] 5.1 Verify `apps/lib/speech_recognition/mic_selection_widgets.dart` still works against the new enumeration source (task 2) without changes to its own logic — it consumes `MicDevice`/`MicPreference`/`micDevicesProvider`, which should keep their shape.
- [ ] 5.2 Verify `micSelectionProvider` (in `mic_preference_provider.dart`) still produces a value the "Active Input Device Indicator" requirement (`microphone-selection`) can render from, now that it no longer comes from `MicRouter.querySelection()`.

## 6. Diagnostics dump

- [ ] 6.1 Update `AudioBackgroundService.kt`'s "=== Android AudioManager Routing ===" dump: the "Available communication devices" / "Current communication device" section is no longer meaningful for recording and should either be removed or clearly re-labeled as informational-only (it may still reflect other apps' or the OS's own state).

## 7. Cleanup

- [ ] 7.1 Update or remove tests referencing `MicRouter`'s removed methods (`ensureReady`, `querySelection`, `MicSelectionResult`, `MicSelectionStatus`) across `apps/test/`.
- [ ] 7.2 Update the `[[reference_bt_audio_debugging]]`-style debugging notes / code comments that describe the old `setCommunicationDevice()`-based flow, to describe the new one.
- [ ] 7.3 Run `fvm dart analyze` and `fvm flutter test`; fix any fallout from the renames/removals in tasks 1-6.

## 8. Manual verification

- [ ] 8.1 On a real device with a Bluetooth headset: pin to Bluetooth, record, and use the tap-mic-and-watch-amplitude check (see today's investigation) to confirm capture actually comes from the headset — not just that the API layer reports success.
- [ ] 8.2 Confirm auto-selection still prefers Bluetooth when connected, and falls back to built-in when not, matching `microphone-selection` - "Automatic Microphone Selection".
- [ ] 8.3 Confirm pinning to built-in mic still works and is unaffected by Bluetooth connection state.
- [ ] 8.4 Measure back-to-back recording latency (stop, then immediately start again) with Bluetooth active, to check whether dropping the idle-hold cycle (design.md risk) causes a noticeable regression.
- [ ] 8.5 Confirm TTS/playback routing (A2DP) is unaffected — start a recording, stop, then play TTS output, and confirm it still routes to the Bluetooth speaker when connected.

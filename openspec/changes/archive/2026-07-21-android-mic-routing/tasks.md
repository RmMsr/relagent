# Tasks: android-mic-routing

## 1. Native MicRouter (Kotlin)

- [x] 1.1 Create `MicRouter.kt` with device enumeration (`getDevices(GET_DEVICES_INPUTS)` filtered to built-in/BT SCO/BLE headset/wired/USB, exposing type, name, address) and the selection policy (pinned → Bluetooth → built-in), all no-op below API 31
- [x] 1.2 Implement `ensureReady(preference)`: cancel pending idle release, fast-path when current route matches target, otherwise `setCommunicationDevice()` + await `onCommunicationDeviceChanged` with 3 s timeout; return actual device and status (ok/timeout/fallback)
- [x] 1.3 Implement `releaseAfterIdle(5s)` timer and `releaseNow()` (`clearCommunicationDevice()` + `MODE_NORMAL`)
- [x] 1.4 Emit device-change events via `AudioDeviceCallback` and route-verification via `registerAudioRecordingCallback` (log actual routed device; warning + event on target mismatch)
- [x] 1.5 Register MethodChannel + EventChannel in `MainActivity`; remove the audio-mode reset from `AudioBackgroundService.kt` (single-writer rule)

## 2. Dart Integration

- [x] 2.1 Create `lib/voice/mic_router.dart` facade: typed device model, all channel calls wrapped so failures degrade to default-device + log (never block recording)
- [x] 2.2 Extend `VoiceService`/`VoiceCapabilities` with the input-device surface (list, preference, active device, events, `isInputSelectionAvailable`); stub returns unavailable/empty
- [x] 2.3 Wire `NativeVoiceService`: `ensureReady` in `configureAudioSessionForRecording`, `releaseAfterIdle` in `stopRecording`, `releaseNow` in `configureAudioSessionForPlayback`; delete `_activateBluetoothScoIfAvailable`, `_deactivateBluetoothSco`, `_pollUntil`
- [x] 2.4 Persist mic preference (`auto` or `{type, address, name}`) via existing user-settings storage; pass into `ensureReady`; fall back to auto when pinned device absent

## 3. Recording Button UI

- [x] 3.1 Create shared recording-button widget: active-device symbol (plain mic / BT-badged / wired-USB-badged) driven by active-device info and device events (existing shared `RecorderButton` extended; `MicSymbol` + picker in new `mic_selection_widgets.dart`)
- [x] 3.2 Add long-press → microphone picker (Automatic + named devices, current selection marked); no-op when input selection unavailable
- [x] 3.3 Integrate the shared widget in both `chat/widgets.dart` and `agentic/widgets.dart` without changing tap behavior (both already use the shared `RecorderButton`; no per-widget changes needed)

## 4. Tests

- [x] 4.1 Unit tests for `mic_router.dart` with mocked MethodChannel: ready-status handling, timeout status, exception degradation, release scheduling calls
- [x] 4.2 Unit tests for `NativeVoiceService` sequencing: ensureReady before stream start, releaseAfterIdle on stop, releaseNow on playback, old SCO code gone
- [x] 4.3 Widget tests: long-press opens picker and updates preference, symbol reflects active device and updates on device-change event, unsupported platform shows plain mic and ignores long-press
- [x] 4.4 Run `fvm flutter analyze` and full `fvm flutter test`; keep existing audio-coordinator and dictation tests green (295 tests pass)

## 5. On-Device Verification

- [x] 5.1 Build debug APK with `--dart-define=debug_logs_enabled=true`, install on FP4, capture via `adb logcat` (protocol from memory: buffer bump, clear, reproduce, dump)
- [x] 5.2 Verify scenarios on FP4: no-BT recording, first BT recording (route awaited, then verified BLUETOOTH_SCO), rapid consecutive recordings (fast-path, no reconnect), other-app playback resumes after idle release
- [x] 5.3 Verify long-press picker and device symbol on device (pin built-in with headset connected, confirm recording uses built-in and symbol matches)

## 6. Findings and Simplification

- [x] 6.1 Root-caused the recurring built-in-mic bug: the `record` plugin's own legacy Bluetooth manager (`manageBluetooth`, default `true`) called `startBluetoothSco()` independently, racing MicRouter — fixed by disabling it and dropping `audioManagerMode` so MicRouter is the sole writer
- [x] 6.2 Fixed false-positive route mismatch (compared `AudioDeviceInfo.id` across two enumeration APIs that don't share an id space; now compares type + address)
- [x] 6.3 Tried and removed auto-correction (restart on detected mismatch, then an unconditional Bluetooth settle timer): both caused restart/reconfigure loops without fixing the symptom
- [x] 6.4 Established the ceiling: the FP4's Qualcomm HAL was observed capturing from `speaker-mic` while every Android API self-consistently reported `BLUETOOTH_SCO`. No app-level signal can distinguish that from a correct recording, so routing is best effort — see design D3
- [x] 6.5 Simplified to the proven set: removed all correction machinery, collapsed the MicRouter event stream to device changes only, kept route verification as native diagnostic logging

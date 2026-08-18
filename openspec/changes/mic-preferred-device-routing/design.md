## Context

See `proposal.md` - Why for the motivating failure and the API-level rationale. This section covers only implementation constraints discovered while researching the replacement.

`record`'s public Dart `InputDevice` (the type `RecordConfig.device` accepts) exposes only `id` and `label` — no device type/category and no stable address. On the native side (`record_android`'s `DeviceUtils.kt`), `id` is `AudioDeviceInfo.id.toString()` — the same non-reboot-stable numeric ID that `microphone-selection`'s existing "Preference Persistence and Fallback" requirement already explicitly rejects as an identity key ("not by platform device ID, which is not stable across reboots"), and `label` is a human-readable string like `"<product name> (Bluetooth telephony SCO, <mac address>)"` with no documented, version-stable format. Neither field alone lets us implement the existing category+address pinning model.

## Goals / Non-Goals

**Goals:**
- Replace `setCommunicationDevice()`-based routing with `AudioRecord.setPreferredDevice()` for both `VadAsr` and the streaming `ASR` class.
- Preserve today's `MicPreference` model (auto / pinned by category+address) and its persistence exactly as-is at the Dart level — this is an internal mechanism swap, not a UX change.
- Keep the existing diagnostic-only route-mismatch logging (`bluetooth-audio-routing` - "Best-Effort Routing with Diagnostic-Only Verification").

**Non-Goals:**
- Guaranteeing Bluetooth capture works on all hardware. Today's investigation already established that no app-level API can guarantee this; this change picks the most direct available API, not a guaranteed fix.
- Changing TTS/playback routing — `configureAudioSessionForPlayback()` and A2DP output are untouched.
- Adopting `flutter_sound` or a lower-level audio engine (AAudio/Oboe via FFI) — noted in the proposal as considered alternatives, not pursued here.

## Decisions

### Keep a slim native device-enumeration helper; do not delete `MicRouter.kt` outright

The proposal's Impact section says `MicRouter.kt` is removed. Refining that here: its **routing-decision** code (`selectDevice()`, `ensureReady()`, `querySelection()`, `setCommunicationDevice()`/`clearCommunicationDevice()`, the idle-release `Runnable`/`Handler` scheduling) is deleted — that's the part this change replaces. Its **enumeration** code (`listInputs()`, `categoryOf()`, `deviceMap()`, `typeToString()`) and its **diagnostic** code (`recordingCallback`/`AudioRecordingCallback`, used by "Best-Effort Routing with Diagnostic-Only Verification") are kept, because `record`'s own enumeration can't supply the category+address identity our preference model needs (see Context). The file is renamed to reflect its narrowed role (e.g. `MicDeviceEnumerator.kt`) and its Dart facade (`mic_router.dart`) is renamed/slimmed to match — `listInputs()`/device-change events survive, `ensureReady()`/`querySelection()` do not.

At the point a recording actually starts, the resolved preference (category+address) is matched against a **fresh** enumeration to get the device's current numeric ID, which is then passed to `record` as `InputDevice(id: <that id>, label: <display name>)`. This works because both this helper and `record_android`'s `DeviceUtils` read from the same `AudioManager.getDevices(GET_DEVICES_INPUTS)` call, so a device's ID is consistent between the two at the same point in time even though it isn't stable across reconnects.

**Alternative considered**: parse `record`'s `InputDevice.label` string to recover type/address. Rejected — undocumented format, no version-stability guarantee, and `record_android`'s own `typeToString()` (source of the label) could change wording between releases without a semver-visible break.

### Re-enable `AndroidRecordConfig.manageBluetooth`

Today it's explicitly `false`, to keep `record`'s own legacy `AudioManager.startBluetoothSco()`-based connection management from racing `MicRouter`'s `setCommunicationDevice()` calls (see the existing code comment in `sherpa_vad_asr.dart`/`services.dart`). With `MicRouter`'s routing removed, nothing else establishes the Bluetooth SCO link — `record_android`'s `RecorderWrapper.maybeStartBluetooth()` already contains the exact logic needed (it starts/stops SCO based on whether `config.device` is a `TYPE_BLUETOOTH_SCO` device), so `manageBluetooth` flips to `true` to let it do that job. This is the one part of the chain that still touches the legacy SCO connection API rather than `setPreferredDevice()` itself — `setPreferredDevice()` selects the device, `manageBluetooth` establishes the underlying SCO link it needs to exist.

### Keep `AndroidAudioSource.voiceCommunication`; drop `MODE_IN_COMMUNICATION`

`MediaRecorder.AudioSource.VOICE_COMMUNICATION`'s acoustic-echo-cancellation/noise-suppression behavior is a property of the audio *source* type, independent of `AudioManager.mode`. Dropping the explicit `MODE_IN_COMMUNICATION` (and the `setCommunicationDevice()` call that required it) does not require giving up AEC/NS — they're separate axes. No code change needed here beyond what the proposal already states; documented as an explicit decision because it wasn't obvious without checking.

### Drop the 5-second idle-hold/release cycle without a replacement

Per proposal.md, this existed only to amortize `setCommunicationDevice()`'s connection-establishment latency across consecutive recordings. `setPreferredDevice()` has no equivalent explicit hold/release step, and `manageBluetooth`'s SCO connection (see above) is `record`'s concern, not something this app schedules. If consecutive-recording latency regresses in practice, that's a measurable follow-up, not something to build speculatively now.

## Risks / Trade-offs

- **`manageBluetooth: true`'s legacy SCO path may have its own reliability quirks**, untested by today's investigation (which only exercised `setCommunicationDevice()`). → Mitigation: verify on the same real-hardware setup that exposed today's original bug before considering this change validated; the tap-mic-and-watch-amplitude test from today's session is a fast, reusable manual check.
- **Consecutive-recording SCO reconnect latency may regress** now that the explicit idle-hold is gone. → Mitigation: measure during manual verification; if it regresses, a follow-up change can add hold logic scoped to `record`'s own Bluetooth connection lifecycle rather than reintroducing `MicRouter`.
- **`setPreferredDevice()` is itself only "best effort"** per Android's own documentation — it can be silently ignored by the platform in principle. → Mitigation: unchanged from today — the existing diagnostic-only logging requirement stays, no correction/retry behavior is attempted, consistent with `bluetooth-audio-routing`'s existing philosophy.
- **Two ASR paths (`VadAsr`, streaming `ASR`) both change together** rather than validating one first. → Mitigation: proposal explicitly chose both for consistency; task breakdown should still let them be implemented and tested as separable steps.

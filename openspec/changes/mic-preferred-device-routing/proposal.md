## Why

Live on-device debugging established that `MicRouter`'s Bluetooth routing mechanism — `AudioManager.setCommunicationDevice()` / `MODE_IN_COMMUNICATION`, paired with `AndroidAudioSource.voiceCommunication` — can silently fail on real hardware: every API in the chain reports success (`setCommunicationDevice()` returns true, `getCommunicationDevice()` confirms Bluetooth, the recording-configuration callback reports the Bluetooth device), yet a physical out-of-band check (tapping the Bluetooth mic and watching the amplitude meter) showed capture never left the built-in mic. `bluetooth-audio-routing`'s own spec already names this exact failure mode ("Platform reports a route the hardware does not honor") and accepts it as undetectable and uncorrectable at this API layer — because `setCommunicationDevice()` is a paired, bidirectional API designed for phone-call-style audio (input and output moving together), and this app never needed that pairing: dictation only cares about input, and TTS playback already has its own independent audio-session configuration.

Android exposes a different, input-only mechanism for exactly this case — `AudioRecord.setPreferredDevice(AudioDeviceInfo)` (API 23+) — which the `record` package (already a dependency) already wires end-to-end via its public `RecordConfig.device` field, currently unused. It pins a specific recorder instance to a specific input device directly, with no communication-device pairing and no audio-mode side effects, so it cannot suffer the same input/output HAL divergence. This change replaces `MicRouter`'s routing mechanism with it, for both ASR paths (not just whisper).

## What Changes

- **BREAKING**: Remove `MicRouter`'s routing-decision responsibility (native `MicRouter.kt` and its Dart facade `mic_router.dart` are narrowed to device enumeration and diagnostics only — see design.md). Android audio-mode and communication-device management is dropped entirely for recording.
- Resolve the user's microphone preference (auto / pinned by category+address — concept unchanged) against `record`'s own `AudioRecorder.listInputDevices()` result instead of `MicRouter`'s `availableCommunicationDevices` candidate list.
- Apply the resolved device via `RecordConfig(device: InputDevice(...))` (`AudioRecord.setPreferredDevice()`), in both `VadAsr` (offline/whisper path) and `ASR` (streaming path) — today only `VadAsr` goes through `MicRouter` at all in terms of mic selection consequence, but both share the same `RecordConfig` construction pattern and should use the same mechanism for consistency.
- Keep `AndroidAudioSource.voiceCommunication` as the audio source (for its acoustic echo cancellation / noise suppression benefit) but stop setting `AudioManager.mode` / `MODE_IN_COMMUNICATION` and stop calling `setCommunicationDevice()` — device selection and audio-mode/AEC-NS-source selection are now independent concerns.
- Bluetooth device connect/disconnect handling (used today to refresh the picker and re-resolve "auto") is preserved via `record`'s own device enumeration and change events, not `MicRouter`'s `AudioDeviceCallback`.
- Drop the SCO idle-release/session-hold logic (`releaseAfterIdle`/`releaseNow`, the 5s hold) — it existed to avoid repeated SCO (re)connect latency under the communication-device model; `setPreferredDevice()` has no equivalent connection-establishment step to amortize.
- Note, not adopted: `flutter_sound` was considered as an alternative recording package. It offers device selection through the same underlying Android APIs `record` already exposes — switching packages would mean replacing the whole recording library for no structural advantage over just using the field `record` already has. Not proposed here.
- Note, not adopted: raw `AAudio`/Oboe via FFI would give the most direct hardware control but is a much larger lift (custom native audio engine) than swapping a config field. Only worth revisiting if `setPreferredDevice()` itself turns out unreliable on real hardware.

## Capabilities

### New Capabilities
(none — this replaces the mechanism behind an existing capability, it doesn't introduce new user-facing capability)

### Modified Capabilities
- `bluetooth-audio-routing`: The routing mechanism changes from `MicRouter`'s communication-device API to `AudioRecord.setPreferredDevice()`. Requirements describing `MicRouter` as sole owner of Android audio-mode/communication-device state, the SCO session-hold/idle-release lifecycle, and the "best-effort, diagnostic-only" framing around communication-device divergence no longer apply as written and need replacement requirements describing the new mechanism's guarantees and remaining best-effort caveats (`setPreferredDevice()` can still be silently overridden by the platform in principle, per Android's own documentation, though it is not known to suffer the same failure observed here).
- `microphone-selection`: Preference persistence and resolution (auto/pinned) is unchanged in user-facing terms, but "Input Device Enumeration" and "Preference Persistence and Fallback" need their underlying source updated from `MicRouter`'s device list to `record`'s `listInputDevices()` / `InputDevice`.

## Impact

- Narrowed and renamed: `android/app/src/main/kotlin/org/venkado/relagent/MicRouter.kt` and its Dart facade `apps/lib/voice/mic_router.dart` — routing-decision code is removed, device-enumeration and diagnostic-logging code is kept (see design.md for why the enumeration code can't simply move to `record`'s own API).
- Modified: `apps/lib/voice/voice_service_native.dart` (drop `_micRouter`/`MicSelectionResult` plumbing, resolve+apply device directly), `apps/lib/speech_recognition/sherpa_vad_asr.dart` and `apps/lib/speech_recognition/services.dart` (`RecordConfig(device: ...)`, drop `voiceCommunication` audio-mode assumption reasoning), `apps/lib/providers/mic_preference_provider.dart` (resolve against `record`'s device list), `apps/lib/speech_recognition/mic_selection_widgets.dart` (device list source), `apps/lib/voice/voice_service.dart` (drop `MicRouter`-shaped types if no longer needed, or adapt them to wrap `record`'s `InputDevice`).
- Also touches `AudioBackgroundService.kt`'s routing diagnostic dump (`availableCommunicationDevices` section becomes irrelevant to recording; may be trimmed or kept purely informational).
- No changes needed to `sherpa_onnx`/ASR decoding — this is purely upstream of where audio samples enter the recognizer.
- Dependencies: no new packages; `record` is already a direct dependency and already supports this via `RecordConfig.device`.

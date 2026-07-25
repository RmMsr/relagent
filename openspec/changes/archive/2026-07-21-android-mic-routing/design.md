# Design: android-mic-routing

## Context

ASR on Android intermittently records from the built-in mic despite a connected Bluetooth headset. Investigation on-device (branch `changes/gentlespark`) established the mechanics: BT SCO connects asynchronously (~0.5–1 s) after it is requested, `record`'s `AudioRecord` binds to whichever mic is active at open time, and the only Dart-visible "connected" signal (`scoAudioEventStream`) is a sticky broadcast that replays stale state. The interim fix polls `getCommunicationDevice()` from Dart — it works but is a timing patch layered on a structural problem: routing state is written by three uncoordinated layers (Dart `audio_session` calls, the `record` plugin, and `AudioBackgroundService`'s mode reset), and no layer can await or verify the actual route.

Industry reference: interactive-voice apps (WebRTC's `AppRTCAudioManager` pattern, Google's API-31 guidance) all use a native routing manager that treats SCO bring-up as an async state machine and opens the mic only after the route is confirmed. iOS needs none of this: `AVAudioSession` with `playAndRecord` + `.allowBluetooth` + `.voiceChat` auto-prefers the headset mic, which is why the bug is Android-only.

Constraints: minSdk 24; Fairphone FP4 (API 35) is the verification device; capture pipeline (`record` → sherpa-onnx) was just verified working and must not change.

## Goals / Non-Goals

**Goals:**

- Recording deterministically opens on the intended microphone; the actual route is verifiable in logs.
- One component owns Android routing state; all other writers removed.
- Consecutive utterances within 5 s start without SCO reconnect latency; other apps' A2DP playback resumes within ~5 s of the last recording.
- User can override the automatic choice via long-press on the recording button and sees the active device as a symbol on the button.
- Headset-less users and pre-API-31 devices pay zero latency and execute zero routing code.

**Non-Goals:**

- No change to capture (`record` plugin stays), ASR, or TTS pipelines.
- No pre-API-31 Bluetooth mic support (legacy `startBluetoothSco` path is deleted).
- No automatic stream restart, reconfigure, or settle delay when verification observes a wrong route — it logs only. Routing is best effort; divergence below the platform API layer (vendor HAL) is explicitly out of scope.
- No iOS mic picker backend (iOS auto-routing already works; interface is designed to admit one later).
- No handling of multiple simultaneous BT headsets beyond "first suitable device wins" in automatic mode.

## Decisions

### D1: Native Kotlin `MicRouter` owns routing; `record` keeps capture

A new `MicRouter.kt` (beside `AudioBackgroundService`) is the single writer of audio mode and communication device, exposed over a MethodChannel (commands) and EventChannel (device/route events). Dart calls `ensureReady(preference)` before `record.startStream()`.

- *Alternative — full native capture (WebRTC-ADM style):* strongest guarantee (`setPreferredDevice` on our own `AudioRecord`), but reimplements buffering/lifecycle/amplitude that `record` already does well, and splits Android/iOS capture paths. Rejected: too much new bug surface in the stable half of the pipeline.
- *Alternative — pure plugin (`record` 6 `manageBluetooth` + `device:`):* least code, but the SCO race moves inside the plugin where readiness can neither be awaited nor verified — the exact failure mode just diagnosed, made unobservable. Rejected.

### D2: Await `onCommunicationDeviceChanged`, not polls or broadcasts

`ensureReady` calls `setCommunicationDevice(target)` then suspends until `AudioManager.addOnCommunicationDeviceChangedListener` reports the target, with a 3 s timeout after which recording proceeds on the current route (status `timeout` returned to Dart). If the current route already matches the target, return immediately — this is the fast path for consecutive utterances.

- *Alternative — keep polling `getCommunicationDevice()`:* works (current interim fix) but is a busy-wait approximating exactly what this listener provides. Replaced.
- *Alternative — `scoAudioEventStream`:* sticky broadcast, replays stale "connected"; empirically defeated the wait. Rejected.

### D3: Verify the real route with `registerAudioRecordingCallback` — diagnostics only

While a session is active, MicRouter registers an `AudioRecordingCallback` (API 24+) and logs each active `AudioRecordingConfiguration`'s routed device — this reports where the `record` plugin's own `AudioRecord` actually landed, without owning it. The observation is logged natively and never drives behavior: no event to Dart, no restart, no reconfigure. Its value is turning a future regression into a one-log-line diagnosis.

**Confirmed by on-device testing, after this decision was briefly reversed and then restored.** Auto-restarting on a detected mismatch was tried and removed: it produced a reconfigure loop, then an unbounded restart loop, and never fixed the underlying symptom. Testing also established *why* no correction mechanism can work here — the FP4's Qualcomm HAL was observed selecting `speaker-mic` while every Android API, including this callback, self-consistently reported `BLUETOOTH_SCO`. When the framework and the hardware disagree, no app-level signal distinguishes a wrongly-routed recording from a correct one, so any "correction" fires on healthy recordings too. Routing is therefore best effort: request through the intended APIs, wait for the platform's readiness signal, record on what it reports.

### D4: Session-scoped SCO with 5 s idle release

`releaseAfterIdle()` (called on recording stop) schedules `clearCommunicationDevice()` + `MODE_NORMAL` after 5 s; a new `ensureReady` cancels the timer. Switching to TTS/playback calls `releaseNow()`. Rationale: SCO and A2DP are mutually exclusive on the headset, so holding SCO blocks other apps' music from resuming — 5 s (user-set bound) covers back-to-back dictation while releasing promptly.

- *Alternative — per-recording teardown (current):* exercises the connect race on every utterance and pays ~0.5–1 s latency each time. Rejected.
- *Alternative — app-lifetime hold:* zero latency but blocks A2DP continuously and drains headset battery. Rejected.

### D5: Android 12+ (API 31) only; single-writer rule enforced

All MicRouter routing methods are no-ops returning "default" below API 31; BT mic preference simply doesn't engage there (minSdk stays 24). The legacy `startBluetoothSco` path and all Dart-side `AndroidAudioManager` SCO code are deleted. `AudioBackgroundService`'s audio-mode reset is removed so MicRouter is the only writer. `audio_session` remains for focus/configuration and iOS.

### D6: Preference model and persistence

Preference is `auto` (default) or a pinned device stored as `{type, address, name}` — Android `AudioDeviceInfo.getId()` is not stable across reboots, so identity is matched by type + address (BT) or type (built-in/wired). If the pinned device is absent at `ensureReady` time, fall back to automatic and report that in the result. Persisted via the existing user-settings storage.

Automatic selection order: pinned device (if present) → Bluetooth (SCO or BLE headset) → built-in.

### D7: Override UX — long-press on the recording button

Long-press on the recording button opens a small picker (bottom sheet / menu) listing "Automatic" plus enumerated input devices, refreshed by MicRouter device events. The button's icon reflects the *active* input device: built-in → plain mic, Bluetooth → BT-badged mic, wired/USB → jack/USB-badged mic. Tap behavior is unchanged. The picker and symbol appear in both chat and agentic inputs via a shared widget; on platforms where the voice service reports no device surface (web stub, iOS for now), long-press does nothing and the plain mic icon shows.

- *Alternative — settings-page picker:* discoverable but far from the moment of use; user chose long-press at point of interaction.

### D8: Failure containment in the Dart facade

`mic_router.dart` wraps every channel call; any `PlatformException`/missing-plugin error degrades to "default device, log a warning" — routing problems must never block or delay recording beyond the bounded waits above.

## Risks / Trade-offs

- [OEM quirks: `onCommunicationDeviceChanged` may fire late or not at all on some vendors] → 3 s timeout proceeds anyway; D3 verification logs the truth, so field diagnosis is one log line.
- [5 s SCO hold still delays other apps' audio briefly] → bound chosen by user; `releaseNow()` on playback transitions inside our own app.
- [Long-press is low-discoverability] → the device symbol on the button hints at the affordance; acceptable for a power-user escape hatch.
- [LE Audio headsets (`TYPE_BLE_HEADSET`) behave differently from SCO] → `setCommunicationDevice` handles both uniformly on API 31+; treated as BT in selection order; not testable now (no LE Audio hardware) — verification logging will show reality when one appears.
- [A `record` plugin update could change its Android internals] → D3 verification detects route regressions immediately; capture API surface used is stable.
- [Sequencing contract ("ensureReady before startStream") lives in Dart convention] → single call-site in `NativeVoiceService`; spec scenario pins it; facade logs if startStream's verification fires without a prior ensureReady.

## Migration Plan

Behavior change only — no data migration. Deploy: implement behind the existing recording flow, verify on FP4 with the established logcat protocol (no-BT, first BT recording, rapid consecutive recordings, disconnect mid-recording, music-resume after idle release). Rollback: revert the commits; the deleted Dart polling fix is recoverable from git history.

## Open Questions

- Exact icon assets for the device symbol (Material `mic`, `headset`/`bluetooth_audio`, `usb`) — decide during implementation from what the app's icon set offers.
- Whether the picker should show device *names* (e.g. headset model from `AudioDeviceInfo.productName`) or generic type labels; prefer names, fall back to types.

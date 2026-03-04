## Context

`ModelDownloadNotifier.build()` returns `ModelDownloadState(downloadedModels: {})` synchronously and fires `_refreshDownloadedModels()` as a fire-and-forget async operation. Both consumers initialize before the scan completes:

- **TTS**: `TtsNotifier.initialize()` called from chat page `initState` (~1500ms after splash). `_getService()` calls `resolveTtsModel(settings, downloadState)` — if `downloadState` is empty, `isDownloaded()` returns false and the bundled model is used.
- **ASR**: `RecordingNotifier.checkAutoStart()` called on chat page mount. `_startASR()` reads `modelDownloadProvider` — same race, falls back to bundled.

## Goals / Non-Goals

**Goals:**
- TTS and ASR use the selected downloaded model even when the scan completes after initialization
- No disruption to in-progress TTS generation when the scan completes
- ASR restart only when actually recording in continuous mode

**Non-Goals:**
- Eliminating the startup race entirely (would require blocking startup on scan)
- Handling mid-session model changes triggered by new downloads (covered by existing settings listener)

## Decisions

### 1. Listener-based reactive reinitialization

**Decision:** Add `ref.listen<ModelDownloadState>` in both providers, triggering reinitialization when the selected model transitions from not-downloaded to downloaded.

**Why:** Riverpod listeners are the idiomatic reactive pattern. Alternatives considered:
- *Polling*: wastes CPU, adds latency
- *Blocking startup on scan*: adds startup latency for all users, not just those with downloads
- *Re-checking in generate()*: would need to reinitialize mid-stream, complex

### 2. TTS deferred reinit via `_pendingReinit` flag

**Decision:** If `_pendingTasks.isNotEmpty` when the model becomes available, set `_pendingReinit = true`. The `finally` block of `enqueue()`/`playNow()` triggers reinit after all tasks complete.

**Why:** `TtsService.reinitializeWithModel()` calls `_voiceService.disposeTts()` which does `Isolate.kill(priority: Isolate.immediate)`. If the isolate is processing a `GenerateAudioMessage`, killing it leaves `responsePort.first` awaiting a response that will never arrive — a permanent hang. Deferring until idle avoids this entirely.

**Alternative considered:** `Isolate.beforeNextEvent` instead of `immediate` — would let the current message finish before kill, but is fragile if the message hasn't started processing yet.

### 3. ASR restart only when actively recording

**Decision:** The ASR listener only triggers `internalStop()` + `internalStart()` if `state.isContinuous && state.isRecording`.

**Why:** `internalStart()` starts the ASR without requesting coordinator permission (assumes permission already granted). Triggering it when not recording would start recording without a coordinator grant.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| Brief interruption in continuous listening when model becomes available | Acceptable — only happens once at startup, duration is milliseconds |
| TTS generation uses bundled model if scan completes mid-generation | `_pendingReinit` ensures next generation uses the correct model |
| Listener fires multiple times if download state changes frequently | Condition `!prev.isDownloaded && next.isDownloaded` is edge-triggered, fires at most once per model |

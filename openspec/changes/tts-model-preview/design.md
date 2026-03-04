## Context

The app already has a fully isolate-based TTS pipeline (`TtsIsolateWorker`) that does RTF logging internally but discards the value. Each model card in the catalog browser shows download/delete controls but gives users no way to hear the model or judge its speed before committing to it as their active choice.

Key existing components reused by this change:
- `TtsIsolateWorker` — spawns an `Isolate`, sends `InitializeTtsMessage` / `GenerateAudioMessage`, returns raw WAV bytes. Can already be pointed at any downloaded model via `ResolvedTtsModel`.
- `_buildConfigFromResolvedPaths` — builds architecture-specific `OfflineTtsModelConfig` from resolved file paths.
- `just_audio` `AudioPlayer` — already a dependency; can play in-memory `BytesSource` without going through the queue.
- `Settings` / `SettingsProvider` — `Map`-based persistence already demonstrated by `engineUrlHistory`.

## Goals / Non-Goals

**Goals:**
- Let users tap "Preview" on any downloaded TTS model card to hear a short sample and see the measured RTF.
- Persist RTF benchmarks per model in settings so the gauge is available without re-running the preview.
- Display a color-coded speed gauge on model cards (green / amber / red).
- Gate streaming TTS on the benchmark: if the active model's RTF > 1.10 the pipeline uses full-buffer synthesis regardless of any streaming flag.

**Non-Goals:**
- Custom preview phrases or language-specific phrases — a single fixed English sentence is sufficient.
- Automatic background benchmarking — preview is always user-initiated.
- Benchmarking ASR models.
- Displaying the gauge on model cards that have no benchmark yet (gauge is absent, not shown as "unknown").

## Decisions

### D1 — Dedicated one-shot preview worker, not reusing the assistant's worker

The assistant's `TtsIsolateWorker` may be mid-generation when the user taps "Preview" for a different model. Reinitializing it would kill the active generation and confuse the audio queue.

Instead, `TtsPreviewService` spawns a brand-new `TtsIsolateWorker` for the preview model, uses it once, then disposes it. This keeps the assistant's TTS completely unaffected.

Alternative considered: a shared "secondary" worker. Rejected because it would need lifecycle management and could still conflict if the user previews two models in rapid succession.

### D2 — RTF returned to the caller as part of the preview result

The `_ttsWorkerIsolate` already computes RTF internally for debug logging. Rather than duplicating the math, a new `AudioGeneratedWithRtfResponse` sealed class variant (or a restructured return type) carries both the WAV bytes and the measured RTF back to `TtsPreviewService`.

Simpler alternative: compute RTF in the service by timing the `generateAudio()` call and measuring the returned WAV duration. This avoids protocol changes in `tts_isolate_worker.dart` but duplicates the duration math. Chosen approach: add `rtf` to `AudioGeneratedResponse` — one small addition to the existing sealed class, no duplication.

### D3 — `ttsModelBenchmarks: Map<String, double>` persisted as JSON in SharedPreferences

A single SharedPreferences key holds a JSON-encoded map of `{ modelId: rtf }`. This mirrors the pattern already used for `history` and `engineUrlHistory` in `Settings`. The field is additive — missing entries mean "no benchmark yet".

Alternative: a separate SharedPreferences key per model. Rejected because it produces unbounded keys and complicates migration.

### D4 — Streaming gate lives in `TtsNotifier._getService` / `reinitializeWithModel`

When `TtsNotifier` sets up (or reinitializes) its `TtsService`, it reads `settings.ttsModelBenchmarks[selectedTtsModelId]`. If the stored RTF > 1.10, it disables streaming for that session.

The `TtsService` does not currently implement streaming — that is a separate `streaming-tts-playback` change. This gate is therefore a no-op today but puts the decision point in the right place so the streaming change can read the flag without further architecture work.

### D5 — Preview plays through a throwaway `AudioPlayer`, not `PlaybackProvider`

The main `PlaybackProvider` manages a queue tied to chat messages. Injecting preview audio into it would confuse message playback state. A local `AudioPlayer` instance created in `TtsPreviewService.preview()`, played, then disposed keeps the preview fully self-contained.

### D6 — Preview button state managed locally in the model card widget

The card already has `_isDownloading` local state. A `_previewState` field (`idle | loading | playing | error`) follows the same pattern without requiring a new provider. The `TtsPreviewService` is instantiated inline (not as a Riverpod provider) because its lifecycle is a single tap — no shared state needed across widgets.

### D7 — RTF gauge as a small inline widget using `LinearProgressIndicator`

A narrow colored bar beneath the model name conveys speed intuitively. The three RTF thresholds map to `Colors.green`, `Colors.amber`, and `Colors.red`. No custom painter needed.

## Risks / Trade-offs

- [Risk] Preview isolate initialization time (1–5 s on slow devices) may feel slow relative to tapping "Preview". → Mitigation: show a loading indicator on the button while the isolate starts; play audio as soon as generation completes.
- [Risk] Running two TTS isolates simultaneously (preview + assistant active) can spike RAM. → Mitigation: `TtsPreviewService.dispose()` is called as soon as the audio is playing, freeing the model immediately. The worker isolate is killed on dispose.
- [Risk] RTF measured on first synthesis includes model load time and is therefore pessimistic. → Accepted trade-off: the benchmark is meant to represent "first use" latency, which includes cold-start cost. The gauge label will say "Speed" not "RTF" to avoid misleading precision.
- [Risk] The streaming gate decision point (D4) depends on `streaming-tts-playback` implementing a flag that `TtsService` respects. → Mitigation: document the flag contract in the streaming change's spec. This change only persists the benchmark and passes the flag; it does not implement streaming itself.

## Open Questions

- None — design is sufficient to begin implementation.

## Why

Users cannot hear how a downloaded TTS model sounds without first selecting it and triggering real speech from the assistant. There is also no way to know whether a model is fast enough for comfortable real-time use on the device. A quick in-place preview with a measured speed indicator lets users make informed model choices before committing.

## What Changes

- Add a "Preview" action to downloaded TTS model cards in the catalog browser. Tapping it synthesizes a short fixed phrase using that model and plays the result immediately.
- Measure the real-time factor (RTF) of the synthesis and persist the result per model.
- Display a compact color-coded RTF gauge on each model card that has a recorded benchmark:
  - **Green** — RTF ≤ 0.90 (fast, comfortable for real-time use)
  - **Amber** — 0.90 < RTF ≤ 1.10 (acceptable, slight delay noticeable)
  - **Red** — RTF > 1.10 (too slow, synthesis cannot keep up with speech rate)
- The preview uses a dedicated lightweight TTS instance separate from the main assistant TTS so it does not interrupt or reinitialize the assistant's active model.
- When the active TTS model has a recorded RTF > 1.10, streaming TTS playback SHALL be disabled for that model and the app SHALL fall back to full-buffer synthesis. Streaming requires the model to produce audio faster than it plays (RTF < 1.0); a model above the threshold would cause audio underruns and choppy playback.

## Capabilities

### New Capabilities

- `tts-model-preview`: On-demand synthesis preview and RTF benchmarking for downloaded TTS models, with persisted results shown as a color-coded speed gauge on model cards.

### Modified Capabilities

- `model-catalog`: TTS model cards gain a "Preview" action (visible when the model is downloaded) and a speed gauge derived from the stored benchmark.
- `user-settings`: Persist per-model RTF benchmark results across app restarts.
- `voice-integration-abstraction`: The TTS pipeline SHALL consult the benchmark result for the active model and disable streaming playback when RTF > 1.10, falling back to full-buffer mode regardless of any streaming setting.

## Impact

- **apps/lib/widgets/model_management_section.dart** — Preview button and RTF gauge on `_ModelEntryCard` for TTS models.
- **apps/lib/voice/tts_preview_service.dart** — New lightweight service that spawns a one-shot TTS isolate for the preview model, plays the result via `just_audio`, and returns the RTF.
- **apps/lib/providers/settings_provider.dart** / `lib/models/settings.dart` — New `ttsModelBenchmarks: Map<String, double>` field persisted to SharedPreferences.
- **apps/lib/providers/model_download_provider.dart** — No changes needed; preview reads the already-resolved model directory.
- No new pub dependencies required.

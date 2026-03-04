## 1. Settings — benchmark persistence

- [ ] 1.1 Add `ttsModelBenchmarks: Map<String, double>` field to `Settings` class with default empty map
- [ ] 1.2 Serialize `ttsModelBenchmarks` in `Settings.toJson` as a JSON-encoded string keyed `ttsModelBenchmarks`
- [ ] 1.3 Deserialize `ttsModelBenchmarks` in `Settings.fromJson`, defaulting to empty map when key absent
- [ ] 1.4 Add `updateTtsModelBenchmark(String modelId, double rtf)` method to `SettingsNotifier`
- [ ] 1.5 Update `Settings.copyWith` to accept `Map<String, double>? ttsModelBenchmarks`
- [ ] 1.6 Update `Settings.==` and `hashCode` to include `ttsModelBenchmarks`

## 2. RTF result from TTS isolate

- [ ] 2.1 Add `rtf` field to `AudioGeneratedResponse` in `tts_isolate_worker.dart`
- [ ] 2.2 Populate `rtf` in `_ttsWorkerIsolate` when sending `AudioGeneratedResponse` (use existing stopwatch math)
- [ ] 2.3 Return `rtf` from `TtsIsolateWorker.generateAudio` (extend return type or use a record/small class)

## 3. TtsPreviewService

- [ ] 3.1 Create `apps/lib/tts/tts_preview_service.dart` with class `TtsPreviewService`
- [ ] 3.2 Implement `preview(ResolvedTtsModel model)` → `Future<double>`: spawn a fresh `TtsIsolateWorker`, generate the fixed phrase, play via a throwaway `AudioPlayer` (`BytesSource`), dispose the worker, return RTF
- [ ] 3.3 Define the fixed preview phrase as a private constant (English sentence, ~10 words)
- [ ] 3.4 Dispose the `AudioPlayer` after playback completes (listen to `playerStateStream`)

## 4. Preview action on model cards

- [ ] 4.1 Add `_previewState` enum (`idle | loading | playing | error`) as local state in `_ModelEntryCard`
- [ ] 4.2 Add Preview `IconButton` to the TTS model card action row, visible only when the model is downloaded
- [ ] 4.3 On tap: resolve the model via `ModelResolver`, call `TtsPreviewService.preview`, update settings benchmark via `SettingsNotifier.updateTtsModelBenchmark`
- [ ] 4.4 Show `CircularProgressIndicator` on the button while `_previewState == loading`
- [ ] 4.5 Show error icon briefly on failure, then reset to idle

## 5. RTF speed gauge widget

- [ ] 5.1 Create `_RtfGauge` private widget in `model_management_section.dart`
- [ ] 5.2 Accept `double rtf` and render a narrow `LinearProgressIndicator`-style bar with color: green (≤ 0.90), amber (≤ 1.10), red (> 1.10)
- [ ] 5.3 Add a small "Speed" label beside the bar
- [ ] 5.4 Display `_RtfGauge` on TTS model cards when `settings.ttsModelBenchmarks[entry.id]` is non-null

## 6. Streaming gate in TTS pipeline

- [ ] 6.1 In `TtsNotifier._getService` / `_handleTtsModelChanged`, read `settings.ttsModelBenchmarks[selectedTtsModelId]`
- [ ] 6.2 Pass a `streamingDisabled` flag to `TtsService` when the benchmark RTF > 1.10 (or when null, do not disable)
- [ ] 6.3 Add `streamingDisabled` property to `TtsService` (no functional change yet — placeholder for `streaming-tts-playback` change to consume)

## 7. Analysis and tests

- [ ] 7.1 Run `dart-flutter_analyze_files` on `apps/`; fix all issues
- [ ] 7.2 Run `dart-flutter_run_tests` on `apps/`; confirm all tests pass

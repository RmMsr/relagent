## Context

Pocket TTS models perform voice cloning: synthesis quality and voice identity are shaped by a short reference audio clip loaded once at TTS worker initialization. The app currently hard-codes `resolvedPaths['referenceWav']` (pointing to `test_wavs/bria.wav`) with no user visibility or choice. A Pocket TTS model typically ships several reference voices in its `test_wavs/` directory (e.g., `bria.wav`, `loona.wav`), and users may also want to supply their own audio file.

The TTS pipeline already accepts an optional `referenceWavPath` through `TtsIsolateWorker.initialize()`. Adding user control requires:
1. Discovering available bundled voices from the downloaded model directory.
2. Managing a small user-owned library of custom audio samples.
3. Persisting the user's current choice and resetting it when it becomes invalid.
4. Passing it through the existing initialization chain and reinitializing the worker on change.

## User-Facing Mental Model

Voice customization lives in the **Voice section of the settings page** alongside the TTS model selector. When the active model supports voice cloning, a reference voice picker appears there. The model card in the catalog browser shows only a brief indication that the model's tone is customizable — no controls.

The user selects one reference voice at a time. There are two kinds, clearly labelled in the picker:

- **Model voices** — audio samples bundled with the current Pocket TTS model (from `test_wavs/`). Specific to that model.
- **My voices** — audio files the user has imported. Stored in app-managed storage; survive model switches.

**What happens when the user switches TTS models:**
The saved reference is validated against the new model. If it is no longer valid (a model voice that does not exist in the new model), it is reset to `null` and the new model's first bundled reference is used as the default. If it was a user-imported voice the file still exists and continues to be used unchanged.

This is intentional and unsurprising: model voices belong to a model; personal voices follow the user.

## Goals / Non-Goals

**Goals:**
- Show voice reference controls in the Voice section of the settings page, visible only when a voice-cloning TTS model is active.
- Let users choose from bundled reference voices in the active Pocket TTS model.
- Let users build a small personal voice library by importing audio files; allow multiple custom samples, each deletable.
- Persist the user's choice as a single `ttsReferenceVoicePath` setting. Reset to `null` (model default) when the active TTS model changes and the saved path is no longer valid.
- Show a non-interactive "tone is customizable" hint on Pocket TTS model cards in the catalog browser.
- Reinitialize the TTS worker whenever the active reference changes.

**Non-Goals:**
- Per-model reference voice persistence.
- Reference voice controls on model cards.
- In-app voice recording.
- Audio format conversion or resampling (sherpa-onnx handles this internally).
- Validating that the chosen file is a well-formed audio file before import (runtime error surfacing is sufficient).

## Decisions

### D1: Discover bundled voices at runtime by scanning the model directory

**Decision**: Scan `<modelDir>/test_wavs/*.wav` when the settings page renders the reference picker; do not enumerate files in `voice-models.json`.

**Rationale**: The model is already on device. Scanning the directory always reflects reality and requires no catalog maintenance as upstream models add or rename voices.

**Alternative considered**: Enumerate all `test_wavs` keys in `fileStructure`. Rejected: brittle, verbose, redundant.

---

### D2: Custom samples copied to app documents storage, tracked as a list in settings

**Decision**: When the user imports a file, copy it into `<appDocumentsDir>/voice_samples/`. The list of imported file paths is persisted in `Settings` as `ttsCustomVoiceSamples: List<String>`. The active reference is a separate `ttsReferenceVoicePath: String?`.

**Rationale**: Copying to app storage gives stable, permission-free access. Android SAF URIs from the file picker are short-lived; the original may be on removable storage. Copying is a one-time cost for a file that is typically < 1 MB.

---

### D3: Single shared `ttsReferenceVoicePath` (nullable String)

**Decision**: `ttsReferenceVoicePath` holds the absolute path of the active reference, or `null` meaning "use the model's first bundled default". This is the only field used by the TTS initialization chain.

**Rationale**: Null-means-default keeps the pipeline simple. No type tag is needed; the path location encodes kind (model directory vs app documents).

---

### D4: Reset reference when model changes and path is no longer valid

**Decision**: When `selectedTtsModelId` changes, the settings notifier checks whether `ttsReferenceVoicePath` is still valid for the new model:
- `null` → stays `null` (model default, always valid).
- Path under `voice_samples/` (user import) → file exists → keep unchanged.
- Any other path (model bundled voice) → reset to `null`.

This gives predictable behaviour: switching models resets bundled voice choices to the new model's default, while personal imports are preserved.

**Alternative considered**: Keep the stale path and fall back silently in the worker. Rejected: the settings page would display a voice name that does not belong to the current model, confusing the user.

---

### D5: UI — reference picker in the settings page Voice section

**Decision**: In the Voice section of the settings page, below the TTS model selector, show a "Reference voice" row only when the active TTS model is a voice-cloning model (`architecture == ModelArchitecture.pocket`). Tapping the row opens a bottom sheet with two labelled sections:

- **Model voices** — voices from `test_wavs/` of the current model, labelled by filename stem (e.g., "Bria", "Loona").
- **My voices** — user-imported samples from `ttsCustomVoiceSamples`, labelled by filename, each with a delete affordance. An "Add voice…" item at the bottom opens the native file picker.

The active reference has a check mark. Tapping selects it, updates `ttsReferenceVoicePath`, and closes the sheet.

On the model card in the catalog browser, Pocket TTS models show a small non-interactive label ("Voice cloning") so users know the model is customizable, but no controls appear there.

---

### D6: Reinitialize TTS worker on reference change via existing `_handleTtsModelChanged` pattern

**Decision**: In `TtsNotifier.build()`, extend the `ref.listen` on `settingsProvider` to also trigger `_handleTtsModelChanged()` when `ttsReferenceVoicePath` changes. Re-uses the already-tested reinitialize-with-model path.

---

### D7: `file_picker` for native file open dialog

**Decision**: Add the `file_picker` pub package. No extension filter enforced in the dialog.

**Rationale**: Standard cross-platform Flutter package. Supports Android, iOS, Linux. Sherpa-onnx uses libsndfile and accepts more formats than just WAV.

## Risks / Trade-offs

- **Reinitialization latency**: Changing reference restarts the TTS worker (~1–3 s, same as a model switch). Acceptable for an explicit user action.
- **Invalid audio file**: If the file cannot be decoded by `sherpa_onnx.readWave()`, the isolate sends an `ErrorResponse` on next synthesis. User sees a TTS error and can fix it by picking a different file.
- **No `test_wavs` directory**: If a future model ships without sample voices, the "Model voices" section is empty. User can still import custom files; no crash.
- **Storage growth**: User files accumulate in app storage. Deletion from "My voices" removes the underlying file.

## Migration Plan

No data migration needed. `ttsReferenceVoicePath` and `ttsCustomVoiceSamples` default to `null` / empty list, preserving current behaviour. Existing users see no change until they open the Voice settings section.

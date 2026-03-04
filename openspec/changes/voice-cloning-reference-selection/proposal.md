## Why

Users want to personalise the assistant's speech to their own taste. The most direct way to express that preference is by providing a concrete voice example — a short audio clip that the assistant then imitates. Pocket TTS models already support this through voice cloning, but the app always silently uses the first bundled reference file with no way for the user to choose. Surfacing that choice turns an invisible implementation detail into a meaningful personalisation feature.

## What Changes

- Add a voice reference picker UI accessible from the TTS model card (model management screen).
- List all bundled reference voices from the active Pocket TTS model's `test_wavs/` directory with playable previews.
- Allow the user to pick a local audio file via the native file-open dialog as a custom reference.
- Persist a **single shared** reference voice path in user settings (not per-model); the setting applies to whichever voice-cloning TTS model is active.
- Hide the reference picker entirely when the active TTS model does not support voice cloning.
- Wire the persisted path through to `TtsIsolateWorker` so the chosen voice is used for synthesis.

## Capabilities

### New Capabilities

- `voice-cloning-reference`: UI and logic for selecting, persisting, and applying a voice reference audio file for Pocket TTS voice cloning models.

### Modified Capabilities

- `user-settings`: Add a single shared `ttsReferenceVoicePath` setting (nullable string, no breaking changes to existing fields); hidden in the UI when the active TTS model does not support voice cloning.
- `model-catalog`: `fileStructure` for Pocket TTS models SHALL enumerate all bundled `test_wavs/*.wav` files individually so the app can list them as selectable voices.

## Impact

- **apps/lib/widgets/model_management_section.dart** – new reference picker entry point on Pocket TTS cards.
- **apps/lib/providers/settings_provider.dart** / `lib/models/settings.dart` – new shared `ttsReferenceVoicePath` (nullable String) persisted to SharedPreferences.
- **apps/lib/providers/tts_provider.dart** – pass selected reference path to `TtsIsolateWorker`.
- **apps/lib/tts/tts_isolate_worker.dart** – already accepts `referenceWavPath`; no structural changes needed.
- **apps/assets/voice-models.json** – Pocket TTS entries may need all `test_wavs/*.wav` files listed in `fileStructure`.
- **New dependency**: `file_picker` package for native file-open dialog (cross-platform: Android, iOS, Linux).

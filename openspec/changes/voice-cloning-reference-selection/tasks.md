## 1. Dependencies

- [ ] 1.1 Add `file_picker` to `apps/pubspec.yaml` and run `pub get`

## 2. Settings Data Model

- [ ] 2.1 Add `ttsReferenceVoicePath: String?` field to `Settings` in `apps/lib/models/settings.dart` (default `null`), with `copyWith`, `toJson`, `fromJson`, and equality support
- [ ] 2.2 Add `ttsCustomVoiceSamples: List<String>` field to `Settings` (default `const []`), with `copyWith`, `toJson`, `fromJson`, and equality support

## 3. Settings Notifier

- [ ] 3.1 Add `updateTtsReferenceVoicePath(String? path)` method to `SettingsNotifier` in `apps/lib/providers/settings_provider.dart`
- [ ] 3.2 Add `addCustomVoiceSample(String path)` method that appends the path to `ttsCustomVoiceSamples`
- [ ] 3.3 Add `removeCustomVoiceSample(String path)` method that removes the path from `ttsCustomVoiceSamples`, deletes the underlying file from app storage, and if the path was the active reference, resets `ttsReferenceVoicePath` to `null`
- [ ] 3.4 In `updateSelectedTtsModelId`, after updating the model id, validate `ttsReferenceVoicePath`: if it is non-null and does NOT start with the `voice_samples` app documents path, reset it to `null` (bundled model voice no longer valid)

## 4. Custom Voice File Storage

- [ ] 4.1 Create `apps/lib/voice/voice_sample_storage.dart` with a `copyToVoiceSamples(String sourcePath) → Future<String>` function that copies the file to `<appDocumentsDir>/voice_samples/<filename>` and returns the destination path; create the directory if it does not exist
- [ ] 4.2 Add a `voiceSamplesDir() → Future<String>` helper used by both `copyToVoiceSamples` and the model-change validation in task 3.4

## 5. TTS Pipeline — Pass User Reference Through

- [ ] 5.1 Add `referenceVoicePath: String?` mutable property to `TtsService` in `apps/lib/tts/services.dart`
- [ ] 5.2 Update `TtsService.initialize()` and `reinitializeWithModel()` to forward `referenceVoicePath` to `VoiceService.initializeTts` (or directly to `TtsIsolateWorker`) alongside `resolvedTtsModel`
- [ ] 5.3 Update `TtsIsolateWorker.initialize()` to accept an explicit `referenceVoicePath` parameter that overrides the model default (`resolvedPaths['referenceWav']`), applying the fallback: explicit path (if file exists) → model default
- [ ] 5.4 In `TtsNotifier._getService()`, set `service.referenceVoicePath = settings.ttsReferenceVoicePath` after constructing the service
- [ ] 5.5 In `TtsNotifier.build()`, extend the existing `ref.listen<Settings>` to trigger `_handleTtsModelChanged()` also when `ttsReferenceVoicePath` changes (in addition to `selectedTtsModelId`)
- [ ] 5.6 In `TtsNotifier._handleTtsModelChanged()`, update `_service!.referenceVoicePath` from current settings before calling `reinitializeWithModel`

## 6. Model Catalog — Voice Cloning Indicator

- [ ] 6.1 In `_ModelEntryCard` in `apps/lib/widgets/model_management_section.dart`, add a non-interactive "Voice cloning" chip or label on TTS cards where `entry.architecture == ModelArchitecture.pocket`; show it regardless of download status

## 7. Settings Page — Reference Voice UI

- [ ] 7.1 In `apps/lib/pages/settings_page.dart`, add a "Reference voice" `ListTile` in the Voice section, visible only when the active TTS model is `ModelArchitecture.pocket`; the subtitle shows the effective voice name (filename stem of `ttsReferenceVoicePath` if set, otherwise the stem of `resolvedPaths['referenceWav']`)
- [ ] 7.2 Create `apps/lib/widgets/voice_reference_picker.dart` — a bottom sheet widget that shows two sections: "Model voices" (scanned from `test_wavs/` of the resolved model directory) and "My voices" (from `ttsCustomVoiceSamples`); active voice has a check mark; "Add voice…" list tile at the bottom of "My voices"; each custom voice has a delete icon button
- [ ] 7.3 Wire "Model voices" section: on tap, call `settingsNotifier.updateTtsReferenceVoicePath(absolutePath)` and close the sheet
- [ ] 7.4 Wire "My voices" section: on tap, call `updateTtsReferenceVoicePath`; on delete, call `removeCustomVoiceSample`
- [ ] 7.5 Wire "Add voice…": call `FilePicker.platform.pickFiles()`, on result copy via `copyToVoiceSamples`, call `addCustomVoiceSample` with the destination path, then `updateTtsReferenceVoicePath` with the same path
- [ ] 7.6 Wire the "Reference voice" tile in settings to open the picker bottom sheet

## 8. Analysis & Tests

- [ ] 8.1 Run `dart-flutter_analyze_files` and fix all analysis warnings in modified files
- [ ] 8.2 Run `dart-flutter_dart_format` on all modified files

## 1. Architecture taxonomy

- [x] 1.1 Add `whisper` to `ModelArchitecture` in `dart_packages/sherpa_voice/lib/model_architecture.dart`, with a doc comment describing the file layout (`{name}-encoder.onnx` + `{name}-decoder.onnx` + `{name}-tokens.txt`, no joiner).

## 2. Detection

- [x] 2.1 In `apps/lib/voice/model_architecture_detector.dart`, add whisper detection: exactly one `*encoder*.onnx`, exactly one `*decoder*.onnx` sharing a common filename prefix, no joiner file, and a `<prefix>tokens.txt` entry.
- [x] 2.2 Verify the new branch is ordered so it can't misfire on existing transducer/CTC/NeMo shapes (it shouldn't, per design.md's narrower-rule rationale, but confirm with a test using a real transducer archive's file list before relying on it).
- [x] 2.3 Add test cases to `apps/test/voice/model_architecture_detector_test.dart`: whisper detected from prefixed filenames; whisper NOT detected when a joiner is present; existing transducer/CTC fixtures still detect correctly (regression).

## 2b. Imported-model file-structure resolution

- [x] 2b.1 In `apps/lib/voice/model_resolver.dart`'s `_buildImportedAsrFileStructure()`, fix the tokens check (`name == 'tokens.txt'`) to also accept the `<prefix>tokens.txt` form, matching the detector's whisper rule — encoder/decoder resolution already works via `.contains(...)`, this is the only exact-match holdout.
- [x] 2b.2 Add a regression test: an imported archive with `nb-whisper-base-tokens.txt` resolves `fileStructure['tokens']` to that file, not empty.

## 3. Offline ASR recognizer construction

- [x] 3.1 In `apps/lib/speech_recognition/sherpa_vad_asr.dart`, generalize `_buildOfflineRecognizer()` from its current hardcoded `nemo_transducer` config into a `switch (architecture)` with `offlineNemoTransducer` (existing behavior, unchanged) and `whisper` (new) cases.
- [x] 3.2 Whisper case: build `OfflineModelConfig.whisper` from `encoder`/`decoder`/`tokens` file-structure entries, `task: 'transcribe'`, and `language` sourced from the model's catalog metadata.
- [x] 3.3 Thread a forced-language value from `CatalogEntry` (default: `languages.first`, per design.md) down to wherever `_buildOfflineRecognizer()` is invoked, so it doesn't have to reach back into the catalog itself.
- [x] 3.4 Throw a clear, actionable error (not a native crash) if a whisper model's `languages` list is empty at recognizer-construction time — never silently pass an empty `language` string, which would enable auto-detect.
- [x] 3.5 Confirm `dispose()` / recognizer teardown already handles the whisper case correctly (it should, since it operates on the same `OfflineRecognizer` type) — no code change expected, just verify.

## 4. Streaming classification

- [x] 4.1 In `apps/lib/models/model_catalog.dart`, confirm `whisper` falls through to `supportsStreaming = false` in the existing derivation (it does by default, since the check is an explicit allow-list) — add a regression test asserting this rather than relying on it being implicit.

## 5. Catalog entry

- [x] 5.1 Decide and document (in the entry's `notes` field or PR description) which converted whisper model ships first — likely `nb-whisper-base`, per the validated conversion in `experiments/nb-whisper-onnx/`. Decided: `nb-whisper-base`.
- [x] 5.2 ~~Add the catalog entry to `apps/assets/voice-models.json`~~ — **deferred, by user decision**. The converted `nb-whisper-base` artifact only exists locally (`experiments/nb-whisper-onnx/out/`); there is no public download URL to give `CatalogEntry.downloadUrl` (a required, non-empty, `https://`-prefixed field per `model_catalog_test.dart`), unlike every other catalog entry which points at a real hosted release asset. Whisper remains import-only for now — reachable via the local-model-import flow (already fully working after tasks 1-4) using `experiments/nb-whisper-onnx/package_archive.sh`'s output. Revisit once the converted model has a real public host (e.g. a GitHub release).
- [x] 5.3 Confirm `tools/voice_catalog/lib/supported_architectures.dart` picks up `whisper` automatically (it derives from `ModelArchitecture.values`, no code change expected) — verify with `--list-architectures`. Verified: `./bin/voice-catalog.sh --list-architectures` now shows `asr | yes | whisper | 0 | 18` (runtime-supported flipped to "yes", zero change needed).

## 5b. Fixes found during manual verification

Three more `ModelArchitecture`-consuming spots existed beyond what proposal.md's Impact section anticipated. The three exhaustive `switch` statements in `import_model_sheet.dart` were caught immediately by `flutter analyze` (non-exhaustive-switch compile error) during task 12's verification pass. These three were *not* caught by the compiler — each is a `Set`/`==` check, which stays syntactically valid with a case silently missing — and only surfaced when manually testing the import flow:

- [x] 5b.1 `apps/lib/widgets/import_model_sheet.dart`'s `_asrArchitectures` — a hardcoded `Set<ModelArchitecture>` independent of the enum, used to build the architecture dropdown's `items:` list. Missing `whisper` meant it was entirely absent from the dropdown (not just unselected) — this was the actual bug behind "whisper is not available in the voice model import screen". Fixed: added to the set.
- [x] 5b.2 `apps/lib/voice/voice_service_native.dart`'s `isOffline` check — gates whether `VadAsr` (task 3's offline builder) or the streaming `asr.ASR` class gets constructed for a selected model. Checked only `== ModelArchitecture.offlineNemoTransducer`, so a whisper model — even if manually forced past the (now-fixed) dropdown gap — would have been routed to the *streaming* backend, which would throw `ArgumentError: Unsupported ASR architecture for online recognition` from `sherpa_voice`'s `buildAsrRecognizer`. This was the more serious of the two: not a UI omission, a full pipeline break. Fixed: added `|| == ModelArchitecture.whisper`.
- [x] 5b.3 `apps/lib/widgets/model_management_section.dart`'s `_modeLabel()` — cosmetic "mode: chunked" badge on model cards, checked only `offlineNemoTransducer`. Whisper would have shown no mode label at all rather than being correctly labeled chunked. Fixed: added whisper to the same branch.

## 6. Manual verification

- [x] 6.1 Import the converted whisper model via the local-model-import flow on a real device/emulator and confirm architecture auto-detects as `whisper`.
- [x] 6.2 Run a live transcription session end-to-end (VAD-chunked) against real Norwegian speech and confirm output quality is consistent with the offline validation already done (NPSC/FLEURS samples).
- [x] 6.3 Confirm the model does NOT appear anywhere in the UI as offering live/streaming indicators.

## 1. Seed voice-models.json

- [x] 1.1 Create `apps/assets/voice-models.json` with all existing `ModelCatalog` entries, each with `status: "approved"`, `recommended: true`, and correct `fileStructure` map
- [x] 1.2 Add `voice-models.json` to the Flutter assets list in `apps/pubspec.yaml`
- [x] 1.3 Verify the JSON is valid and pretty-printed (2-space indent)

## 2. Refactor ModelCatalog to read from JSON

- [x] 2.1 Add `recommended` field to `CatalogEntry` (bool, defaults to false)
- [x] 2.2 Add `CatalogEntry.fromJson(Map<String, dynamic>)` factory — throws `FormatException` on missing required fields or unknown enum values
- [x] 2.3 Add `ModelCatalog.init()` static async method that loads and parses `voice-models.json`, filters to `status == "approved"`, and caches the result
- [x] 2.4 Change `ModelCatalog.entries` from `const List` to a mutable static list populated by `init()`
- [x] 2.5 Update `byType`, `byLanguage`, `byTypeAndLanguage` to sort `recommended` entries first
- [x] 2.6 Call `await ModelCatalog.init()` in `apps/lib/main.dart` before `runApp`
- [x] 2.7 Update `apps/test/models/model_catalog_test.dart` to load entries from a test-fixture JSON rather than compile-time constants; verify all existing assertions still pass

## 3. voice-catalog tool — entry point and structure

- [x] 3.1 Create `apps/lib/voice_catalog/` directory with `voice_catalog_main.dart` entry point: calls `WidgetsFlutterBinding.ensureInitialized()`, runs the three phases, prints summary, calls `exit(0)`
- [x] 3.2 Add reference fixture WAVs to `apps/lib/voice_catalog/fixtures/` — at minimum `en.wav` (mono 16 kHz, 2–5 seconds); add per-language clips for de, fr, es, ru as available
- [x] 3.3 Verify the tool builds and launches on Linux: redesigned as pure Dart CLI (`tools/voice_catalog/`); run via `bin/voice-catalog` shell script; `--help`, discover, and filter phases confirmed working

## 4. voice-catalog tool — discovery phase

- [x] 4.1 Implement `VoiceCatalogDiscovery` class that fetches `https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/asr-models` and `…/tts-models` using the `http` package
- [x] 4.2 Implement filename parser that extracts `type`, `architecture`, `languages`, `downloadSizeMb`, and `downloadUrl` from each asset filename; returns a parse-failure note when the filename does not match a known pattern
- [x] 4.3 Merge newly discovered entries into the existing `voice-models.json`: add as `untested` / `recommended: false` / `notes: ""`, leave existing entries unchanged
- [x] 4.4 Handle GitHub API unreachable: print warning, skip discovery, proceed with existing JSON

## 5. voice-catalog tool — filter phase

- [x] 5.1 Implement `VoiceCatalogFilter` that applies all hard criteria to `untested` entries and marks excluded ones with a `notes` reason string
- [x] 5.2 Filter: license not in `{Apache-2.0, MIT}` → `"excluded: license <value>"`
- [x] 5.3 Filter: `downloadSizeMb > 1000` → `"excluded: size <value>MB exceeds 1GB limit"`
- [x] 5.4 Filter: no overlap with supported languages (en, de, fr, es, it, nl, pl, ru, sv, pt, cs) → `"excluded: no supported language"`
- [x] 5.5 Filter: Piper model with `_low` or `x_low` in filename → `"excluded: quality below medium"`
- [x] 5.6 Filter: architecture cannot be mapped to `ModelArchitecture` → `"excluded: unsupported architecture"`

## 6. voice-catalog tool — evaluate phase

- [x] 6.1 Implement `VoiceCatalogEvaluator` that iterates `untested` entries passing the filter and runs download + inference for each
- [x] 6.2 Download each model via `ModelDownloadService`; skip if already present in cache
- [x] 6.3 After extraction, inspect the archive directory and populate `fileStructure` in the JSON entry
- [x] 6.4 For ASR entries: initialize via `createOnlineRecognizerFromMetadata` (streaming) or `createOfflineRecognizerFromMetadata` (offline); run inference on the language fixture WAV; verify output string is non-empty; record latency in `notes`
- [x] 6.5 For TTS entries: initialize via `createOfflineTtsFromMetadata`; synthesize a short sentence; verify output buffer is non-empty; record latency in `notes`
- [x] 6.6 On exception: update `notes` with the exception message; leave `status` as `"untested"`; continue to next entry
- [x] 6.7 Write `voice-models.json` to disk after each entry completes (crash resilience)

## 8. Extract packages/sherpa_voice/

- [x] 8.1 Create `packages/sherpa_voice/` with `pubspec.yaml` — depends only on `sherpa_onnx`, `archive`, `path`; no Flutter
- [x] 8.2 Move `ModelArchitecture` and `ModelType` enums to `packages/sherpa_voice/lib/model_architecture.dart`
- [x] 8.3 Move `ModelLoader` abstract interface to `packages/sherpa_voice/lib/model_loader.dart`
- [x] 8.4 Add `packages/sherpa_voice/lib/asr_config.dart` — `buildAsrConfig(ModelArchitecture, Map<String, String>, ModelLoader)` → `OnlineRecognizer`, extracted from `sherpa_streaming_asr.dart`
- [x] 8.5 Add `packages/sherpa_voice/lib/tts_config.dart` — `buildTtsConfig(ModelArchitecture, Map<String, String>, ModelLoader)` → `OfflineTts`, extracted from `sherpa_tts.dart`
- [x] 8.6 Add `packages/sherpa_voice/lib/model_archive.dart` — extract `.tar.bz2` with prefix-stripping and `.complete` marker, shared between app and tool
- [x] 8.7 Add `path: ../../packages/sherpa_voice` dependency to `apps/pubspec.yaml` and `tools/voice_catalog/pubspec.yaml`
- [x] 8.8 Update `apps/lib/models/model_catalog.dart` to import `ModelArchitecture`/`ModelType` from `package:sherpa_voice/model_architecture.dart`
- [x] 8.9 Update `apps/lib/voice/model_loader.dart` to re-export or replace with `package:sherpa_voice/model_loader.dart`
- [x] 8.10 Simplify `apps/lib/speech_recognition/sherpa_streaming_asr.dart` to call `buildAsrConfig` from `sherpa_voice`
- [x] 8.11 Simplify `apps/lib/tts/sherpa_tts.dart` to call `buildTtsConfig` from `sherpa_voice`
- [x] 8.12 Update `apps/lib/voice/model_download_service.dart` to delegate archive extraction to `model_archive.dart`
- [x] 8.13 Replace hand-rolled sherpa-onnx config logic in `tools/voice_catalog/lib/evaluator.dart` with calls to `buildAsrConfig` / `buildTtsConfig` from `sherpa_voice`
- [x] 8.14 Replace hand-rolled extraction in `tools/voice_catalog/lib/download_service.dart` with `model_archive.dart`
- [x] 8.15 Run `dart-flutter_analyze_files` on `apps/` and analysis on `tools/voice_catalog/`; fix all issues
- [x] 8.16 Run `dart-flutter_run_tests` on `apps/`; confirm all tests pass

## 7. Verify end-to-end

- [x] 7.1 Run `voice-catalog` tool on Linux; confirm it discovers, filters, and evaluates at least one untested model and writes an updated `voice-models.json`
- [x] 7.2 Manually promote one evaluated entry to `approved` in `voice-models.json`; run the app and confirm the new model appears in the model selection UI
- [x] 7.3 Run `dart-flutter_analyze_files` on `apps/`; fix any analysis warnings
- [x] 7.4 Run `dart-flutter_run_tests` on `apps/`; confirm all tests pass including updated `model_catalog_test.dart`

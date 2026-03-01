## 1. Seed voice-models.json

- [ ] 1.1 Create `apps/assets/voice-models.json` with all existing `ModelCatalog` entries, each with `status: "approved"`, `recommended: true`, and correct `fileStructure` map
- [ ] 1.2 Add `voice-models.json` to the Flutter assets list in `apps/pubspec.yaml`
- [ ] 1.3 Verify the JSON is valid and pretty-printed (2-space indent)

## 2. Refactor ModelCatalog to read from JSON

- [ ] 2.1 Add `recommended` field to `CatalogEntry` (bool, defaults to false)
- [ ] 2.2 Add `CatalogEntry.fromJson(Map<String, dynamic>)` factory — throws `FormatException` on missing required fields or unknown enum values
- [ ] 2.3 Add `ModelCatalog.init()` static async method that loads and parses `voice-models.json`, filters to `status == "approved"`, and caches the result
- [ ] 2.4 Change `ModelCatalog.entries` from `const List` to a mutable static list populated by `init()`
- [ ] 2.5 Update `byType`, `byLanguage`, `byTypeAndLanguage` to sort `recommended` entries first
- [ ] 2.6 Call `await ModelCatalog.init()` in `apps/lib/main.dart` before `runApp`
- [ ] 2.7 Update `apps/test/models/model_catalog_test.dart` to load entries from a test-fixture JSON rather than compile-time constants; verify all existing assertions still pass

## 3. voice-catalog tool — entry point and structure

- [ ] 3.1 Create `apps/lib/voice_catalog/` directory with `voice_catalog_main.dart` entry point: calls `WidgetsFlutterBinding.ensureInitialized()`, runs the three phases, prints summary, calls `exit(0)`
- [ ] 3.2 Add reference fixture WAVs to `apps/lib/voice_catalog/fixtures/` — at minimum `en.wav` (mono 16 kHz, 2–5 seconds); add per-language clips for de, fr, es, ru as available
- [ ] 3.3 Verify the tool builds and launches on Linux: `fvm flutter run -d linux -t lib/voice_catalog/voice_catalog_main.dart`

## 4. voice-catalog tool — discovery phase

- [ ] 4.1 Implement `VoiceCatalogDiscovery` class that fetches `https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/asr-models` and `…/tts-models` using the `http` package
- [ ] 4.2 Implement filename parser that extracts `type`, `architecture`, `languages`, `downloadSizeMb`, and `downloadUrl` from each asset filename; returns a parse-failure note when the filename does not match a known pattern
- [ ] 4.3 Merge newly discovered entries into the existing `voice-models.json`: add as `untested` / `recommended: false` / `notes: ""`, leave existing entries unchanged
- [ ] 4.4 Handle GitHub API unreachable: print warning, skip discovery, proceed with existing JSON

## 5. voice-catalog tool — filter phase

- [ ] 5.1 Implement `VoiceCatalogFilter` that applies all hard criteria to `untested` entries and marks excluded ones with a `notes` reason string
- [ ] 5.2 Filter: license not in `{Apache-2.0, MIT}` → `"excluded: license <value>"`
- [ ] 5.3 Filter: `downloadSizeMb > 1000` → `"excluded: size <value>MB exceeds 1GB limit"`
- [ ] 5.4 Filter: no overlap with supported languages (en, de, fr, es, it, nl, pl, ru, sv, pt, cs) → `"excluded: no supported language"`
- [ ] 5.5 Filter: Piper model with `_low` or `x_low` in filename → `"excluded: quality below medium"`
- [ ] 5.6 Filter: architecture cannot be mapped to `ModelArchitecture` → `"excluded: unsupported architecture"`

## 6. voice-catalog tool — evaluate phase

- [ ] 6.1 Implement `VoiceCatalogEvaluator` that iterates `untested` entries passing the filter and runs download + inference for each
- [ ] 6.2 Download each model via `ModelDownloadService`; skip if already present in cache
- [ ] 6.3 After extraction, inspect the archive directory and populate `fileStructure` in the JSON entry
- [ ] 6.4 For ASR entries: initialize via `createOnlineRecognizerFromMetadata` (streaming) or `createOfflineRecognizerFromMetadata` (offline); run inference on the language fixture WAV; verify output string is non-empty; record latency in `notes`
- [ ] 6.5 For TTS entries: initialize via `createOfflineTtsFromMetadata`; synthesize a short sentence; verify output buffer is non-empty; record latency in `notes`
- [ ] 6.6 On exception: update `notes` with the exception message; leave `status` as `"untested"`; continue to next entry
- [ ] 6.7 Write `voice-models.json` to disk after each entry completes (crash resilience)

## 7. Verify end-to-end

- [ ] 7.1 Run `voice-catalog` tool on Linux; confirm it discovers, filters, and evaluates at least one untested model and writes an updated `voice-models.json`
- [ ] 7.2 Manually promote one evaluated entry to `approved` in `voice-models.json`; run the app and confirm the new model appears in the model selection UI
- [ ] 7.3 Run `dart-flutter_analyze_files` on `apps/`; fix any analysis warnings
- [ ] 7.4 Run `dart-flutter_run_tests` on `apps/`; confirm all tests pass including updated `model_catalog_test.dart`

## Context

The app currently maintains its model catalog as a hardcoded `const List<CatalogEntry>` in `model_catalog.dart`. Adding a new model requires editing Dart source and shipping a new release. There is no tooling to discover or verify models from the sherpa-onnx ecosystem systematically.

This design introduces two things: a JSON file (`voice-models.json`) as the single source of truth for both the developer evaluation workflow and the app's runtime catalog, and a Flutter Linux CLI tool (`voice-catalog`) that manages that file.

Existing code reused without modification: `ModelDownloadService`, `DownloadModelLoader`, `createOnlineRecognizerFromMetadata`, `createOfflineTtsFromMetadata`, `ModelArchitecture`, `ModelType`.

## Goals / Non-Goals

**Goals:**
- Auto-discover new sherpa-onnx models from the GitHub releases API
- Filter candidates by hard project criteria without downloading
- Smoke-test candidates using identical code paths to the app
- Produce a `voice-models.json` that serves as both the evaluation log and the app's runtime catalog
- Migrate `ModelCatalog` to read from JSON without changing its public API

**Non-Goals:**
- Automated promotion to `approved` — a human always reviews before shipping
- Subjective quality scoring (MOS, WER benchmarks) — pass/fail only
- Running in CI — this is a developer tool for manual runs when models are updated
- Supporting platforms other than Linux for the evaluation tool

## Decisions

### D1: Flutter Linux app, not a Dart CLI or integration test

The tool needs `sherpa_onnx` (FFI to native libs) and `path_provider` (cache directory). Both are Flutter plugins that require the Flutter engine.

- **Integration test** (`flutter test -d linux`): designed for fast widget tests, not multi-hundred-MB downloads that take minutes. Plugin initialization is also less predictable in test mode.
- **Pure Dart CLI** (`dart run`): Flutter plugins are not available; `sherpa_onnx` would need manual FFI setup.
- **Flutter Linux app** (chosen): full plugin environment, same native binary loading as the app, exits cleanly via `dart:io exit()`.

The tool uses `WidgetsFlutterBinding.ensureInitialized()`, runs all logic, then calls `exit(0)`. No `runApp()` or widget tree is needed — the binding alone initialises the plugin channel.

### D2: Same project, separate entry point

The tool lives at `apps/lib/voice_catalog/voice_catalog_main.dart` inside the existing `apps/` Flutter project rather than in a separate project with a path dependency.

- **Separate project**: requires maintaining a second `pubspec.yaml`, path-dependent on `apps/`, adds indirection.
- **Same project** (chosen): zero extra setup, immediate access to all `apps/lib/` code, shares the same `sherpa_onnx` version automatically.

The entry point is only activated via `-t lib/voice_catalog/voice_catalog_main.dart` and is never referenced by the regular `lib/main.dart`, so it does not affect the production build.

### D3: One JSON file, two roles

`apps/assets/voice-models.json` serves as both the developer evaluation registry and the app's runtime catalog. The app filters to `status == "approved"` entries; the tool writes all statuses including `"untested"` and `"fail"`.

- **Two files** (rejected): a `candidates.yaml` for developers and a `voice-models.json` for the app would require keeping them in sync and introduce a second format.
- **One file** (chosen): git diff shows the full evaluation history, a single commit updates both tool state and app catalog, and the file stays small enough (~40–60 KB pretty-printed) that bundling all entries as a Flutter asset is negligible.

### D4: Filename-based metadata inference

The GitHub releases API returns asset filenames that encode architecture and language, e.g.:
```
sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06.tar.bz2  → transducer, en, streaming
sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2           → offlineNemoTransducer, 25 langs
vits-piper-en_US-lessac-medium-int8.tar.bz2                   → vitsPiper, en, medium quality
kokoro-int8-en-v0_19.tar.bz2                                  → kokoro, en
sherpa-onnx-whisper-tiny.en.tar.bz2                           → whisper (unsupported arch → excluded)
```

Parsing is pattern-based and will fail on unusual filenames. When a filename cannot be fully parsed, the entry is added with `status: "untested"` and `notes: "parse: <reason>"` so a developer can fill in the metadata manually. This is acceptable because the discovery phase is additive only — it never overwrites existing entries.

The `fileStructure` map (model file paths inside the archive) cannot be inferred from the filename alone and must be populated by the developer after a successful evaluation, or left empty for `untested` entries. The evaluate phase populates `notes` with the inferred paths once download succeeds.

### D5: ModelCatalog initialised eagerly at app startup

`ModelCatalog` changes from a class with `const` fields to one that loads `voice-models.json` asynchronously. The catalog is initialised once in `main.dart` before `runApp`, stored in a static field, and all existing query methods (`byType`, `byLanguage`, `findById`, etc.) continue to work synchronously against the cached data.

- **Lazy init on first access** (rejected): requires every query method to be `async`, which cascades through all call sites.
- **Eager init at startup** (chosen): one `await ModelCatalog.init()` in `main.dart`; all downstream code remains synchronous and unchanged.

### D6: Write after each evaluated entry

After each model completes evaluation (success or failure), `voice-models.json` is written to disk before the next model begins. A long evaluation run (dozens of models, gigabytes of downloads) must not lose results on crash or Ctrl-C. The cost of an extra JSON write per model is negligible compared to download time.

### D7: Fixture WAV files stored in the repo

Short reference WAV clips (2–5 seconds, mono 16 kHz) are stored at `apps/lib/voice_catalog/fixtures/<lang>.wav`. They are regular files accessed via `dart:io`, not Flutter assets, so they are not bundled with the app. The tool resolves their path relative to the project directory using `Platform.script` or `Directory.current`.

Languages with no dedicated fixture fall back to the English clip. The English clip is mandatory; others are added as the catalog grows to cover more languages.

## Risks / Trade-offs

**Filename parsing brittleness** → If sherpa-onnx changes naming conventions, new models land as `untested` with a parse note. The developer adds metadata manually. No data is lost; the tool degrades gracefully.

**Large downloads in evaluation** → Some models exceed 500 MB. `ModelDownloadService` already handles resumable downloads and cached extraction; the tool reuses this. A developer should expect evaluation runs to take significant time on first use.

**ModelCatalog async init adds startup latency** → Parsing a ~50 KB JSON file at startup is fast (< 5 ms on any device). This is not a concern.

**voice-models.json bundled with app includes fail/untested entries** → All entries ship in the asset regardless of status. The app filters in code. The overhead is ~1 KB per extra entry — negligible. The benefit is a single file to maintain.

**fileStructure cannot be inferred from filename** → The tool cannot fully populate `fileStructure` for a newly discovered model without downloading and inspecting the archive. For `untested` entries, `fileStructure` is left as `{}`. After a successful evaluation, the tool inspects the extracted archive and populates `fileStructure` in the JSON entry automatically.

## Migration Plan

1. **Seed `voice-models.json`** with all existing `ModelCatalog` entries, status `"approved"`, `recommended: true` (one per language+type).
2. **Refactor `ModelCatalog`**: add `CatalogEntry.fromJson`, add `ModelCatalog.init()`, make `entries` a mutable static list populated at init. Existing query methods are unchanged.
3. **Add `await ModelCatalog.init()` in `main.dart`** before `runApp`.
4. **Update `model_catalog_test.dart`**: tests now load from a test-fixture JSON rather than relying on compile-time constants. Existing test assertions remain valid.
5. **Build and verify**: run the app on Linux and Android; confirm model selection UI shows the same models as before.
6. **Ship `voice-catalog` tool**: add entry point, discovery/filter/evaluate logic, fixtures.

Rollback: revert `model_catalog.dart` to the constants form and remove the `init()` call in `main.dart`. The `voice-models.json` asset can stay; it simply won't be read.

## Open Questions

- **fileStructure population**: the current design populates `fileStructure` by inspecting the extracted archive during evaluation. Should the tool infer common structures from architecture type (e.g., transducer always has encoder/decoder/joiner/tokens) to avoid full extraction? Probably yes — the evaluate phase extracts anyway, so inspection is free.
- **Piper quality filtering**: `x_low` and `low` are excluded. Should `high` quality variants be preferred over `medium` automatically (e.g., auto-set `recommended: true`)? Or always leave `recommended` to the developer? Leaving it to the developer is safer.
- **GitHub API rate limiting**: unauthenticated API calls are limited to 60/hour. Two calls (one per release tag) are well within limits. No authentication is needed.

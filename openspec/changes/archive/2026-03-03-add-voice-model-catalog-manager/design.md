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

### D1: Pure Dart CLI, not a Flutter app or integration test

*This decision supersedes the original design that chose a Flutter Linux app. See revision note below.*

The tool was initially designed as a Flutter Linux app (`flutter run -d linux`) to get free access to Flutter plugins (`sherpa_onnx`, `path_provider`). In practice, `flutter run -d linux` creates a GTK window that suppresses stdout entirely, making the tool unusable as a CLI. The approach was revised.

- **Flutter Linux app** (rejected): suppresses CLI output behind a GTK window.
- **Integration test** (`flutter test -d linux`): designed for fast widget tests, not multi-hundred-MB downloads.
- **Pure Dart CLI** (chosen): `dart run` on a standalone `tools/voice_catalog/` package. `sherpa_onnx` native bindings are loaded explicitly via `sherpa_onnx.initBindings(path)` in Dart; the shell script `bin/voice-catalog` sets `LD_LIBRARY_PATH` and `VOICE_CATALOG_SHERPA_LIB_DIR` by locating the `.so` in the project-local pub cache. No Flutter engine is involved.

`path_provider` is not needed: the tool uses the XDG cache directory (`$XDG_CACHE_HOME/relagent/models`, falling back to `~/.cache/relagent/models`) resolved from environment variables.

### D2: Standalone Dart package, project-local pub cache

The tool lives at `tools/voice_catalog/` as its own `pubspec.yaml` with a project-local `.pub-cache/` directory (set via `PUB_CACHE` before `dart pub get`). All packages, including the native `.so` files from `sherpa_onnx_linux`, are downloaded inside the repository tree and never reach into `~/.pub-cache`.

- **Inside `apps/`**: the `apps/` project is a Flutter package; adding a CLI entry point creates friction and pollutes the Flutter build.
- **Standalone package with local cache** (chosen): self-contained, auditable, no global side effects.

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

### D8: Shared `packages/sherpa_voice/` for all sherpa-onnx domain code

The evaluation tool needs to use the exact same sherpa-onnx config-building logic as the app, so that a model that passes the smoke test is guaranteed to work in production. Rather than duplicating the architecture switch in the tool, all sherpa-onnx-specific knowledge is extracted to a new pure Dart package `packages/sherpa_voice/`.

- **Duplicate in tool**: config construction diverges silently when the app's logic changes.
- **Import `apps/` as path dependency**: `apps/` is a Flutter package; importing it from a pure Dart CLI pulls in Flutter transitively.
- **Shared pure Dart package** (chosen): `packages/sherpa_voice/` depends only on `sherpa_onnx`, `archive`, and `path`. Both `apps/` and `tools/voice_catalog/` reference it via `path:` dependency.

The package contains: `ModelArchitecture` and `ModelType` enums, the `ModelLoader` abstract interface, architecture-specific ASR and TTS config builders, and the `.tar.bz2` archive extractor (sherpa-onnx's archive format convention). It has no knowledge of where files come from (assets, downloads, or local paths) — that remains in each consumer.

The download logic itself (HTTP streaming) is **not** moved to the shared package. The app's `ModelDownloadService` has UI concerns (progress, cancellation) that are orthogonal to sherpa-onnx. The tool's `ModelDownloadService` is simpler. Only the archive extraction format (strip top-level prefix, write `.complete` marker) is shared.

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

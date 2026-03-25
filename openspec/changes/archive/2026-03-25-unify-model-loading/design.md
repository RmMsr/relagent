## Context

The app currently has two parallel model loading paths:

- **Bundled path**: `NativeVoiceService` creates an `AssetModelLoader` which copies individual model files from Flutter assets to the cache directory on demand. Referenced in `voice_service_native.dart` line 21 (`final ModelLoader _modelLoader = AssetModelLoader()`).
- **Downloaded path**: `model_resolver.dart` creates a `DownloadModelLoader` when a user-selected downloaded model is active.

When a downloaded model is selected, the downloaded path wins (resolved by `resolveAsrMetadata` / `resolveTtsModel`). When no model is selected, the bundled path is used as fallback in `sherpa_tts.dart` and `sherpa_streaming_asr.dart`. This branching exists in `model_resolver.dart` (null returns mean "use bundled"), `voice_service_native.dart`, and the legacy config branches in the sherpa files.

The proposal asks to eliminate the bundled path by treating bundled archives as pre-seeded downloads — extracted once at startup, then served by `DownloadModelLoader` like any other model.

## Goals / Non-Goals

**Goals:**
- Single runtime loading path for all models (downloaded or bundled)
- Remove `AssetModelLoader` as a runtime concept
- Bundled models appear as already-installed in the model list on first launch
- `pubspec.yaml` asset declarations reduce to one `.tar.bz2` per bundled model
- No regression in functionality for users with or without bundled models

**Non-Goals:**
- Changing the download or extraction logic in `ModelDownloadService`
- Supporting platforms other than Android, iOS, and Linux
- Resumable seeding (extraction is fast enough to redo on interrupted first launch)
- Streaming the archive extraction (archives are small, < 200 MB each)

## Decisions

### D1: Seeding on app startup before `runApp`

Bundled archives are extracted in `main.dart` before `runApp`, using a new `BundledModelSeeder` utility. The seeder reads `.tar.bz2` files from `assets/voice-models/` via `rootBundle`, extracts them using `ModelDownloadService.extractArchive` (same code path as downloads), and writes the `.complete` marker.

- **Alternative — lazy seeding on first model use**: Would require `DownloadModelLoader` to know which models might be bundled and check asset availability, mixing concerns back together.
- **Alternative — seeding in a Riverpod provider**: Provider initialization order is less predictable and the seeder must complete before `ModelDownloadState` is first read. Startup is the safe, deterministic point.

Seeding is idempotent: if `.complete` already exists the archive is skipped. First-launch cost is the extraction time (< 2 seconds for a 55 MB archive on device).

### D2: Keep `ModelDownloadService.extractArchive` as the shared extraction function

The extraction logic already exists and handles `.tar.bz2` archives. The seeder reads archive bytes from `rootBundle` into a temporary file and calls `extractArchive` with the same destination path convention (`<support_dir>/models/<type>/<model-id>/`).

- **Alternative — duplicate extraction in seeder**: Violates DRY and risks divergence. The same code must work for both.

### D3: `AssetModelLoader` converted to internal seeding utility only

`AssetModelLoader` changes role: it is no longer `ModelLoader`-implementing and no longer injected into `NativeVoiceService`. Its asset-reading logic moves into `BundledModelSeeder` (or `AssetModelLoader` is renamed to `BundledModelSeeder` directly). The `ModelLoader` interface implementation is removed.

- **Alternative — delete `AssetModelLoader` entirely**: Clean, but the `rootBundle` access logic is useful in `BundledModelSeeder`. Renaming is cleaner than deleting and reimplementing.

### D4: `NativeVoiceService` injects `DownloadModelLoader` directly

After this change, `NativeVoiceService` no longer needs a field-level `ModelLoader` for bundled models. The loader is created per-model in `model_resolver.dart` (already done for downloaded models). The field `final ModelLoader _modelLoader = AssetModelLoader()` is removed from `NativeVoiceService`. The null-return convention in `resolveAsrMetadata` / `resolveTtsModel` no longer means "use bundled" — null means "no model available".

### D5: Bundled model IDs must match catalog entries

A bundled `.tar.bz2` archive must correspond to a `CatalogEntry` in `voice-models.json` (or the hardcoded catalog until that change lands). The archive filename is the model ID: `assets/voice-models/<model-id>.tar.bz2`. The seeder derives the type and destination path from the catalog entry.

- **Alternative — embed type in filename**: More explicit but redundant — the catalog already maps ID to type. Single source of truth wins.

### D6: `AppConfig` bundled model fields become seeding config only

`AppConfig.streamingAsrModelName` and `AppConfig.ttsModelName` are currently used at runtime to find model files. After this change they are used only by the seeder to know which archive file to look for. If null, no seeding happens for that type. The fields remain nullable.

## Risks / Trade-offs

**First-launch startup latency** → Extraction of a 55 MB archive takes < 2 seconds on a mid-range device. For distribution builds without bundled models, startup is unchanged. Acceptable.

**App size increase for bundled builds** → Bundling a `.tar.bz2` archive is already the case; the change is in how it's referenced in `pubspec.yaml` (one line instead of a file tree). No size regression.

**Android and iOS asset size limits** → Large `.tar.bz2` files (> 100 MB) may hit Play Store or App Store asset limits depending on delivery method. This is a deployment concern, not a code concern. The unbundled default (no assets, user downloads) is the recommended path for distribution.

**`.tar.bz2` in Flutter assets is not streaming** → Flutter's `rootBundle.load` reads the full asset into memory. For a 55–200 MB archive this is fine on modern devices. For archives > 200 MB, streaming would be preferable, but such large bundled models are an edge case.

**Rollback** → Revert `main.dart` seeding call and restore `AssetModelLoader` injection in `NativeVoiceService`. The extracted models in support directory remain (harmless; they appear as downloaded and deletable by the user).

## Migration Plan

1. Add `BundledModelSeeder` utility: reads archive bytes from `rootBundle`, writes to a temp file, calls `ModelDownloadService.extractArchive`, writes `.complete` marker.
2. Call `await BundledModelSeeder.seedAll()` in `main.dart` before `runApp` (after `ModelCatalog.init()` if that change has landed, or after the hardcoded catalog is available).
3. Remove `AssetModelLoader` implementation of `ModelLoader` interface. Update or rename to `BundledModelSeeder`.
4. Remove `final ModelLoader _modelLoader = AssetModelLoader()` from `NativeVoiceService`. Remove `modelLoader` getter.
5. Remove bundled fallback branches from `sherpa_tts.dart`, `sherpa_streaming_asr.dart`, and `voice_service_native.dart`.
6. Update `model_resolver.dart`: null from `resolveAsrMetadata` / `resolveTtsModel` now means unavailable (no model), not "use bundled".
7. Update `pubspec.yaml`: replace multi-file asset directory listings with `assets/voice-models/<model-id>.tar.bz2` entries.
8. Test: launch app with bundled archives; confirm models appear as downloaded in the model list.
9. Test: launch app without bundled archives; confirm graceful degradation (model list empty, voice unavailable).

## Open Questions

- **Should `BundledModelSeeder` log progress?** Extraction on first launch takes a few seconds. A startup splash or progress indicator is outside scope, but a debug log is useful.
- **What if a bundled archive's catalog entry is missing?** The seeder skips it and logs a warning. This should not happen in practice (developer error).

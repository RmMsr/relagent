## Context

The app manages sherpa-onnx models in two places:

- **Catalog models** (`ModelCatalog`) — approved entries from the bundled `voice-models.json`, downloaded over HTTP to `<cache_dir>/models/<type>/<id>/`. `CatalogEntry` has many required fields (downloadUrl, fileStructure, origin, etc.) that are meaningless for user-supplied files.
- **Model resolver** (`model_resolver.dart`) — selects the right file paths for the engine by looking up `ModelCatalog.findById` and handing off to `DownloadModelLoader`.

Imported models live outside this catalog. They arrive as `.tar.bz2` archives (the format sherpa-onnx uses for all distributions). The archive must be extracted and the model must surface in the selection UI alongside catalog models.

## Goals / Non-Goals

**Goals:**
- Let users pick a `.tar.bz2` model archive from device storage via the system file picker.
- Auto-detect model architecture from archive file structure where possible.
- Collect optional user-supplied metadata (display name, model type, language codes) through a form after picking the file.
- Extract the archive to persistent (non-cache) storage and register the model in a local manifest.
- Surface imported models in the existing catalog browser and selection UI with an "Imported" badge.
- Allow deletion of imported models from within the app.

**Non-Goals:**
- Supporting directory-based (pre-extracted) imports in this change — archives only.
- Validating that the imported model is actually loadable before registration.
- Cloud sync or backup of imported models.
- Modifying the `voice-models.json` format or the `voice-catalog` CLI tool.

## Decisions

### D1 — Separate data type for imported models

`CatalogEntry` has many required fields that are meaningless for user-supplied models (`downloadUrl`, `fileStructure`, `origin`, `releaseDate`, etc.). Rather than making those nullable (breaking the invariant that catalog entries are fully described), introduce a separate `ImportedModelEntry`:

```dart
class ImportedModelEntry {
  final String id;           // "imported-<uuid>"
  final String displayName;  // user-supplied or derived from filename
  final ModelType type;      // required selection (ASR / TTS)
  final ModelArchitecture architecture;  // required for engine
  final List<String> languages;  // optional; empty list if not supplied
  final DateTime importedAt;
}
```

This is persisted to `<support_dir>/imported_models.json`. A companion `ImportedModelRegistry` (analogous to `ModelCatalog`) loads and manages the list at runtime. It exposes `byType`, `byTypeAndLanguage`, and `findById`, mirroring the catalog API so callers can treat both sources uniformly.

**Alternative considered:** Extend `CatalogEntry` with an `isImported` flag and nullable fields. Rejected because it pollutes all existing catalog code with null-checks and blurs the boundary between "vetted catalog entry" and "user file".

### D2 — Storage in application support directory (not cache)

Downloaded catalog models go to `getApplicationCacheDirectory()`. The OS may purge cache at any time. User-imported models are irreplaceable (they came from external storage the user may no longer have access to), so they go to `getApplicationSupportDirectory()`:

```
<support_dir>/
  imported_models.json        # manifest (array of ImportedModelEntry)
  imported_models/
    asr/<id>/
      <extracted files>
      .complete
    tts/<id>/
      <extracted files>
      .complete
```

The `.complete` marker convention mirrors the download service.

### D3 — Architecture auto-detection from archive file names

Architecture is required by the engine but opaque to users. On import, scan the archive file list and match against known sherpa-onnx naming conventions:

| Detected files | Architecture |
|---|---|
| `encoder*.onnx` + `decoder*.onnx` + `joiner*.onnx` | `transducer` |
| `model.onnx` + `tokens.txt` (ASR) | `ctc` |
| `model.onnx` + `tokens.txt` + `espeak-ng-data/` (TTS) | `vitsPiper` |
| `model.onnx` + `voices.bin` | `kokoro` |
| `encoder-epoch*.onnx` + `decoder-epoch*.onnx` (NeMo naming) | `onlineNemoCtc` / `offlineNemoTransducer` |

Detection is best-effort. When detection fails (or produces a low-confidence result), show the architecture field as a required dropdown in the metadata form, pre-filled with the detected guess. When detection succeeds confidently, pre-fill it and collapse the field into an editable chip so it's not distracting but remains overridable.

### D4 — Separate Riverpod provider for imported models

`ModelDownloadState` and `ModelDownloadNotifier` are download-specific (progress, cancellation, HTTP errors). Mixing import operations there would conflate two distinct responsibilities. Instead:

- New `importedModelsProvider` (a `NotifierProvider<ImportedModelsNotifier, ImportedModelsState>`) owns the imported-model list and import/delete operations.
- `ImportedModelsState` holds `List<ImportedModelEntry> entries` and an `AsyncValue`-style operation state (idle / importing / error).
- The import operation (pick → extract → write manifest) lives in `ImportedModelService`.

### D5 — Model ID namespace for imported entries

Imported model IDs are prefixed `imported-` followed by a UUID generated at import time (e.g., `imported-a3f2c1d4`). This prevents collisions with catalog IDs and lets the resolver distinguish sources without extra lookup.

### D6 — Resolver updated to consult both sources

`model_resolver.dart` currently calls `ModelCatalog.findById` and assumes a `DownloadModelLoader`. Update the lookup sequence:

1. Try `ModelCatalog.findById` → use `DownloadModelLoader` as before.
2. Try `ImportedModelRegistry.findById` → use `ImportedModelLoader` (points to `<support_dir>/imported_models/<type>/<id>/`).
3. Return null if neither finds the ID.

`ImportedModelLoader` implements the same `ModelLoader` interface as `DownloadModelLoader`. It derives paths relative to the support dir instead of cache dir. Because imported models have no `fileStructure` map, `ImportedModelLoader.loadModelFile` returns the model root directory rather than a named file; the engine is expected to discover files by walking the directory (which it does for all supported architectures).

### D7 — Imported models appear first in all listings

In the catalog browser and any model-selection surface, imported models are listed **before** catalog models within the same type tab. Within the imported group, entries are sorted by `importedAt` descending (most recently imported first). Within the catalog group, existing ordering (recommended first, then alphabetical) is unchanged.

Rationale: a user who imported a model almost certainly wants to use it; burying it below a long catalog list makes the feature feel hidden.

The `ImportedModelRegistry` query methods (`byType`, `byTypeAndLanguage`) return imported entries in this order. The UI concatenates `importedEntries + catalogEntries` when building each list.

### D8 — Metadata form design

The import sheet collects:

| Field | Required | Notes |
|---|---|---|
| Display name | No | Pre-filled from archive filename without extension |
| Model type | Yes | ASR / TTS toggle; determines storage sub-path |
| Architecture | Yes | Dropdown; pre-filled from detection (see D3) |
| Languages | No | Free text comma-separated ISO codes, or multi-chip input |

"Required" here means it has a reasonable default: model type defaults to ASR, architecture defaults to the detected value. The user can tap Import without changing anything; the form never blocks on optional fields.

## Risks / Trade-offs

- **Unvalidated models** → A user imports a model the engine can't load. Mitigation: show a clear error when the model fails to initialise (existing engine error reporting covers this); no special pre-validation needed.
- **Large archives block the main thread** → Extraction is synchronous in `model_archive.dart` (reads all bytes into memory). Mitigation: run extraction in an `Isolate` or via `compute()`. This is already a risk for downloaded models; address it here.
- **Architecture detection false positives** → Wrong architecture causes a crash at load time. Mitigation: make architecture always overridable in the form; document naming conventions in the UI tooltip.
- **`listDownloadedModels` only scans cache dir** → Imported models in support dir are invisible to it. Mitigation: `importedModelsProvider` maintains its own availability state; the resolver's two-step lookup handles this without merging the two sets.

## Migration Plan

No migrations required. Imported models are additive: new directories and a new JSON file in support dir. Existing downloaded catalog models are unaffected. The manifest is created on first import.

## Open Questions

- Should architecture be truly required (block Import if not determinable) or always optional with a safe fallback default? Lean toward required with auto-detection so the engine doesn't fail silently.
- What should happen if the user imports a model with an archive that has a non-standard structure (nested dirs, no top-level prefix)? `extractModelArchive` already handles the no-prefix case; test coverage needed.

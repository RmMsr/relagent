## 1. Dependencies

- [x] 1.1 Add `file_picker` to `apps/pubspec.yaml` and run `fvm flutter pub get`
- [x] 1.2 Add `READ_EXTERNAL_STORAGE` / `READ_MEDIA_*` permissions to `apps/android/app/src/main/AndroidManifest.xml` as needed by `file_picker`

## 2. Domain Layer — ImportedModelEntry & Registry

- [x] 2.1 Create `apps/lib/models/imported_model.dart` with `ImportedModelEntry` (fields: id, displayName, type, architecture, languages, importedAt) and JSON serialisation
- [x] 2.2 Create `apps/lib/voice/imported_model_registry.dart` with `ImportedModelRegistry` singleton: `init()`, `entries`, `byType()`, `byTypeAndLanguage()`, `findById()`, `add()`, `remove()`; reads/writes `<support_dir>/imported_models.json`
- [x] 2.3 Call `ImportedModelRegistry.init()` in `apps/lib/main.dart` at app startup (alongside `ModelCatalog.init()`)

## 3. Service Layer — Import, Load, Detect

- [x] 3.1 Create `apps/lib/voice/model_architecture_detector.dart` with a pure function `detectArchitecture(List<String> archiveEntryNames) → ModelArchitecture?` implementing the file-pattern rules from design D3
- [x] 3.2 Create `apps/lib/voice/imported_model_loader.dart` implementing `ModelLoader`; resolves paths under `<support_dir>/imported_models/<type>/<id>/`; `isModelAvailable` checks for `.complete` marker
- [x] 3.3 Create `apps/lib/voice/imported_model_service.dart` with:
  - `peekArchive(File) → ({List<String> entries, ModelArchitecture? detected})` — reads entry names from archive without extracting
  - `importModel(File archive, ImportedModelEntry metadata) → Future<void>` — generates UUID id, extracts archive via `compute(extractModelArchive, ...)`, writes `.complete` marker, calls `ImportedModelRegistry.add()`
  - `deleteModel(String id) → Future<void>` — deletes directory, calls `ImportedModelRegistry.remove()`

## 4. Provider Layer

- [x] 4.1 Create `apps/lib/providers/imported_models_provider.dart` with `ImportedModelsState` (fields: entries, operationError) and `ImportedModelsNotifier` exposing `importFromFile(File, ImportedModelEntry)` and `deleteModel(String id)`; invalidates on completion

## 5. Model Resolver Update

- [x] 5.1 Update `resolveAsrMetadata` in `apps/lib/voice/model_resolver.dart` to fall back to `ImportedModelRegistry.findById` and `ImportedModelLoader` when `ModelCatalog.findById` returns null
- [x] 5.2 Update `resolveTtsModel` in `apps/lib/voice/model_resolver.dart` with the same two-step lookup
- [x] 5.3 Update `getSelectedTtsSpeakerCount` in `apps/lib/voice/model_resolver.dart` to check the imported registry when the catalog returns null

## 6. UI — Import Flow

- [x] 6.1 Create `apps/lib/widgets/import_model_sheet.dart`: a bottom sheet / dialog showing the metadata form (display name, ASR/TTS toggle, architecture dropdown, language chips); validates type and architecture before enabling the Import button; accepts a pre-detected architecture
- [x] 6.2 Create `apps/lib/widgets/import_model_button.dart` (or inline in catalog browser): taps opens file picker, calls `importedModelService.peekArchive()`, then shows `ImportModelSheet`; shows a loading indicator during extraction; shows an error snackbar on failure

## 7. UI — Catalog Browser Changes

- [x] 7.1 Update the list-building logic in `apps/lib/widgets/model_management_section.dart` to prepend imported models (from `importedModelsProvider`) before catalog entries in each tab; imported group sorted by `importedAt` descending
- [x] 7.2 Add an "Imported" badge chip to imported model cards in the catalog browser; omit download-size and origin fields for imported cards
- [x] 7.3 Add an "Import from storage" action button to the catalog browser app bar or FAB area; wire it to the import flow from 6.2
- [x] 7.4 Add a delete action to imported model cards; show a confirmation dialog; on confirm call `ImportedModelsNotifier.deleteModel()`; show a snackbar on completion
- [x] 7.5 Update the "Downloaded" filter chip logic so imported models are always included when the filter is active (they are always locally available)
- [x] 7.6 Ensure the `importedModelsProvider` is watched in the catalog browser so the list updates reactively after import or deletion

## 8. Tests

- [x] 8.1 Unit-test `detectArchitecture` in `apps/test/voice/model_architecture_detector_test.dart` covering all four detected architectures and the undetected fallback
- [x] 8.2 Unit-test `ImportedModelRegistry` in `apps/test/voice/imported_model_registry_test.dart`: init from missing file, add entry, remove entry, persist and reload
- [x] 8.3 Unit-test `ImportedModelLoader.isModelAvailable` with and without the `.complete` marker
- [x] 8.4 Unit-test `model_resolver.dart` fallback path: catalog miss → imported registry hit returns correct metadata

## Why

Users may have sherpa-onnx models already on device — downloaded manually, sideloaded, or obtained from sources not in the curated catalog. There is currently no way to use these models in the app without adding them to the bundled catalog, which requires a release cycle.

## What Changes

- Add a UI flow that lets the user pick a model archive (`.tar.bz2` / `.zip` / directory) from local storage via the system file picker.
- Collect optional metadata from the user (language, display name, model type) through a simple form shown after file selection; all fields are optional except those required for the engine to load the file.
- Store the imported model in the same on-device model directory used by downloaded models, tagged with an `imported` source so the app can distinguish it from catalog entries.
- Surface imported models alongside catalog entries in the model selection UI, with a visual indicator that the model was user-imported.
- Allow the user to delete an imported model from within the app.

## Capabilities

### New Capabilities
- `local-model-import`: Pick, validate, and store a locally sourced model archive; collect optional user-supplied metadata; expose the result through the existing model selection surface.

### Modified Capabilities
- `model-catalog`: Imported models must appear in the catalog browser and model-selector alongside downloaded catalog entries; the catalog must accommodate entries with partial metadata.
- `voice-model-index`: Entry schema needs an optional `source` field (`"catalog"` | `"imported"`) and a `userLabel` field so imported entries without a canonical id can carry a user-supplied display name. Required metadata fields (e.g. `languages`, `downloadUrl`) must become optional for imported entries.

## Impact

- **File picker**: requires `file_picker` package (or equivalent) on Android and iOS; needs storage-read permission on Android.
- **Model loading**: imported models use the same `ModelLoader` / sherpa-onnx pipeline as catalog downloads; no engine changes needed if the file layout is compatible.
- **Model index / catalog domain layer**: `CatalogEntry` and `ModelCatalog` must tolerate null metadata fields for imported entries.
- **Settings / model-selection UI**: needs to render imported-model cards with reduced metadata and a delete action.
- **No server-side or API changes** required.

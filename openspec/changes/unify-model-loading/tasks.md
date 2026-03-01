## 1. Bundled Model Seeder

- [ ] 1.1 Create `apps/lib/voice/bundled_model_seeder.dart` with a `BundledModelSeeder.seedAll()` static async method that reads bundled archive paths from `AppConfig` and extracts each to `<support_dir>/models/<type>/<model-id>/` using `ModelDownloadService.extractArchive`
- [ ] 1.2 Skip extraction if a `.complete` marker already exists at the destination path
- [ ] 1.3 Write the `.complete` marker after successful extraction
- [ ] 1.4 Log a debug message for each model: "Seeding bundled model <id>..." and "Skipping <id>, already seeded"
- [ ] 1.5 Handle missing catalog entry gracefully: log a warning and skip if `AppConfig` model name has no matching `CatalogEntry`

## 2. Startup Integration

- [ ] 2.1 Call `await BundledModelSeeder.seedAll()` in `apps/lib/main.dart` before `runApp`, after other async init steps (SharedPreferences, AppConfig, ModelCatalog if applicable)
- [ ] 2.2 Verify seeding does not block the splash screen: confirm it completes in < 3 seconds on a fresh install with a 55 MB bundled model

## 3. Remove AssetModelLoader as Runtime Loader

- [ ] 3.1 Remove the `ModelLoader` interface implementation from `AssetModelLoader` (or delete the file entirely if all logic moves to `BundledModelSeeder`)
- [ ] 3.2 Remove `final ModelLoader _modelLoader = AssetModelLoader()` and the `modelLoader` getter from `NativeVoiceService`
- [ ] 3.3 Remove the `import '/voice/asset_model_loader.dart'` reference from `voice_service_native.dart`

## 4. Unify Model Resolver

- [ ] 4.1 Update `resolveAsrMetadata` in `model_resolver.dart`: null return now means "no model available" (not "use bundled"); update function comment accordingly
- [ ] 4.2 Update `resolveTtsModel` in `model_resolver.dart`: same convention — null means unavailable
- [ ] 4.3 Update `getSelectedTtsSpeakerCount` in `model_resolver.dart`: remove the bundled-Kokoro fallback comment (speaker count now comes from catalog entry or defaults to 0)
- [ ] 4.4 Ensure all callers of `resolveAsrMetadata` and `resolveTtsModel` handle null as "unavailable" (no silent fallback to a bundled path)

## 5. Remove Legacy Bundled Branches

- [ ] 5.1 Remove the legacy/asset-shortcut config branch from `apps/lib/tts/sherpa_tts.dart` (the path that constructs `OfflineTtsConfig` from `AppConfig.ttsModelName` directly)
- [ ] 5.2 Remove the legacy/asset-shortcut config branch from `apps/lib/speech_recognition/sherpa_streaming_asr.dart` (the path that constructs `OnlineRecognizerConfig` from `AppConfig.streamingAsrModelName` directly)
- [ ] 5.3 Remove any remaining references to `AssetModelLoader` from `voice_service_native.dart` and anywhere else in the codebase

## 6. Update pubspec.yaml Assets

- [ ] 6.1 Create `apps/assets/voice-models/` directory (add `.gitkeep` so it exists in the repo even when no bundles are present)
- [ ] 6.2 Replace the multi-file asset directory listings for bundled models in `apps/pubspec.yaml` with `assets/voice-models/<model-id>.tar.bz2` entries (or remove if no models are bundled by default)
- [ ] 6.3 Verify `flutter build` still succeeds with the new asset structure

## 7. AppConfig Clarification

- [ ] 7.1 Update comments in `apps/lib/config/app_config.dart`: `streamingAsrModelName` and `ttsModelName` are now seeding config only — the model name identifies the `.tar.bz2` to extract; null means no bundled model for that type
- [ ] 7.2 Update `apps/assets/config.template.json` (if present): add a comment explaining the field is optional seeding config, not a runtime requirement

## 8. Testing and Verification

- [ ] 8.1 Test fresh install with bundled archives: confirm models appear as downloaded in the model selection UI immediately on first launch
- [ ] 8.2 Test fresh install without bundled archives (no `assets/voice-models/` entries): confirm app starts, model list is empty, voice mode shows "model required"
- [ ] 8.3 Test second launch after seeding: confirm seeding is skipped (`.complete` marker present) and startup time is unchanged
- [ ] 8.4 Test model deletion via UI then app restart: confirm model does NOT re-seed (deleted model should stay deleted, not auto-restore)
- [ ] 8.5 Run `dart-flutter_analyze_files` on `apps/`; fix any analysis warnings
- [ ] 8.6 Run `dart-flutter_run_tests` on `apps/`; confirm all tests pass

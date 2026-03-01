## Why

There is no systematic process for evaluating new or updated on-device voice models against the project's requirements. When sherpa-onnx releases new models, identifying good candidates and verifying they actually work requires manual effort. The gap between "model exists" and "model lands in the next app release" should be a single command.

## What Changes

- Add a **Dart/Flutter CLI app** (`lib/eval/eval_main.dart`) that runs on Linux as a separate entry point in the existing `apps/` project
- The tool auto-discovers new sherpa-onnx models from the GitHub releases API, filters them against project criteria, downloads and smoke-tests candidates using the same code paths as the app, and writes results back to `apps/assets/voice-models.json`
- The app reads `voice-models.json` at startup as its model catalog instead of a hardcoded Dart class
- `ModelCatalog` becomes a thin JSON parser rather than a constants file

Run: `fvm flutter run -d linux -t lib/eval/eval_main.dart`

The tool shares the same `pubspec.yaml`, the same `sherpa_onnx` native bindings, and the same `apps/lib/` code as the app — giving high confidence that models that pass evaluation will work in the app.

## Capabilities

### New Capabilities

- `voice-model-index`: A single pretty-printed JSON file (`apps/assets/voice-models.json`) that is both the tool's output and the app's model catalog. Each entry contains model metadata (id, architecture, language, size, license, download URL) plus two curation fields: `status` (`untested` | `fail` | `approved`) and `recommended` (boolean). The tool sets `status` to `untested` on discovery and updates it to `fail` or leaves a `pass` note after evaluation; the developer promotes entries to `approved` and marks one `recommended: true` per language+type combination. The app reads only `approved` entries and highlights `recommended` ones. The file is checked into the repo; git history is the evaluation log.

- `voice-catalog`: A Flutter Linux CLI app (`lib/eval/eval_main.dart`) that manages the full lifecycle of `voice-models.json`. Three phases run in sequence:
  1. **Discover** — fetch the GitHub releases API for the `asr-models` and `tts-models` tags on `k2-fsa/sherpa-onnx`, parse asset filenames to extract id/architecture/language/size/URL, add any entries not already in `voice-models.json` as `untested`
  2. **Filter** — skip entries that fail hard criteria: non-permissive license, unsupported architecture, size > 1 GB, no project-relevant language (en/de/fr/es/it/nl/pl/ru/sv/pt/cs), or Piper quality below `medium` (x_low and low variants excluded)
  3. **Evaluate** — for each `untested` entry that passes filters: download via `ModelDownloadService`, initialize via `createOnlineRecognizerFromMetadata` / `createOfflineTtsFromMetadata`, run a minimal inference pass (short WAV for ASR, short sentence for TTS), record latency, update `status` to `fail` with notes on error, write `voice-models.json`; developer then reviews output and promotes passing entries to `approved`

### Modified Capabilities

- `model-loading`: The app's model catalog transitions from a hardcoded Dart class (`ModelCatalog` with `const List<CatalogEntry> entries`) to a JSON-driven catalog loaded from `assets/voice-models.json` at app startup. `ModelCatalog` becomes a loader that parses the JSON and exposes the same query API (`byType`, `byLanguage`, `findById`, etc.) that the rest of the app already uses.

## Impact

- `apps/lib/voice_catalog/voice_catalog_main.dart` — new Flutter Linux CLI entry point (`voice-catalog` tool)
- `apps/lib/voice_catalog/` — discovery, filtering, evaluation, and JSON I/O logic
- `apps/assets/voice-models.json` — generated and checked in; read by the app at startup
- `apps/lib/models/model_catalog.dart` — refactored from constants to JSON parser (API unchanged)
- `apps/test/models/model_catalog_test.dart` — updated for JSON-backed catalog
- `tools/model_eval/fixtures/` — short test WAV clips for ASR smoke tests (one per language)

### Intended workflow

```
fvm flutter run -d linux -t lib/voice_catalog/voice_catalog_main.dart
→ Fetches github.com/k2-fsa/sherpa-onnx releases API
→ Finds 3 new model entries not in voice-models.json → adds as "untested"
→ Filters out entries with no project-relevant language or low quality
→ Downloads and smoke-tests untested entries
→ 2 run successfully, 1 fails (notes: "encoder_dims missing in metadata")
→ Writes voice-models.json with updated notes/status
→ Developer reviews diff, promotes passing entries to "approved",
  sets recommended: true on best pick per language
→ git commit apps/assets/voice-models.json
→ Ships in next release — app reads new models on first use
```

### Expected model count (after filter phase)

Piper TTS has ~76 European voice variants across quality tiers (source: rhasspy/piper VOICES.md):
- English: 31 voices (en_US + en_GB), quality low–high
- German: 8, French: 5, Spanish: 7, Italian: 2, Dutch: 7, Polish: 4, Russian: 4, Swedish: 2, Portuguese: 5, Czech: 1

After excluding `x_low` and `low` quality: **~40 Piper voices** remain. Add Kokoro (3), Matcha (2), KittenTTS (2) = **~47 TTS models**.

ASR: ~15–20 streaming/offline models for European languages.

**Total expected: ~60–65 models** after filtering. At ~600 bytes each pretty-printed, `voice-models.json` will be approximately **~40 KB** — negligibly small for a Flutter asset.

---

## Research Notes: Model Landscape

### ASR candidates — sherpa-onnx GitHub releases

| Model | Architecture | Languages | Int8 Size | Streaming | License | Status |
|-------|-------------|-----------|-----------|-----------|---------|--------|
| zipformer-en/de/fr-kroko-2025 | transducer | en, de, fr | ~55 MB each | ✓ | Apache-2.0 | approved |
| nemo-parakeet-tdt-0.6b-v3 | offline transducer (VAD) | 25 European | ~640 MB | pseudo | Apache-2.0 | approved |
| nemo-parakeet-tdt-0.6b-v2 | offline transducer | en | ~1.3 GB | pseudo | Apache-2.0 | untested |
| nemo-canary-180m-flash | offline | en, es, de, fr | ~180 MB | ✗ | Apache-2.0 | untested |
| zipformer-ko-2024 | transducer | ko | ~? MB | ✓ | Apache-2.0 | untested |
| zipformer-bn-2026 | transducer | bn | ~87 MB | ✓ | Apache-2.0 | untested |
| gigaam-v2 | offline transducer | ru | ~231 MB | pseudo | Apache-2.0 | untested |
| sense-voice | offline multitask | zh/en/ja/ko/yue | ~228 MB | ✗ | Apache-2.0 | untested |
| whisper-tiny/distil | offline | 99 lang / en | 50–300 MB | ✗ | MIT | untested |

Excluded automatically: Chinese-only, dialect-specific, non-commercial licenses.

### TTS candidates — sherpa-onnx GitHub releases

| Model | Family | Languages | In catalog |
|-------|--------|-----------|------------|
| Kokoro v0.19 | kokoro | en (54 speakers) | approved |
| Kokoro v1.0/v1.1 | kokoro | zh + en (53/103 speakers) | untested |
| Piper en/de/fr/ru/sv-medium | vitsPiper | en, de, fr, ru, sv | approved |
| Piper es/it/nl/pl/pt/cs-medium | vitsPiper | es, it, nl, pl, pt, cs | untested |
| Matcha en-ljspeech | matcha | en | untested |
| KittenTTS nano/mini | kitten | en | untested |

### Filtering criteria

A candidate passes the filter phase if:
1. **License**: Apache-2.0 or MIT
2. **Size**: ≤ 1 GB (int8 variant preferred where available)
3. **Architecture**: maps to an existing `ModelArchitecture` enum value
4. **Language**: covers ≥ 1 of: en, de, fr, es, it, nl, pl, ru, sv, pt, cs
5. **Quality**: Piper models at `x_low` or `low` quality are excluded

A candidate is `approved` when a developer has reviewed it and decided to ship it. One entry per language+type is marked `recommended: true` — the tool's suggested default for that language. The app shows all `approved` entries and highlights `recommended` ones.

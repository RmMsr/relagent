## Why

NbAiLab publishes fine-tuned Whisper checkpoints that are the best available Norwegian ASR models (5.9% WER on Bokmål per NbAiLab's own eval), and converting one (`nb-whisper-base`) to sherpa-onnx's ONNX format has been validated end-to-end offline: the HF→OpenAI weight transplant is bit-exact, the export produces working `encoder.onnx`/`decoder.onnx`/`tokens.txt`, and it transcribes real Norwegian speech (including this exact model's own NPSC training-domain audio) essentially perfectly. But `sherpa_voice` cannot run it — there is no `whisper` case in `ModelArchitecture`, no detection branch recognizes the file layout sherpa-onnx's own export script produces, and nothing in the package calls `OfflineRecognizer.fromWhisper`. Without this change the converted model has nowhere to go.

## What Changes

- Add `ModelArchitecture.whisper` to the shared taxonomy in `dart_packages/sherpa_voice/lib/model_architecture.dart`.
- Extend `detectArchitecture()` (`apps/lib/voice/model_architecture_detector.dart`) to recognize the sherpa-onnx whisper export layout: an encoder `.onnx` + decoder `.onnx` pair (no joiner) plus a tokens file, where sherpa-onnx's own `export-onnx.py` names all three with a `{model-name}-` prefix (e.g. `nb-whisper-base-encoder.onnx`, `nb-whisper-base-tokens.txt`) rather than the bare `encoder.onnx`/`tokens.txt` every other architecture assumes. The exact-match `tokens.txt` check and the `startsWith('encoder')`/`startsWith('decoder')` checks both need to accept the prefixed form without breaking existing architectures that rely on the current bare-filename behavior.
- Add a `whisper` branch to whatever `sherpa_voice` code builds `sherpa_onnx.OfflineRecognizerConfig` (mirroring the Python `OfflineRecognizer.fromWhisper` shape: encoder, decoder, tokens, plus a `language` field). The language MUST be forced to a fixed value at config-build time, not left to auto-detect — auto-detection on a single-language fine-tune is what produces garbage output on marginal audio (observed firsthand with the sibling Omnilingual/Parakeet multilingual models: wrong-language lock-in degrades output to near-uselessness). Where the forced language comes from (catalog metadata field vs. hardcoded per-entry) is a design decision, not decided here.
- Exclude `whisper` from any "supports streaming" derivation (e.g. `model_catalog.dart`'s `supportsStreaming` computation) — whisper is confirmed offline/chunked (30s windows, no partial results), unlike transducer/CTC.
- Add a curated `apps/assets/voice-models.json` entry (or document the manual-import path) so a converted whisper model is actually reachable by a user, not just detectable.

**Not doing in this change**: the model-conversion pipeline itself (HF→OpenAI weight bridge, ONNX export, quantization) is a separate, already-validated concern — see `experiments/nb-whisper-onnx/` — not something this app-runtime change needs to redo.

## Capabilities

### New Capabilities
(none — this extends two existing capabilities' requirements, it doesn't introduce a new domain)

### Modified Capabilities
- `sherpa-voice`: architecture taxonomy gains `whisper`; the package's config-builder requirements gain a whisper case with mandatory forced-language configuration (no auto-detect).
- `local-model-import`: the "Architecture Auto-Detection" requirement gains a "Whisper detected" scenario, and the existing CTC/transducer scenarios' file-matching rules need to be read as accepting the model-name-prefixed variants sherpa-onnx's own export tooling produces, not just bare filenames.

## Impact

- `dart_packages/sherpa_voice/lib/model_architecture.dart` — new enum case.
- `dart_packages/sherpa_voice/lib/` — wherever `OfflineRecognizerConfig`/loader construction lives (not yet inspected in detail — a `grep` for the existing transducer/CTC config-builder is the starting point for design.md).
- `apps/lib/voice/model_architecture_detector.dart` — new detection branch, prefix-tolerant filename matching.
- `apps/lib/voice/model_resolver.dart` — `_buildImportedAsrFileStructure()`'s tokens check is an exact `tokens.txt` match; needs the same prefix tolerance as the detector (encoder/decoder resolution there already works via substring match).
- `apps/lib/models/model_catalog.dart` — `supportsStreaming` derivation must exclude `whisper`.
- `apps/assets/voice-models.json` — new catalog entry (or explicit decision to leave whisper import-only).
- `tools/voice_catalog/lib/supported_architectures.dart` — automatically picks up the new enum value (it derives from `ModelArchitecture.values`), no change needed there, but worth confirming in tasks.
- Tests: `apps/test/voice/model_architecture_detector_test.dart`, `apps/test/models/model_catalog_test.dart`, and any `sherpa_voice` package tests covering config builders.

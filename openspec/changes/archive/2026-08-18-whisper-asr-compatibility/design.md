## Context

See `proposal.md` for motivation. Two things discovered while scoping this that change the shape of the work:

1. **The imported-model file-structure resolver has the same prefix-blindness as the detector, in a different place.** `apps/lib/voice/model_resolver.dart`'s `_buildImportedAsrFileStructure()` scans an imported model's files and builds the `{encoder, decoder, joiner, tokens}` map the offline/online builders consume. Encoder/decoder/joiner resolution already uses `.contains(...)`, so sherpa-onnx's `{name}-encoder.onnx` naming resolves correctly today with zero changes — but tokens resolution is `name == 'tokens.txt'`, an exact match, so `{name}-tokens.txt` resolves to an empty path. This needs the identical prefix-tolerant fix as the detector's tokens check, in a second file.
2. **Offline ASR construction is not in the shared package today.** `asr_config.dart` (in `dart_packages/sherpa_voice/`) only builds `OnlineRecognizer` — true streaming. The only place `OfflineRecognizer` is built at all is `apps/lib/speech_recognition/sherpa_vad_asr.dart`'s `_buildOfflineRecognizer()`, and it's hardcoded to a single architecture (`offlineNemoTransducer`, `modelType: 'nemo_transducer'`) — there's no `switch` on architecture there, unlike its online counterpart. This is where `whisper` actually needs to be wired in; the proposal's "not yet inspected in detail" pointer resolves to this file.
2. **`tools/voice_catalog/lib/evaluator.dart` never smoke-tests offline architectures.** It only exercises the shared package's online ASR and TTS builders. `offlineNemoTransducer` entries are catalogued but not eval-tested by the tool today — that gap predates this change and `whisper` will inherit it, not introduce it.

## Goals / Non-Goals

**Goals:**
- `whisper` runs end-to-end in the app via the existing VAD-chunked offline-ASR path, with language forced (never auto-detect).
- Detection recognizes sherpa-onnx's own whisper export naming without weakening detection for any other architecture.

**Non-Goals:**
- Relocating offline-ASR construction into `dart_packages/sherpa_voice/` for symmetry with the online builder. Real architectural debt, but `whisper` doesn't require it — `sherpa_vad_asr.dart`'s builder only needs one more `case`. Moving it is a larger, separately-justifiable refactor (it would also be the natural moment to make `tools/voice_catalog` able to smoke-test offline models, which it currently can't do for any architecture). Called out here so it isn't silently done as a drive-by.
- Live/streaming Whisper decoding. Whisper is a 30-second-window offline model; VAD-chunked pseudo-real-time is the ceiling, matching the `offlineNemoTransducer` precedent.
- The model-conversion pipeline itself (HF→OpenAI weight bridge, ONNX export, quantization). Already solved and validated in `experiments/nb-whisper-onnx/`, orthogonal to app-runtime support.

## Decisions

**Extend `sherpa_vad_asr.dart`'s existing builder rather than generalize it into the shared package.**
Alternative considered: add `buildOfflineAsrRecognizer` to `sherpa_voice`, mirroring `buildAsrRecognizer`. Rejected for this change because nothing currently consumes an offline builder from the shared package — `offlineNemoTransducer` never needed it — so generalizing now is speculative scope beyond what whisper support requires. `_buildOfflineRecognizer()` gains a `switch (architecture)` with two cases instead of one hardcoded path; that mirrors the online builder's shape closely enough that a future consolidation stays cheap.

**Forced language defaults to `CatalogEntry.languages.first`.**
Alternative considered: a dedicated `forcedLanguage` field, or a user-facing language picker for multilingual-capable whisper entries. Rejected for now: every whisper checkpoint under consideration (NbAiLab's `nb-whisper-*`) is fine-tuned toward one target language even though the underlying multilingual tokenizer technically covers others, so `languages.first` is correct for the immediate use case and adds no new catalog schema. If a genuinely multi-target-language whisper entry shows up later, that's the trigger to revisit — see Open Questions.

**Detection matches on shared-prefix encoder+decoder pairs, not a loosened generic rule.**
The alternative — making the existing `startsWith('encoder')`/exact-`tokens.txt` checks prefix-tolerant globally — was rejected because it would let unrelated files accidentally satisfy transducer/CTC detection (e.g. a decoy `decoder_extra.onnx` in an unrelated archive). Whisper detection instead requires: exactly one `*encoder*.onnx`, exactly one `*decoder*.onnx`, both sharing a filename prefix, no joiner file, and a `<same-prefix>tokens.txt` — a narrower, additive rule that can't fire on the existing transducer/CTC shapes (those require a joiner or lack the shared-prefix tokens file respectively).

## Risks / Trade-offs

- **[Risk]** A future contributor adds a second whisper catalog entry with a different target language and nobody notices `languages.first` picked the wrong one silently. → Mitigation: the "Missing forced language rejected" scenario in the spec means an *empty* list fails loudly; a wrong-but-present language won't be caught by code, so note this explicitly in the catalog entry's review checklist (tasks.md).
- **[Risk]** `_buildOfflineRecognizer()` staying app-local means the voice-catalog tool still can't smoke-test whisper entries before they're published, unlike every online architecture. → Mitigation: none in this change (see Non-Goals); manual verification (as already done in this conversation, against real NPSC/FLEURS audio) substitutes until the consolidation happens.

## Open Questions

- Should a whisper catalog entry ever expose more than one forceable language (e.g. a picker), or is one-fine-tune-one-language a safe permanent assumption? Deferred — doesn't change this change's spec, approach, or tasks; only matters if/when a multi-target-language whisper model is actually added to the catalog.

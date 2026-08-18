# Converting NbAiLab Whisper checkpoints to sherpa-onnx

NbAiLab publishes fine-tuned Norwegian Whisper checkpoints (`nb-whisper-{tiny,base,small,medium,large}`, 5.9% WER on Bokmål per their own eval) in HuggingFace `transformers` format. sherpa-onnx's own export tooling only understands OpenAI's original Whisper checkpoint format, so there's a weight-format bridge to build before the usual ONNX export step — and the export script itself needs a small patch to work with current PyTorch. This directory does both, plus a quantization fix that recovers most of the size int8 "should" have saved but doesn't out of the box.

Validated end-to-end against real Norwegian speech (NPSC parliamentary recordings — this model's own training domain — and Google FLEURS) for `nb-whisper-base`; the same recipe applies to the other sizes.

**This is exploratory/one-off tooling, not part of the app.** If whisper support in the app itself becomes real (see `openspec/changes/whisper-asr-compatibility/`), promote what's still needed then — don't assume everything here belongs in `apps/` or `tools/`.

## Quickstart

```shell
./setup.sh                    # isolated venv, ~2 min
./convert.sh nb-whisper-base   # download -> convert -> export -> quantize -> shrink

./venv/bin/python3 fetch_test_audio.py
./venv/bin/python3 sanity_check.py \
  --encoder out/nb-whisper-base/nb-whisper-base-encoder.int8.onnx \
  --decoder out/nb-whisper-base/nb-whisper-base-decoder.int8.fp16emb.onnx \
  --tokens  out/nb-whisper-base/nb-whisper-base-tokens.txt \
  --all

./package_archive.sh nb-whisper-base   # -> out/nb-whisper-base.tar.gz
```

Swap `nb-whisper-base` for `nb-whisper-tiny`/`-small`/`-medium`/`-large` to convert a different size — nothing here is hardcoded to `base`.

## Packaging for the app

`package_archive.sh` bundles the three "sweet spot" files (`*-encoder.int8.onnx`, `*-decoder.int8.fp16emb.onnx`, `*-tokens.txt` — **not** the plain-int8 or fp32 variants) into a `.tar.gz`, filenames unchanged, under a single top-level directory (matching sherpa-onnx's own release convention; the app's archive extractor strips one shared top-level prefix automatically, so this or a flat layout both work).

**Filenames are deliberately left as sherpa-onnx's export script produces them, not renamed to bare `encoder.onnx`/`decoder.onnx`/`tokens.txt`.** Checked against the actual app code, not assumed:

- `apps/lib/voice/model_architecture_detector.dart` and `apps/lib/voice/model_resolver.dart` resolve encoder/decoder by `.contains('encoder')`/`.contains('decoder')` — the `<model>-` prefix already resolves correctly today, no renaming needed there.
- Both files check the tokens filename with an *exact* `== 'tokens.txt'` match, which `<model>-tokens.txt` fails. Renaming just the tokens file would make it resolve under today's code — but doesn't matter yet: see below.

**This archive is not importable in the app today regardless of naming.** `ModelArchitecture.whisper` doesn't exist, `detectArchitecture()` has no whisper case (so detection returns null → "architecture detection failed", not a false match), and there's no offline-recognizer case to build one even if the architecture were picked manually. All of that is `openspec/changes/whisper-asr-compatibility/` — this archive is shaped to match what that change's detector is *designed* to recognize (`<prefix>encoder.onnx` + `<prefix>decoder.onnx`, no joiner, `<prefix>tokens.txt`) once implemented, including the resolver's tokens-matching gap the design doc now calls out as a second touchpoint alongside the detector.

## What each piece does

| File | Purpose |
|---|---|
| `setup.sh` | Isolated venv: torch (CPU), openai-whisper, transformers, onnx, onnxruntime, sherpa-onnx |
| `download_model.sh <name>` | Pulls the HF checkpoint files into `models/<name>/` |
| `convert_state_dict.py` | Bridges HF's key naming to OpenAI's `whisper.model.Whisper` format, **verified with a numeric parity check**, not just "ran without error" |
| `export-onnx-torch2.9.patch` | Patch for sherpa-onnx's `scripts/whisper/export-onnx.py` — see "Exporter gotcha" below |
| `shrink_decoder.py` | Fixes a real gap in the script's own int8 quantization step — see "Quantization sweet spot" below |
| `fetch_test_audio.py` | Pulls two real (non-synthetic) Norwegian speech samples with ground-truth transcripts |
| `sanity_check.py` | Runs a converted model against audio via sherpa-onnx's Python bindings |
| `package_archive.sh` | Bundles the quantized trio into a `.tar.gz` the app's import flow can extract — see "Packaging for the app" |
| `convert.sh` | Runs conversion through quantization in order for one model name |

## Why the HF→OpenAI bridge needs a parity check, not just "no exception"

The key mapping (`convert_state_dict.py`) is a pure rename — same weights, same architecture — so a correct mapping should reproduce the original model's output *exactly*, not approximately. The script asserts `max abs diff < 1e-3` against the original HF model on identical random input; in practice this comes out as `0.0` (bit-exact), which is the actual bar for "the mapping has no bugs," not a probabilistic sanity check.

As an independent cross-check: [`NbAiLab/nb-whisper`](https://github.com/NbAiLab/nb-whisper)'s own `convert-h5-to-ggml.py` (a copy of whisper.cpp's community conversion script, used for their GGML/whisper.cpp exports) uses the identical target key scheme — `attn.query/key/value/out`, `cross_attn.*`, `mlp.0`/`mlp.2`, `ln_post`, `positional_embedding`, `token_embedding.weight` — independently confirming this is the standard OpenAI-format mapping, not something specific to this experiment. (Their script's decoder cross-attention key-projection mapping is handled via a special-cased branch rather than a plain dict entry — looks like a workaround for how they strip the `self_attn.`/`encoder_attn.` prefix, not a bug, but it threw me off on first read.) NbAiLab's two other whisper-related repos, `nb-whisper-jax` (TPU inference speedup) and `nb.whisperX` (a WhisperX fork for diarization/timestamps), have nothing relevant to format conversion. `distil-whisper` in their org is a bare mirror of the generic HuggingFace project, not NbAiLab-specific tooling.

## Exporter gotcha

Torch ≥2.9 defaults `torch.onnx.export()` to the newer `torch.export`-based ("dynamo") exporter. It doesn't propagate sherpa-onnx's `dynamic_axes` correctly through this script's custom KV-cache decoder wrapper — **it exports without error**, but the resulting decoder graph bakes in a static shape from trace time and throws an onnxruntime `Reshape` error on the very first real inference call. That's a failure mode that only shows up when you *run* the model, which is why `sanity_check.py` against real audio is part of this pipeline, not an afterthought.

`export-onnx-torch2.9.patch` forces the legacy exporter (`dynamo=False, external_data=False`) on both `torch.onnx.export()` calls, and generalizes the script's `--model` argument to accept any name for which a local `<name>.pt` exists (originally it only accepted a hardcoded list of official OpenAI/icefall model names).

## Quantization "sweet spot"

The export script's own `quantize_dynamic(op_types_to_quantize=["MatMul"])` step quantizes 72 of the decoder's 73 `MatMul` weights cleanly (~4x smaller each). The 73rd — the tied token-embedding / output-projection matrix, at 51,865×512 also the single largest tensor in the whole model (~106MB fp32) — doesn't shrink at all:

| | fp32 | naive int8 |
|---|---|---|
| encoder | 90.7MB | 27.6MB |
| decoder | 187.4MB | 124.6MB *(barely smaller)* |

**Root cause** (confirmed by inspecting the exported graph, not guessed): onnxruntime's dynamic quantizer only recognizes `MatMul(activation, weight)` — weight as the *second* operand, matching how `nn.Linear` normally traces. This decoder's tied output-projection computes `MatMul(token_embedding.weight, activation)` instead — weight *first* — which the quantizer's pattern matcher doesn't treat as a quantizable weight at all. (An initial theory — that an intervening `Identity` node from the export code's `.to(x.dtype)` was blocking detection — turned out to be a coincidence: removing the `Identity` node changed nothing.)

`shrink_decoder.py` downcasts just that one tensor to fp16, restoring fp32 via a `Cast` node at the matmul boundary, rather than hand-rolling proper int8 weight-only quantization for it (real risk: scale/zero-point plumbing to get subtly wrong, for one tensor). Verified **numerically identical transcription output** to the int8-only version on both test clips:

| | Size | vs. fp32 |
|---|---|---|
| encoder int8 | 27.6MB | -70% |
| decoder int8 + fp16 embedding | 77.5MB | -59% |
| **Total** | **~105MB** | **-63%** (vs. naive int8's -46%) |

If you need the last few MB, proper int8 weight-only quantization for that one tensor is possible — just not worth the added complexity for what it buys here.

## Validate on real speech, not synthetic TTS

Early testing used `espeak-ng`-synthesized Norwegian audio and got visibly garbled output that looked like a conversion bug. It wasn't: running the *same* clip through the original, unconverted HF PyTorch model produced similarly rough output — the robotic, formant-synthesized audio is simply unlike anything in this model's training distribution (real broadcast/parliamentary recordings), and greedy decoding is sensitive enough to numeric noise near its confidence edge that fp32 vs. int8 can diverge onto entirely different sentences on marginal input. It's not a representative test either way — don't use TTS output to validate an ASR conversion.

`fetch_test_audio.py` pulls two real, legitimately-licensed sources instead, no full dataset download required:

- **FLEURS** (`google/fleurs`, `nb_no` config) — clean single-speaker read speech, out-of-domain for this model.
- **NPSC** (`NbAiLab/NPSC`, via its `refs/convert/parquet` branch) — actual Norwegian Parliament recordings, the exact corpus NbAiLab's `nb-whisper`/`nb-wav2vec2` models are fine-tuned on, i.e. in-domain.

Both transcribed essentially perfectly in testing (NPSC: exact match including restored punctuation; FLEURS: one near-miss word out of ~20 — "hår" (hair) heard as a phonetically similar word).

`sanity_check.py` always forces `language="no"` explicitly — sherpa-onnx's whisper binding auto-detects language only when this is left empty, and auto-detection on a single-language fine-tune is unreliable on marginal audio (the same failure mode observed firsthand with unrelated multilingual models like Omnilingual ASR / Parakeet, where a wrong language lock-in produces near-useless output). Never ship a whisper config with an empty `language`.

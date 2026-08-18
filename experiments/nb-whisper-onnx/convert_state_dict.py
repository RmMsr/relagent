#!/usr/bin/env python3
"""Convert a HuggingFace `transformers`-format Whisper checkpoint into the
OpenAI `whisper.model.Whisper` state-dict format that sherpa-onnx's
scripts/whisper/export-onnx.py expects (a .pt file containing
{"dims": {...}, "model_state_dict": {...}}).

The key mapping is a pure rename (same weights, same architecture, no
re-derivation), so this script verifies it with a numeric parity check
against the original HF model rather than trusting "no exception raised".

Usage:
    ./venv/bin/python3 convert_state_dict.py models/nb-whisper-base
"""
import argparse
import json
import re
import sys
from pathlib import Path

import torch
from safetensors.torch import load_file
from transformers import WhisperForConditionalGeneration

import whisper
from whisper.model import ModelDimensions


def hf_key_to_openai_key(key: str) -> str:
    assert key.startswith("model."), key
    k = key[len("model."):]

    k = k.replace("encoder.embed_positions.weight", "encoder.positional_embedding")
    k = k.replace("decoder.embed_positions.weight", "decoder.positional_embedding")
    k = k.replace("decoder.embed_tokens.weight", "decoder.token_embedding.weight")
    k = k.replace("encoder.layer_norm.", "encoder.ln_post.")
    k = k.replace("decoder.layer_norm.", "decoder.ln.")

    k = re.sub(r"\.layers\.(\d+)\.", r".blocks.\1.", k)

    k = k.replace(".self_attn.q_proj", ".attn.query")
    k = k.replace(".self_attn.k_proj", ".attn.key")
    k = k.replace(".self_attn.v_proj", ".attn.value")
    k = k.replace(".self_attn.out_proj", ".attn.out")
    k = k.replace(".self_attn_layer_norm", ".attn_ln")

    k = k.replace(".encoder_attn.q_proj", ".cross_attn.query")
    k = k.replace(".encoder_attn.k_proj", ".cross_attn.key")
    k = k.replace(".encoder_attn.v_proj", ".cross_attn.value")
    k = k.replace(".encoder_attn.out_proj", ".cross_attn.out")
    k = k.replace(".encoder_attn_layer_norm", ".cross_attn_ln")

    k = k.replace(".fc1", ".mlp.0")
    k = k.replace(".fc2", ".mlp.2")
    k = k.replace(".final_layer_norm", ".mlp_ln")

    return k


def convert(repo_dir: Path, out_path: Path, tolerance: float) -> None:
    with open(repo_dir / "config.json") as f:
        cfg = json.load(f)

    dims = ModelDimensions(
        n_mels=cfg["num_mel_bins"],
        n_audio_ctx=cfg["max_source_positions"],
        n_audio_state=cfg["d_model"],
        n_audio_head=cfg["encoder_attention_heads"],
        n_audio_layer=cfg["encoder_layers"],
        n_vocab=cfg["vocab_size"],
        n_text_ctx=cfg["max_target_positions"],
        n_text_state=cfg["d_model"],
        n_text_head=cfg["decoder_attention_heads"],
        n_text_layer=cfg["decoder_layers"],
    )
    print("ModelDimensions:", dims)

    hf_sd = load_file(repo_dir / "model.safetensors")
    print(f"Loaded {len(hf_sd)} tensors from HF safetensors")

    openai_sd = {}
    for k, v in hf_sd.items():
        if not k.startswith("model."):
            print("  skipping non-model key:", k)
            continue
        openai_sd[hf_key_to_openai_key(k)] = v.clone()

    oa_model = whisper.model.Whisper(dims)
    missing, unexpected = oa_model.load_state_dict(openai_sd, strict=False)
    if unexpected:
        print("FAIL: unexpected keys in mapped state dict:", unexpected)
        sys.exit(1)
    bad_missing = [m for m in missing if "mask" not in m]
    if bad_missing:
        # only the non-persistent causal-mask buffer may legitimately be absent
        print("FAIL: unexpected missing keys:", bad_missing)
        sys.exit(1)

    # --- numerical parity check against the original HF model ---
    hf_model = WhisperForConditionalGeneration.from_pretrained(str(repo_dir))
    hf_model.eval()
    oa_model.eval()

    torch.manual_seed(0)
    mel = torch.randn(1, dims.n_mels, 3000)
    tokens = torch.tensor([[cfg["decoder_start_token_id"], 50259, 50359, 50363]])

    with torch.no_grad():
        oa_logits = oa_model.decoder(tokens, oa_model.encoder(mel))
        hf_logits = hf_model(input_features=mel, decoder_input_ids=tokens).logits

    diff = (oa_logits - hf_logits).abs().max().item()
    print("max abs diff vs HF model:", diff)
    if diff > tolerance:
        print(f"FAIL: parity check exceeds tolerance ({tolerance}) — mapping has a bug")
        sys.exit(1)
    print("PASS: parity check within tolerance")

    torch.save({"dims": dims.__dict__, "model_state_dict": oa_model.state_dict()}, out_path)
    print("Saved OpenAI-format checkpoint to", out_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo_dir", type=Path, help="Directory from download_model.sh")
    parser.add_argument("--out", type=Path, default=None, help="Output .pt path (default: <repo_dir name>.pt in cwd)")
    parser.add_argument("--tolerance", type=float, default=1e-3)
    args = parser.parse_args()

    out = args.out or Path(f"{args.repo_dir.name}.pt")
    convert(args.repo_dir, out, args.tolerance)

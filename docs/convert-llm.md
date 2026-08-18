# Converting a model from Hugging Face to GGUF

Not every model on the [Hugging Face Hub](https://huggingface.co/models) is published in GGUF format. If you found a promising one that only ships `safetensors` weights, you can convert and quantize it yourself with [llama.cpp](https://github.com/ggml-org/llama.cpp).

No GPU is required for conversion or quantization. Budget roughly 1.2x the model's full-precision size in RAM, and about 2x that size in free disk space (original download plus converted file).

Download the source model with either of these tools — both work fine, pick whichever you have installed:

- [huggingface-cli](https://huggingface.co/docs/huggingface_hub/guides/cli) — Python-based, ships with `huggingface_hub`
- [hfdownloader](https://github.com/bodaay/HuggingFaceModelDownloader) — single Go binary, no Python needed, faster on large multi-file repos via concurrent multipart transfers

```shell
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

huggingface-cli download <org>/<model-name> --local-dir ./models/<model-name>
# or: hfdownloader download <org>/<model-name>

# Convert to an unquantized GGUF (F16). llama.cpp ships a pyproject.toml,
# so `uv run` installs its pinned dependencies into an isolated environment
# and exposes the console script below, no manual pip install needed.
uv run llama-convert-hf-to-gguf ./models/<model-name> \
  --outfile ./models/<model-name>.f16.gguf

# Quantize down to a size that fits your hardware, e.g. Q4_K_M
./build/bin/llama-quantize ./models/<model-name>.f16.gguf ./models/<model-name>.Q4_K_M.gguf Q4_K_M
```

**If conversion fails to load the tokenizer** on a very recently released model, llama.cpp's bundled `transformers` version may be too old to know about it. Its `pyproject.toml` pins an exact version, so bump it in your local clone rather than fighting the pin:

```toml
# llama.cpp/pyproject.toml
[tool.uv]
override-dependencies = ["transformers>=4.58"]
```

`uv run` picks this up automatically on the next invocation, no extra flags needed.

The resulting `.gguf` file loads like any other local model: drop it into LM Studio's model folder, `ollama create` it with a Modelfile, or point `llama.cpp server` at it directly.

## Picking a quantization

Each step down roughly scales file size (and VRAM) from the F16 baseline:

| Quant     | Size vs. F16 | Notes                                    |
| --------- | ------------ | ----------------------------------------- |
| Q8_0      | ~53%         | Near-lossless, still large                |
| Q5_K_M    | ~35%         | Very close to F16 quality                 |
| Q4_K_M    | ~30%         | Best size/quality tradeoff for most models |
| Q3_K_M    | ~23%         | Noticeable quality loss                   |

**Recommendations:**

1. **Q4_K_M** — default choice; fits most consumer GPUs and holds up well in practice.
2. **Q5_K_M** — if you have the VRAM to spare and want output closer to the unquantized model.
3. **Q8_0** — only for smaller models where you can afford the size and want quality as close to F16 as possible.

**Note**: Mixture-of-experts models keep every expert in memory even though only a few are active per token. Size your RAM/VRAM budget against the full parameter count, not the "active parameters" figure some model names advertise (for example, an "A4B" suffix).


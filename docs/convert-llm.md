# Converting a model from Hugging Face to GGUF

Not every model on the [Hugging Face Hub](https://huggingface.co/models) is published in GGUF format. If you found a promising one that only ships `safetensors` weights, you can convert and quantize it yourself with [llama.cpp](https://github.com/ggml-org/llama.cpp).

**Before downloading anything**, check that llama.cpp's `convert_hf_to_gguf.py` supports the model's architecture (the `architectures` field in the model's `config.json`). New model families can take weeks or months to gain support.

No GPU is required for conversion or quantization. Budget roughly 1.2x the model's full-precision size in RAM, and about 2x that size in free disk space (original download plus converted file).

```shell
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

# Download the source model (needs huggingface_hub or git-lfs)
huggingface-cli download <org>/<model-name> --local-dir ./models/<model-name>

# Convert to an unquantized GGUF (F16). `uv run --with-requirements` installs
# the converter's dependencies into an isolated, ephemeral environment
# instead of polluting your system Python.
uv run --with-requirements requirements.txt python convert_hf_to_gguf.py \
  ./models/<model-name> --outfile ./models/<model-name>.f16.gguf

# Build llama.cpp's quantize tool
cmake -B build
cmake --build build --target llama-quantize -j

# Quantize down to a size that fits your hardware, e.g. Q4_K_M
./build/bin/llama-quantize ./models/<model-name>.f16.gguf ./models/<model-name>.Q4_K_M.gguf Q4_K_M
```

For the download step, [hfdownloader](https://github.com/bodaay/HuggingFaceModelDownloader) is a good alternative to `huggingface-cli`: it's a single Go binary (no Python environment needed) and downloads large multi-file repos faster via concurrent multipart transfers.

```shell
bash <(curl -sSL https://g.bodaay.io/hfd) install /usr/local/bin
hfdownloader download <org>/<model-name>
```

The resulting `.gguf` file loads like any other local model: drop it into LM Studio's model folder, `ollama create` it with a Modelfile, or point `llama.cpp server` at it directly.

**Note**: Mixture-of-experts models keep every expert in memory even though only a few are active per token. Size your RAM/VRAM budget against the full parameter count, not the "active parameters" figure some model names advertise (for example, an "A4B" suffix).


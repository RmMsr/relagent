#!/usr/bin/env bash
# Creates an isolated venv with everything the rest of this experiment needs.
set -euo pipefail
cd "$(dirname "$0")"

python3 -m venv venv
./venv/bin/pip install --upgrade pip -q
./venv/bin/pip install -q torch --index-url https://download.pytorch.org/whl/cpu
./venv/bin/pip install -q \
  openai-whisper transformers huggingface_hub onnx onnxruntime \
  safetensors sherpa-onnx pyarrow numpy

echo "done: ./venv/bin/python3 is ready"

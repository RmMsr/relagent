#!/usr/bin/env bash
# Downloads an NbAiLab Whisper checkpoint (HF transformers format) into
# ./models/<name>/. Usage: ./download_model.sh nb-whisper-base
set -euo pipefail
cd "$(dirname "$0")"

MODEL="${1:?Usage: $0 <nb-whisper-name, e.g. nb-whisper-base>}"
DEST="models/$MODEL"
mkdir -p "$DEST"

FILES=(
  config.json generation_config.json model.safetensors
  preprocessor_config.json tokenizer.json vocab.json merges.txt
  normalizer.json special_tokens_map.json tokenizer_config.json
  added_tokens.json
)

for f in "${FILES[@]}"; do
  echo "fetching $f"
  curl -sL "https://huggingface.co/NbAiLab/$MODEL/resolve/main/$f" -o "$DEST/$f"
done

echo "done: $DEST"

#!/usr/bin/env bash
# End-to-end: download an NbAiLab whisper checkpoint, convert it to OpenAI
# format, export to sherpa-onnx ONNX, quantize, and shrink the decoder.
# Usage: ./convert.sh nb-whisper-base
set -euo pipefail
cd "$(dirname "$0")"

MODEL="${1:?Usage: $0 <nb-whisper-name, e.g. nb-whisper-base>}"
PY=./venv/bin/python3
OUT="out/$MODEL"

[ -x "$PY" ] || { echo "run ./setup.sh first"; exit 1; }

echo "== 1/5: download HF checkpoint =="
./download_model.sh "$MODEL"

echo "== 2/5: convert HF -> OpenAI state dict (with parity check) =="
mkdir -p "$OUT"
"$PY" convert_state_dict.py "models/$MODEL" --out "$OUT/$MODEL.pt"

echo "== 3/5: fetch + patch sherpa-onnx's export script =="
if [ ! -f "$OUT/export-onnx.py" ]; then
  curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/scripts/whisper/export-onnx.py" -o "$OUT/export-onnx.py"
  patch "$OUT/export-onnx.py" < export-onnx-torch2.9.patch
fi

echo "== 4/5: export to ONNX =="
( cd "$OUT" && ../../venv/bin/python3 export-onnx.py --model "$MODEL" )

echo "== 5/5: shrink the decoder's fp32-stuck embedding matrix =="
"$PY" shrink_decoder.py "$OUT/$MODEL-decoder.int8.onnx" -o "$OUT/$MODEL-decoder.int8.fp16emb.onnx"

echo
echo "done. Ship these three files as the model package:"
echo "  $OUT/$MODEL-encoder.int8.onnx"
echo "  $OUT/$MODEL-decoder.int8.fp16emb.onnx"
echo "  $OUT/$MODEL-tokens.txt"
echo
echo "Validate with real audio:"
echo "  $PY fetch_test_audio.py"
echo "  $PY sanity_check.py --encoder $OUT/$MODEL-encoder.int8.onnx --decoder $OUT/$MODEL-decoder.int8.fp16emb.onnx --tokens $OUT/$MODEL-tokens.txt --all"

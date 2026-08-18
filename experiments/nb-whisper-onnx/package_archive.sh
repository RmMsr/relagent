#!/usr/bin/env bash
# Packages the quantized encoder/decoder/tokens trio from ./convert.sh into a
# .tar.gz the app's local-model-import flow can extract (it auto-detects
# .tar.bz2 / .tar.gz / .tgz / .zip / .tar via magic bytes — gzip is used here
# purely because it needs no extra tooling beyond `tar`).
#
# Filenames are kept exactly as sherpa-onnx's export script produces them
# (<model>-encoder.onnx / <model>-decoder... / <model>-tokens.txt). That's a
# deliberate choice, not an oversight — see README.md "Packaging for the app".
#
# Usage: ./package_archive.sh nb-whisper-base
set -euo pipefail
cd "$(dirname "$0")"

MODEL="${1:?Usage: $0 <model name, e.g. nb-whisper-base>}"
SRC="out/$MODEL"
STAGE="out/${MODEL}-package/$MODEL"
ARCHIVE="out/${MODEL}.tar.gz"

ENCODER="$SRC/$MODEL-encoder.int8.onnx"
DECODER="$SRC/$MODEL-decoder.int8.fp16emb.onnx"
TOKENS="$SRC/$MODEL-tokens.txt"

for f in "$ENCODER" "$DECODER" "$TOKENS"; do
  [ -f "$f" ] || { echo "missing $f — run ./convert.sh $MODEL first"; exit 1; }
done

rm -rf "out/${MODEL}-package"
mkdir -p "$STAGE"
cp "$ENCODER" "$DECODER" "$TOKENS" "$STAGE/"

( cd "out/${MODEL}-package" && tar czf "../../$ARCHIVE" "$MODEL" )
rm -rf "out/${MODEL}-package"

echo "done: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo
echo "Contents:"
tar tzf "$ARCHIVE"
echo
echo "NOTE: importing this in the app today will show 'architecture detection"
echo "failed' — ModelArchitecture.whisper doesn't exist yet. See"
echo "openspec/changes/whisper-asr-compatibility/. This archive is already"
echo "shaped for what that change's detector is designed to recognize."

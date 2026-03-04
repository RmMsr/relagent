#!/usr/bin/env sh
# voice-catalog — Relagent voice model catalog manager
#
# Usage:
#   bin/voice-catalog [--discover] [--eval] [OPTIONS]
#   bin/voice-catalog --help

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/../tools/voice_catalog"

# Detect CPU architecture for native library selection.
case "$(uname -m)" in
  x86_64)  ARCH="x64" ;;
  aarch64) ARCH="aarch64" ;;
  *)       ARCH="x64" ;;
esac

# Use a project-local pub cache so all packages (including native .so files)
# stay within the repository directory and never reach into ~/.pub-cache.
export PUB_CACHE="$TOOLS_DIR/.pub-cache"

# Resolve dependencies on first run (or when the local cache is missing).
if [ ! -d "$PUB_CACHE/hosted" ]; then
  echo "First run: downloading voice-catalog dependencies to tools/voice_catalog/.pub-cache/ ..."
  (cd "$TOOLS_DIR" && dart pub get)
fi

# Locate sherpa_onnx native libraries inside the project-local pub cache.
# Both libsherpa-onnx-c-api.so and libonnxruntime.so must be on LD_LIBRARY_PATH.
_find_sherpa_lib_dir() {
  find "$PUB_CACHE" -path "*/sherpa_onnx_linux-*/linux/$ARCH/libsherpa-onnx-c-api.so" 2>/dev/null \
    | sort --version-sort --reverse \
    | head -1 \
    | xargs -r dirname
}

SHERPA_LIB_DIR="$(_find_sherpa_lib_dir || true)"
if [ -n "$SHERPA_LIB_DIR" ]; then
  export LD_LIBRARY_PATH="$SHERPA_LIB_DIR:${LD_LIBRARY_PATH:-}"
  export VOICE_CATALOG_SHERPA_LIB_DIR="$SHERPA_LIB_DIR"
else
  echo "Warning: sherpa_onnx native library not found." >&2
  echo "  Try: rm -rf tools/voice_catalog/.pub-cache && bin/voice-catalog --help" >&2
  echo "  The evaluate phase will fail without the native library." >&2
fi

exec dart run "$TOOLS_DIR/bin/voice_catalog.dart" "$@"

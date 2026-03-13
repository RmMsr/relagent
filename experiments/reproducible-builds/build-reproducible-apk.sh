#!/usr/bin/env sh
# Build reproducible split-ABI release APKs.
#
# Creates a shallow git clone at a normalized path so that absolute paths
# embedded in libapp.so are identical across machines. Uses a project-local
# PUB_CACHE so cached package paths are deterministic.
#
# Environment variables (all optional):
#   BUILD_DIR    – normalized build directory
#                  default: /tmp/build/org.venkado.relagent
#   FLUTTER_BIN  – path to the flutter binary
#                  default: auto-detected (fvm flutter | flutter)
#   OUTPUT_DIR   – where to place the final APKs
#                  default: apps/build/local
#   PLATFORMS    – comma-separated target platforms
#                  default: android-arm,android-arm64,android-x64

set -eu

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BUILD_DIR="${BUILD_DIR:-/tmp/build/org.venkado.relagent}"
PLATFORMS="${PLATFORMS:-android-arm,android-arm64,android-x64}"

if [ -z "${FLUTTER_BIN:-}" ]; then
    if command -v fvm >/dev/null 2>&1; then
        FLUTTER_BIN="fvm flutter"
    elif command -v flutter >/dev/null 2>&1; then
        FLUTTER_BIN="flutter"
    else
        echo "Error: neither fvm nor flutter found in PATH" >&2
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$BUILD_DIR/apps"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/apps/build/local}"
APK_DIR="build/app/outputs/flutter-apk"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "==> $*"; }

# Map flutter platform names to APK ABI suffixes
apk_name_for_platform() {
    case "$1" in
        android-arm)   echo "app-armeabi-v7a-release.apk" ;;
        android-arm64) echo "app-arm64-v8a-release.apk" ;;
        android-x64)   echo "app-x86_64-release.apk" ;;
        *) echo "Error: unknown platform $1" >&2; exit 1 ;;
    esac
}

output_name_for_platform() {
    case "$1" in
        android-arm)   echo "relagent-armeabi-v7a-release.apk" ;;
        android-arm64) echo "relagent-arm64-v8a-release.apk" ;;
        android-x64)   echo "relagent-x86_64-release.apk" ;;
        *) echo "Error: unknown platform $1" >&2; exit 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# Warn if worktree has uncommitted changes
if ! git -C "$REPO_ROOT" diff --quiet HEAD 2>/dev/null || \
   ! git -C "$REPO_ROOT" diff --quiet --cached HEAD 2>/dev/null; then
    echo "WARNING: repository has uncommitted changes — build uses HEAD only" >&2
fi

log "Repository root : $REPO_ROOT"
log "Build directory : $BUILD_DIR"
log "Flutter binary  : $FLUTTER_BIN"
log "Output directory: $OUTPUT_DIR"
log "Platforms       : $PLATFORMS"

# Prepare build directory
if [ -d "$BUILD_DIR" ]; then
    log "Removing previous build directory"
    rm -rf "$BUILD_DIR"
fi

# Shallow clone from HEAD — only committed files, no worktree noise
log "Cloning HEAD to $BUILD_DIR"
git clone --depth 1 "file://$REPO_ROOT" "$BUILD_DIR"

cd "$APP_DIR"

# config.json is gitignored; create from template
cp assets/config.template.json assets/config.json
log "Created assets/config.json from template"

# Use project-local pub cache for deterministic paths
export PUB_CACHE="$REPO_ROOT/.pub-cache"
log "PUB_CACHE=$PUB_CACHE"

# Suppress analytics
$FLUTTER_BIN config --no-analytics 2>/dev/null || true

# Resolve dependencies
log "Resolving dependencies"
$FLUTTER_BIN pub get --enforce-lockfile

# Build split-ABI release APKs
log "Building release APKs"
$FLUTTER_BIN build apk \
    --release \
    --split-per-abi \
    --target-platform="$PLATFORMS"

# Copy outputs
mkdir -p "$OUTPUT_DIR"
IFS=','
for platform in $PLATFORMS; do
    apk_name="$(apk_name_for_platform "$platform")"
    out_name="$(output_name_for_platform "$platform")"
    apk_path="$APK_DIR/$apk_name"

    if [ ! -f "$apk_path" ]; then
        echo "Error: APK not found at $apk_path" >&2
        exit 1
    fi

    cp "$apk_path" "$OUTPUT_DIR/$out_name"
    log "Built: $OUTPUT_DIR/$out_name"
done
unset IFS

# Verify embedded paths point to BUILD_DIR, not the original source
log "Checking libapp.so for embedded paths"
CHECK_DIR="/tmp/apk_check_$$"
# Use the first APK for the check (paths are the same in all ABIs)
FIRST_PLATFORM="$(echo "$PLATFORMS" | cut -d, -f1)"
FIRST_APK="$APK_DIR/$(apk_name_for_platform "$FIRST_PLATFORM")"
mkdir -p "$CHECK_DIR"
unzip -q -o "$FIRST_APK" 'lib/*/libapp.so' -d "$CHECK_DIR"
FOUND_PATHS="$(find "$CHECK_DIR" -name libapp.so -exec strings {} + | grep '^file:///' || true)"
rm -rf "$CHECK_DIR"
if [ -n "$FOUND_PATHS" ]; then
    echo "    Embedded paths (should reference BUILD_DIR):"
    echo "$FOUND_PATHS" | sed 's/^/    /'
else
    echo "    No file:/// paths found in libapp.so"
fi

# Clean up
log "Cleaning up build directory"
rm -rf "$BUILD_DIR"

log "Done"

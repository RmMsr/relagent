#!/usr/bin/env sh

set -e

BUILD_DIR=/tmp/build/org.venkado.relagent
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -d "$REPO_ROOT"/apps/build ]; then
    rm -rf "$REPO_ROOT"/apps/build
fi

if [ -d "$BUILD_DIR"/apps/build ]; then
    mv "$BUILD_DIR"/apps/build "$REPO_ROOT"/apps/
    echo "Collected artifacts in repo's apps/"
else
    echo "No builds found"
fi

if [ -d "$BUILD_DIR/apps/.pub-cache" ]; then
    rm -rf "$REPO_ROOT/.pub-cache"
    cp -a "$BUILD_DIR/apps/.pub-cache" "$REPO_ROOT/.pub-cache"
fi

rm -rf "$BUILD_DIR"

echo "Flutter source deleted: ${BUILD_DIR}"

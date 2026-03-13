#!/usr/bin/env sh

# The real file pathes leak into the compiled packages. Therefore all builds
# should be created from the same directory.

set -e

BUILD_DIR=/tmp/build/org.venkado.relagent
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

git clone --depth 1 "file://$REPO_ROOT" "$BUILD_DIR"

cd "$BUILD_DIR"/apps || exit

echo "Flutter source checked out to: ${PWD}"

cp assets/config.template.json assets/config.json

flutter pub get --enforce-lockfile

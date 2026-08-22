#!/usr/bin/env sh
# Update the pinned Flutter SDK version across the repo.
# Usage: sync-flutter-version.sh [<version>]
#   <version>  Target Flutter version (e.g. 3.42.0). Omit to use the latest stable release.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v fvm >/dev/null 2>&1; then
  echo "fvm is required (see CLAUDE.md environment setup)" >&2
  exit 1
fi

VERSION="$1"
if [ -z "$VERSION" ]; then
  printf '=== Resolving latest stable Flutter release ===\n'
  VERSION="$(fvm api releases --filter-channel stable --limit 1 --compress | \
    python3 -c 'import json,sys; print(json.load(sys.stdin)["versions"][0]["version"])')"
fi

printf '\n=== Pinning Flutter %s (.fvmrc) ===\n' "$VERSION"
(cd "$REPO_ROOT" && fvm use "$VERSION" --force)

if [ -n "$(tail -c1 "$REPO_ROOT/.fvmrc")" ]; then
  printf '\n' >> "$REPO_ROOT/.fvmrc"
fi

printf '\n=== Resolving Dart SDK bundled with Flutter %s ===\n' "$VERSION"
DART_VERSION="$(cd "$REPO_ROOT" && fvm flutter --version | sed -n 's/.*Dart \([0-9][0-9.]*\).*/\1/p')"
if [ -z "$DART_VERSION" ]; then
  echo "Failed to resolve bundled Dart SDK version from 'fvm flutter --version'" >&2
  exit 1
fi

printf '\n=== Updating apps/pubspec.yaml environment.flutter and environment.sdk ===\n'
sed -i.bak -E "s/^(  flutter: ).*/\1${VERSION}/" "$REPO_ROOT/apps/pubspec.yaml"
sed -i.bak -E "s/^(  sdk: ).*/\1${DART_VERSION}/" "$REPO_ROOT/apps/pubspec.yaml"
rm -f "$REPO_ROOT/apps/pubspec.yaml.bak"

if ! grep -q "^  flutter: ${VERSION}\$" "$REPO_ROOT/apps/pubspec.yaml"; then
  echo "Failed to update apps/pubspec.yaml environment.flutter (expected line not found after sed)" >&2
  exit 1
fi

if ! grep -q "^  sdk: ${DART_VERSION}\$" "$REPO_ROOT/apps/pubspec.yaml"; then
  echo "Failed to update apps/pubspec.yaml environment.sdk (expected line not found after sed)" >&2
  exit 1
fi

printf '\n=== Updating .gitlab-ci.yml FLUTTER_VERSION ===\n'
sed -i.bak -E "s/^(  FLUTTER_VERSION: \")[^\"]*(\")/\1${VERSION}\2/" "$REPO_ROOT/.gitlab-ci.yml"
rm -f "$REPO_ROOT/.gitlab-ci.yml.bak"

if ! grep -q "^  FLUTTER_VERSION: \"${VERSION}\"\$" "$REPO_ROOT/.gitlab-ci.yml"; then
  echo "Failed to update .gitlab-ci.yml FLUTTER_VERSION (expected line not found after sed)" >&2
  exit 1
fi

printf '\n=== Refreshing pub dependencies against the new SDK ===\n'
(cd "$REPO_ROOT/apps" && fvm flutter pub get)

printf '\nFlutter pinned to %s (with Dart %s) in .fvmrc, apps/pubspec.yaml, and .gitlab-ci.yml.\n' "$VERSION" "$DART_VERSION"
printf 'CI will rebuild+publish flutter-ci:%s once these are committed and pushed.\n' "$VERSION"
printf 'Review the diff, run tests, then commit .fvmrc, apps/pubspec.yaml, apps/pubspec.lock, and .gitlab-ci.yml.\n'
printf 'If this is a minor/major Flutter bump, also re-check the Android SDK/NDK pins in ci/flutter.Containerfile against the new SDK'"'"'s packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt.\n'

#!/usr/bin/env sh
# Update all Python and Dart/Flutter dependencies in the repository.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

printf '=== Syncing Python dependencies ===\n'
(cd "$REPO_ROOT" && uv sync --upgrade)

# Determine flutter/dart commands: prefer fvm if available
if command -v fvm >/dev/null 2>&1; then
  FLUTTER="fvm flutter"
  DART="fvm dart"
else
  FLUTTER="flutter"
  DART="dart"
fi

# Dart-only projects
for pkg_dir in dart_packages/sherpa_voice tools/voice_catalog; do
  printf '\n=== Upgrading Dart dependencies in %s ===\n' "$pkg_dir"
  (cd "$REPO_ROOT/$pkg_dir" && $DART pub upgrade)
done

# Flutter project
printf '\n=== Upgrading Flutter dependencies in apps ===\n'
(cd "$REPO_ROOT/apps" && $FLUTTER pub upgrade)

printf '\nAll dependencies synced and up to date.\n'

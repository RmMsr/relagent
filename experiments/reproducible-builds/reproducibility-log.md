# Reproducibility Log

Tracking empirical verification of reproducible Android builds for Relagent.

**Target**: Unsigned, split-ABI, arm64-v8a release APK.
**Method**: Build twice from same source, compare with `cmp` and `diffoscope`.

---

## Attempt 1: Baseline — Unmodified Release Build

**Date**: 2026-03-10
**Changes**: None (current state of `release` buildType)
**Build command**: `fvm flutter build apk --release --split-per-abi --target-platform="android-arm64"`

### Results

**Outcome**: ✅ IDENTICAL on same machine (both incremental and after `flutter clean`)

**APK size**: 44.4 MB (462 ZIP entries)
**Timestamps**: All zeroed to `1981-01-01 01:01` ✅ (AGP 8.9.1)

**Files needing attention for cross-machine reproducibility:**

| File | Content | Action Needed |
|------|---------|---------------|
| `META-INF/version-control-info.textproto` | `generate_error_reason: NO_SUPPORTED_VCS_FOUND` | Disable via `vcsInfo.include = false` |
| `META-INF/.../app-metadata.properties` | `androidGradlePluginVersion=8.9.1` | Disable via `dependenciesInfo` |
| `assets/dexopt/baseline.prof` | Binary ART profile (205 bytes) | Disable ArtProfile tasks |
| `assets/dexopt/baseline.profm` | Binary profile metadata (65 bytes) | Disable ArtProfile tasks |
| `lib/arm64-v8a/libapp.so` | Contains absolute path: `file:///home/roman/projects/relagent-beodddaily/apps/.dart_tool/flutter_build/dart_plugin_registrant.dart` | Build from normalized path `/tmp/build` |

**Conclusion**: Same-machine builds already reproducible. Next step: eliminate cross-machine differences via gradle config changes.

---

## Attempt 2: Phase 1 Gradle Config Changes

**Date**: 2026-03-10
**Changes**:
- Disable VCS info (`vcsInfo.include = false`)
- Disable dependencies info (`dependenciesInfo { includeInApk = false }`)
- Disable baseline profile generation (ArtProfile tasks)
- Disable PNG crunching (`cruncherEnabled = false`)

### Results

**Outcome**: ✅ IDENTICAL after clean rebuild. 3 non-deterministic files removed.

**Files removed from APK:**
- `META-INF/version-control-info.textproto` — gone ✅
- `assets/dexopt/baseline.prof` — gone ✅
- `assets/dexopt/baseline.profm` — gone ✅

**Still present (deterministic):**
- `META-INF/com/android/build/gradle/app-metadata.properties` — contains only `androidGradlePluginVersion=8.9.1` (deterministic, pinned by settings.gradle.kts)

**Note**: `aaptOptions.cruncherEnabled` is not available in Kotlin DSL. Used `androidResources.noCompress += listOf("png")` instead, which prevents AAPT2 from re-compressing PNGs.

**Remaining for cross-machine**: `libapp.so` still contains `file:///home/roman/projects/relagent-beodddaily/apps/.dart_tool/...` — needs normalized build path.

---

## Attempt 3: Build Script with Normalized Path

**Date**: 2026-03-10
**Changes**: Created `bin/build-reproducible-apk.sh` — copies source to `/tmp/build/org.venkado.relagent`, sets `PUB_CACHE` to project-local dir, builds from normalized path.

### Results

**Outcome**: ✅ Two consecutive script runs produce IDENTICAL APKs.

**libapp.so embedded path**: `file:///tmp/build/org.venkado.relagent/apps/.dart_tool/flutter_build/dart_plugin_registrant.dart` — normalized as intended.

**Comparison with local build**: Only `lib/arm64-v8a/libapp.so` differs (expected — different build paths). All other 461 files are identical.

**Issues encountered**:
- `assets/config.json` is gitignored (created from template). Script now copies `config.template.json → config.json` if missing or a broken symlink.
- `cp -a` preserves symlinks which can break when copied to a different path. Using `cp -a` + explicit config.json handling rather than `cp -aL` to avoid dereferencing all symlinks.

**Script features**:
- POSIX compliant (`#!/usr/bin/env sh`), passes shellcheck
- Configurable `BUILD_DIR`, `FLUTTER_BIN`, `OUTPUT_DIR` via environment
- Auto-detects fvm vs flutter
- Verifies embedded paths in libapp.so after build
- Cleans up build directory on completion

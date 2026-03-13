# Reproducible Android Builds

Research and implementation guide for achieving F-Droid-verified reproducible builds of the Relagent Android APK.

**Scope**: Unsigned, split-ABI, arm64-v8a APK.

## Table of Contents

- [Goal](#goal)
- [What F-Droid Verifies](#what-f-droid-verifies)
- [Our Build Components](#our-build-components)
- [Sources of Non-Determinism](#sources-of-non-determinism)
- [Proven Flutter Recipes](#proven-flutter-recipes)
- [Implementation Plan](#implementation-plan)
- [Verification Workflow](#verification-workflow)
- [Tools Reference](#tools-reference)

---

## Goal

Produce bit-for-bit identical APKs when building from the same source commit, regardless of the build machine. The target standard is [F-Droid reproducible build verification](https://f-droid.org/docs/Reproducible_Builds/), which uses `apksigcopier` to copy a signature from a reference APK to the rebuilt one and checks that the result still verifies.

For v2/v3 APK signatures, the APKs must be **completely identical** apart from the signature block. This means every byte — ZIP metadata, file ordering, timestamps, native binaries — must match.

---

## What F-Droid Verifies

F-Droid's verification process:

1. Builds the APK from source using `fdroidserver` in a Debian-based VM.
2. Downloads the developer's signed APK (the "reference binary").
3. Copies the signature from the signed APK to the unsigned rebuild using `apksigcopier`.
4. Checks that the result verifies — if it does, the builds are reproducible.

The build environment is either:
- **F-Droid CI**: build path `/builds/fdroid/fdroiddata/build/<app.id>`
- **F-Droid buildserver**: build path `/home/vagrant/build/<app.id>`

The fdroiddata recipe can manipulate the build directory before building (e.g., `mv` to `/tmp/build`).

---

## Our Build Components

### Flutter SDK (pinned via FVM)

| Component | Current Value | Reproducibility Impact |
|-----------|--------------|----------------------|
| Flutter version | `3.41.4` (`.fvmrc`) | **CRITICAL** — Dart AOT compiler (`gen_snapshot`) embeds absolute source paths into `libapp.so`. Different Flutter versions produce different binaries. |
| Dart SDK | `>=3.9.2` (from Flutter) | Bundled with Flutter. `gen_snapshot` is the AOT compiler that produces `libapp.so`. |

**For F-Droid**: Flutter must be pinned as a git submodule (not FVM), so F-Droid's build system can use the exact same version. FVM is a developer convenience tool not available in F-Droid's build environment.

### Android Build Tools

| Component | Current Value | Reproducibility Impact |
|-----------|--------------|----------------------|
| Android Gradle Plugin | `8.9.1` (`settings.gradle.kts`) | ≥7.1.x ensures deterministic ZIP ordering and zeroed timestamps. ✅ |
| Kotlin | `2.1.0` (`settings.gradle.kts`) | Must match exactly between builds. |
| Gradle | `8.12.1` (`gradle-wrapper.properties`, with SHA-256 checksum) | Pinned with integrity check. ✅ |
| compileSdk / targetSdk | From `flutter.compileSdkVersion` / `flutter.targetSdkVersion` | Determined by Flutter SDK version. Platform revision differences can cause `platformBuildVersionName` mismatches. |
| NDK | From `flutter.ndkVersion` | Used for stripping native libs. Must match exactly. |
| Java | `VERSION_11` (`build.gradle.kts`) | JDK version must match. Different JDKs produce different `.dex` bytecode. |

### Native Libraries (`.so` files in APK)

These are the **hardest** component to make reproducible.

#### `libapp.so` — Dart AOT Snapshot (CRITICAL)

This is the compiled Dart application code, produced by `gen_snapshot`. It is the **primary source of reproducibility failures** for Flutter apps.

**Known issues:**
- **Embedded build paths**: The `app.dill` intermediate file passed to `gen_snapshot` contains absolute paths to all Dart source files (e.g., `file:///home/user/project/.dart_tool/flutter_build/dart_plugin_registrant.dart`). These paths are embedded in the compiled `libapp.so`. See [dart-lang/sdk#55282](https://github.com/dart-lang/sdk/issues/55282).
- **Verification**: Run `strings lib/arm64-v8a/libapp.so | grep file:` to see embedded paths.
- **Solution**: Build from an identical absolute path on all systems. F-Droid recipes use `mv` to `/tmp/build` to normalize the path.

#### `libflutter.so` — Flutter Engine

Pre-built binary distributed with the Flutter SDK. Identical across builds using the same Flutter version. ✅ (as long as Flutter is pinned exactly)

#### `libsherpa-onnx-c-api.so` + `libonnxruntime.so` — Sherpa ONNX

Distributed as pre-compiled binaries via the `sherpa_onnx_android` pub package (v1.12.28). These come from the pub.dev-hosted platform package, which bundles pre-built `.so` files for each architecture.

**Reproducibility**: Since these are downloaded from pub.dev with content hashes verified by `pubspec.lock`, they are deterministic as long as:
- `pubspec.lock` is committed (✅ already committed).
- `PUB_CACHE` is set to a project-local directory during build.
- The same version is resolved (pinned by lockfile).

#### Other native plugins

`record`, `flutter_secure_storage`, `audio_session`, `just_audio`, and other plugins with Android native code. These compile Kotlin/Java source via Gradle — generally reproducible with matching JDK and AGP versions.

### Dart Dependencies (pub packages)

All dependencies are pinned in `pubspec.lock` with SHA-256 content hashes. The lockfile ensures identical packages are fetched. ✅

The local path dependency `sherpa_voice` (at `../dart_packages/sherpa_voice`) is pure Dart and part of our source tree. ✅

### Build Outputs in APK

| File | Source | Deterministic? |
|------|--------|---------------|
| `classes.dex` | Java/Kotlin code compiled by D8/R8 | Usually yes with matching JDK. Can depend on CPU core count with some R8 versions. |
| `AndroidManifest.xml` | Compiled binary XML | Yes, if same build-tools version. |
| `resources.arsc` | Resource table | Yes, with AGP ≥3.4.x. ✅ |
| `res/**` | Compiled resources | Yes. Disable PNG crunching if needed. |
| `assets/**` | Flutter assets (config.json, icons, silero_vad.onnx, voice-models.json) | Byte-for-byte from source. ✅ |
| `lib/arm64-v8a/libapp.so` | Dart AOT snapshot | **NO** — contains embedded paths. Main challenge. |
| `lib/arm64-v8a/libflutter.so` | Flutter engine | Yes (from SDK). ✅ |
| `lib/arm64-v8a/libsherpa-onnx-*.so` | Sherpa ONNX native libs | Yes (from pub package). ✅ |
| `assets/dexopt/baseline.prof` | Baseline profile | Can be non-deterministic. May need to disable or sort. |
| `assets/dexopt/baseline.profm` | Baseline profile metadata | Non-deterministic. Needs sorting or disabling. |
| `META-INF/version-control-info.textproto` | VCS info (AGP ≥8.3) | Contains build path. Must disable. |

---

## Sources of Non-Determinism

### 1. Embedded Build Paths in `libapp.so` (CRITICAL)

The Dart AOT compiler embeds absolute file paths into `libapp.so`. This is the #1 blocker for Flutter reproducible builds.

**Detection:**
```bash
# Extract and compare paths from two builds
strings lib/arm64-v8a/libapp.so | grep 'file:'
```

**Example output showing the problem:**
```
file:///home/runner/work/myapp/myapp/.dart_tool/flutter_build/dart_plugin_registrant.dart
```
vs.
```
file:///tmp/build/.dart_tool/flutter_build/dart_plugin_registrant.dart
```

**Solution:** Build from the same absolute path. The F-Droid recipe moves the source to `/tmp/build` before building:
```bash
cd ..
mv org.venkado.relagent /tmp/build
pushd /tmp/build/
# ... build ...
popd
mv /tmp/build org.venkado.relagent
```

Our CI/release builds must also use `/tmp/build` as the build directory.

### 2. Embedded SDK Paths

The Android SDK path can also end up embedded in the build output.

**Solution:** Either use the same SDK path, or configure:
```bash
flutter config --android-sdk <path>
```

### 3. `PUB_CACHE` Path

The pub cache path is embedded in some build artifacts.

**Solution:** Set `PUB_CACHE` to a relative project-local directory:
```bash
export PUB_CACHE=$(pwd)/.pub-cache
```

### 4. VCS Info (`META-INF/version-control-info.textproto`)

AGP ≥8.3 (we use 8.9.1) embeds VCS info including the build directory path.

**Solution:** Disable it in `build.gradle.kts`:
```kotlin
buildTypes {
    release {
        vcsInfo.include = false
    }
}
```

### 5. Baseline Profiles (`baseline.prof` / `baseline.profm`)

Baseline profiles can be non-deterministic and depend on CPU core count.

**Solution:** Disable baseline profile generation:
```kotlin
tasks.whenTaskAdded {
    if (name.contains("ArtProfile")) {
        enabled = false
    }
}
```

Or sort them using `sort-baseline.py` from `reproducible-apk-tools`.

### 6. PNG Crunching

AAPT2 PNG optimization is non-deterministic.

**Solution:** Already mitigated since our PNGs are committed to source. Optionally disable:
```kotlin
android {
    aaptOptions {
        cruncherEnabled = false
    }
}
```

### 7. ZIP Ordering

Non-deterministic ZIP entry ordering can occur with older AGP or Android Studio builds.

**Solution:** AGP 8.9.1 (our version) handles this correctly. ✅ Build with `./gradlew` (not Android Studio).

### 8. R8/D8 DEX Compilation

DEX bytecode can vary with CPU core count in some R8 versions.

**Solution:** Use recent R8 (≥8.6.33). Our AGP 8.9.1 bundles a recent R8. If issues persist, limit to single core:
```bash
export CPUS_MAX=1
```

### 9. Dependencies Metadata (`dependencies.pb`)

AGP can embed dependency metadata in the APK (`META-INF/com/android/build/gradle/app-metadata.properties` and a `dependencies.pb` file). This metadata may include non-deterministic elements.

**Solution:** Disable in `build.gradle.kts`:
```kotlin
android {
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}
```

### 10. CRLF vs LF Line Endings

If upstream builds on Windows and F-Droid builds on Linux, `META-INF/services/*` files may have different line endings.

**Solution:** We build on Linux. Not an issue unless cross-platform builds are attempted. If needed, use `fix-newlines.py` from `reproducible-apk-tools`.

### 11. `apksigner` Version

`apksigner` from build-tools ≥35.0.0 produces APKs that `apksigcopier` cannot verify.

**Solution:** Use `apksigner` from build-tools 34.x for signing. For unsigned builds this is not an issue, but matters when the developer-signed APK is produced.

### 12. Native Library Stripping

AGP may strip `.so` files differently depending on NDK version and platform.

**Solution:** Pin NDK version exactly. If stripping causes issues:
```kotlin
android {
    packagingOptions {
        doNotStrip("**/*.so")
    }
}
```

---

## Proven Flutter Recipes

### LocalSend (Reference Implementation)

LocalSend is the most successful Flutter app with F-Droid reproducible builds. Key patterns from their [fdroiddata recipe](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/org.localsend.localsend_app.yml):

1. **Flutter as git submodule** — exact version pinning.
2. **Move to `/tmp/build`** — normalizes absolute paths in `libapp.so`.
3. **Project-local `PUB_CACHE`** — `export PUB_CACHE=$(pwd)/.pub-cache`.
4. **Split-per-ABI builds** — `--split-per-abi --target-platform="android-arm64"`.
5. **Separate version codes per ABI** — each architecture gets its own version code and build.
6. **Disable analytics** — `flutter config --no-analytics`.

```yaml
# Simplified LocalSend recipe pattern
prebuild:
  - cd ..
  - mv org.localsend.localsend_app /tmp/build
  - pushd /tmp/build/
  - export PUB_CACHE=$(pwd)/.pub-cache
  - submodules/flutter/bin/flutter config --no-analytics
  - submodules/flutter/bin/flutter pub get
  - popd
  - mv /tmp/build org.localsend.localsend_app
build:
  - cd ..
  - mv org.localsend.localsend_app /tmp/build
  - pushd /tmp/build/
  - export PUB_CACHE=$(pwd)/.pub-cache
  - submodules/flutter/bin/flutter build apk --release --split-per-abi --target-platform="android-arm64"
  - popd
  - mv /tmp/build org.localsend.localsend_app
```

### Flutter Server Box (Alternative Path Pattern)

Uses a different directory to match upstream CI path:
```yaml
sudo:
  - mkdir -p /home/runner
  - chown vagrant /home/runner
prebuild:
  - export repo=/home/runner/work/flutter_server_box
  - mkdir -p $repo
  - cd ..
  - mv tech.lolli.toolbox $repo/flutter_server_box
  - pushd $repo/flutter_server_box
  # ... build from upstream's CI path ...
```

### PicGuard (Resolved Example)

Initially failed because `libapp.so` contained GitHub Actions CI paths (`/home/runner/work/picguard/picguard`). Fixed by matching the path in the F-Droid recipe. See [F-Droid Forum discussion](https://forum.f-droid.org/t/flutter-app-not-reproducible/27462).

---

## Implementation Plan

### Phase 1: Build Configuration Changes

#### 1.1 Disable VCS Info and Dependencies Metadata

In `apps/android/app/build.gradle.kts`:
```kotlin
android {
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

buildTypes {
    release {
        vcsInfo.include = false
        // ... existing config ...
    }
}
```

#### 1.2 Disable PNG Crunching

In `apps/android/app/build.gradle.kts`:
```kotlin
android {
    aaptOptions {
        cruncherEnabled = false
    }
}
```

#### 1.3 Disable Baseline Profile Generation

In `apps/android/app/build.gradle.kts`:
```kotlin
tasks.whenTaskAdded {
    if (name.contains("ArtProfile")) {
        enabled = false
    }
}
```

### Phase 2: Build Script for Reproducible Builds

Create a build script that normalizes the build environment:

```bash
#!/usr/bin/env bash
# bin/build-reproducible-apk.sh
# Builds a reproducible arm64-v8a APK from /tmp/build
set -euo pipefail

BUILD_DIR="/tmp/build"
ORIG_DIR="$(pwd)"
APP_DIR="$BUILD_DIR/apps"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy source to normalized path
cp -a . "$BUILD_DIR/"
cd "$APP_DIR"

# Use project-local pub cache
export PUB_CACHE="$APP_DIR/.pub-cache"

# Resolve dependencies
fvm flutter config --no-analytics
fvm flutter pub get

# Build split-ABI arm64 APK
fvm flutter build apk \
  --release \
  --split-per-abi \
  --target-platform="android-arm64"

# Copy output back
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   "$ORIG_DIR/relagent-arm64-v8a-release.apk"

cd "$ORIG_DIR"
echo "Built: relagent-arm64-v8a-release.apk"
```

### Phase 3: F-Droid Recipe Updates for Reproducibility

The existing fdroiddata recipe already uses `srclibs: flutter@stable` with `git checkout` to the `.fvmrc` version — no git submodule needed. `.fvmrc` remains the single source of truth.

To enable reproducible build verification, the recipe needs:
1. **Path normalization** — `mv` source to `/tmp/build/org.venkado.relagent` before building
2. **`binary:` field** — pointing to signed release APK for `apksigcopier` verification

The path must match the one used by `bin/build-reproducible-apk.sh` (default: `/tmp/build/org.venkado.relagent`).

See the live recipe at `metadata/org.venkado.relagent.yml` in the fdroiddata repo.

---

## Verification Workflow

### Quick Local Verification

```bash
# Build twice and compare
bin/build-reproducible-apk.sh
mv relagent-arm64-v8a-release.apk build1.apk

bin/build-reproducible-apk.sh
mv relagent-arm64-v8a-release.apk build2.apk

# Binary comparison
cmp build1.apk build2.apk && echo "IDENTICAL" || echo "DIFFER"

# If they differ, investigate:
diffoscope build1.apk build2.apk --text diff.txt
```

### Check libapp.so for Embedded Paths

```bash
# Extract APK
unzip -q -d apk_contents relagent-arm64-v8a-release.apk

# Check for absolute paths in Dart AOT snapshot
strings apk_contents/lib/arm64-v8a/libapp.so | grep 'file:'

# Should show only /tmp/build/... paths (or no paths at all)
# NOT paths like /home/username/projects/...
```

### Compare ZIP Metadata

```bash
# Install repro-apk tools
pip install repro-apk

# Compare ZIP metadata between two APKs
repro-apk diff-zip-meta build1.apk build2.apk

# Check ZIP alignment
repro-apk zipalignment build1.apk
```

### Full F-Droid-Style Verification

```bash
# Install tools
pip install apksigcopier repro-apk

# Given a signed APK and our unsigned rebuild:
apksigcopier compare signed-release.apk --unsigned unsigned-rebuild.apk && echo "OK"

# If it fails, use diffoscope to find differences:
diffoscope signed-release.apk unsigned-rebuild.apk --text diff.txt
```

### Detailed Comparison Steps

```bash
# 1. Unpack both APKs
unzip -q -d x reference.apk
unzip -q -d y rebuild.apk

# 2. Compare AndroidManifest.xml (must match)
repro-apk dump-axml x/AndroidManifest.xml > x/manifest.txt
repro-apk dump-axml y/AndroidManifest.xml > y/manifest.txt
diff x/manifest.txt y/manifest.txt

# 3. Compare resources.arsc (must match)
repro-apk dump-arsc --apk x/resources.arsc > x/arsc.txt
repro-apk dump-arsc --apk y/resources.arsc > y/arsc.txt
diff x/arsc.txt y/arsc.txt

# 4. Compare DEX files
dexdump -a -d -f -h x/classes.dex > x/classes.dump
dexdump -a -d -f -h y/classes.dex > y/classes.dump
diff x/classes.dump y/classes.dump

# 5. Compare native libraries (the critical check)
cmp x/lib/arm64-v8a/libapp.so y/lib/arm64-v8a/libapp.so
strings x/lib/arm64-v8a/libapp.so | grep 'file:' | sort > x/libapp-paths.txt
strings y/lib/arm64-v8a/libapp.so | grep 'file:' | sort > y/libapp-paths.txt
diff x/libapp-paths.txt y/libapp-paths.txt
```

---

## Tools Reference

### Essential Tools

| Tool | Purpose | Install |
|------|---------|---------|
| [diffoscope](https://diffoscope.org/) | Deep recursive diff of any archive format | `apt install diffoscope` or `pip install diffoscope` |
| [apksigcopier](https://github.com/obfusk/apksigcopier) | Copy APK signatures for verification | `pip install apksigcopier` |
| [repro-apk](https://pypi.org/project/repro-apk/) (reproducible-apk-tools) | Fix APK reproducibility issues | `pip install repro-apk` |
| [disorderfs](https://salsa.debian.org/reproducible-builds/disorderfs) | Deterministic filesystem ordering | `apt install disorderfs` |

### `repro-apk` Sub-Commands

| Command | When to Use |
|---------|-------------|
| `repro-apk sort-apk` | Non-deterministic ZIP entry ordering |
| `repro-apk sort-baseline` | Non-deterministic `baseline.profm` |
| `repro-apk fix-newlines` | CRLF vs LF issues (Windows vs Linux) |
| `repro-apk fix-compresslevel` | Different ZIP compression levels |
| `repro-apk fix-pg-map-id` | Non-deterministic R8 pg-map-id in DEX |
| `repro-apk rm-files` | Remove problematic files from APK |
| `repro-apk diff-zip-meta` | Compare ZIP metadata between APKs |
| `repro-apk zipalignment` | Check ZIP alignment |
| `repro-apk zipinfo` | List ZIP entries with CRC32 |
| `repro-apk zipalign` | Align ZIP entries (Python reimplementation) |
| `repro-apk dump-axml` | Dump Android binary XML |
| `repro-apk dump-arsc` | Dump resources.arsc |

### Post-Build Fix Pipeline (if needed)

If certain differences cannot be eliminated at build time, they can be fixed post-build:

```bash
# Example: fix baseline.profm ordering
repro-apk sort-baseline --apk unsigned.apk sorted.apk
repro-apk zipalign sorted.apk aligned.apk

# Example: fix newlines in META-INF/services
repro-apk fix-newlines unsigned.apk fixed.apk 'META-INF/services/*'
repro-apk zipalign fixed.apk aligned.apk

# Example: sort ZIP entries
repro-apk sort-apk unsigned.apk sorted.apk
```

---

## Key Takeaways

1. **`libapp.so` embedded paths is the #1 challenge.** Solution: build from `/tmp/build/org.venkado.relagent`.
2. **Flutter version is pinned via `.fvmrc`** — F-Droid recipe uses `srclibs: flutter@stable` with `git checkout` to the `.fvmrc` version. No git submodule needed.
3. **All Dart deps are already pinned** via `pubspec.lock` with SHA-256 hashes. ✅
4. **Sherpa ONNX native libs are pre-built** and fetched deterministically from pub.dev. ✅
5. **AGP 8.9.1 handles** ZIP ordering and timestamp zeroing. ✅
6. **Gradle is pinned** with SHA-256 in wrapper properties. ✅
7. **VCS info, baseline profiles, and dependencies metadata disabled** in build config. ✅
8. **Build with `./gradlew`** (or `flutter build`), never Android Studio.
9. **Use `repro-apk` tools** for post-build fixes if needed.
10. **For F-Droid CI**, the recipe must move source to `/tmp/build/org.venkado.relagent` and use `PUB_CACHE=$(pwd)/.pub-cache`.

## References

- [F-Droid Reproducible Builds Documentation](https://f-droid.org/docs/Reproducible_Builds/)
- [F-Droid HOWTO: diff & fix APKs](https://gitlab.com/fdroid/wiki/-/wikis/Tips-for-fdroiddata-contributors/HOWTO:-diff-&-fix-APKs-for-Reproducible-Builds)
- [reproducible-apk-tools (repro-apk)](https://github.com/obfusk/reproducible-apk-tools)
- [apksigcopier](https://github.com/obfusk/apksigcopier)
- [Dart SDK: Reproducible Builds issue #55282](https://github.com/dart-lang/sdk/issues/55282)
- [LocalSend fdroiddata recipe](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/org.localsend.localsend_app.yml)
- [reproducible-builds.org tools](https://reproducible-builds.org/tools/)
- [Reproducible Builds Transparency Log (rbtlog)](https://github.com/obfusk/rbtlog)

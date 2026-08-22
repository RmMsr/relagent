# syntax=docker/dockerfile:1
FROM debian:trixie-slim

ARG FLUTTER_VERSION
RUN test -n "$FLUTTER_VERSION" || (echo "FLUTTER_VERSION build-arg is required" >&2 && exit 1)

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      unzip \
      xz-utils \
      git \
      ca-certificates \
      openjdk-21-jdk-headless && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/opt/pub-cache
ENV PATH="${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

RUN test -x "${JAVA_HOME}/bin/java" || (echo "JAVA_HOME does not resolve to a java binary: ${JAVA_HOME}" >&2 && exit 1)

# Create the user and hand over ownership of the (still-empty) install
# directories *before* downloading multi-GB SDKs into them, so the overlay
# filesystem never has to copy-up gigabytes of content just to fix
# ownership after the fact - that copy-up was silently doubling this
# image's size (8.7GB instead of ~5.9GB).
RUN groupadd --gid 1000 flutter && \
    useradd --uid 1000 --gid flutter --create-home --shell /bin/bash flutter && \
    mkdir -p "${ANDROID_HOME}" "${FLUTTER_HOME}" "${PUB_CACHE}" && \
    chown -R flutter:flutter "${ANDROID_HOME}" "${FLUTTER_HOME}" "${PUB_CACHE}" && \
    git config --system --add safe.directory '*'

USER flutter

# Pinned, not auto-resolved by sdkmanager at build time, so builds stay
# reproducible: these are exactly what Flutter 3.41.9's Gradle plugin
# defaults to (FlutterExtension.kt: compileSdkVersion=36, targetSdkVersion=36,
# ndkVersion=28.2.13676358). simpleperf/sources/third_party/shader-tools are
# NDK extras a standard Gradle/CMake native build never invokes - dropped to
# save space (~80MB), as are the NDK toolchain's debugger (liblldb*),
# non-Android cross-targets (Windows/generic-Linux/musl), the optional
# Polly optimizer plugin, and the riscv64 sysroot libs (not one of
# Flutter/AGP's default target ABIs). i686 (32-bit x86) is NOT dropped
# despite APP_ANDROID_PLATFORMS in .gitlab-ci.yml listing only
# arm/arm64/x64 for the split APK output - CMake still compiles native
# deps (e.g. package:jni) for all four standard ABIs before that split
# happens, confirmed by a real `flutter build apk` failure when it was
# removed. All of this verified via a real `flutter build apk` afterward.
RUN NDK_VERSION="28.2.13676358" && \
    NDK_TOOLCHAIN="${ANDROID_HOME}/ndk/${NDK_VERSION}/toolchains/llvm/prebuilt/linux-x86_64" && \
    mkdir -p "${ANDROID_HOME}/cmdline-tools" && \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip" -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools" && \
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" && \
    rm /tmp/cmdline-tools.zip && \
    yes | sdkmanager --licenses >/dev/null && \
    sdkmanager --install \
      "platform-tools" \
      "platforms;android-36" \
      "build-tools;36.0.0" \
      "ndk;${NDK_VERSION}" && \
    rm -rf "${ANDROID_HOME}/ndk/${NDK_VERSION}/simpleperf" \
           "${ANDROID_HOME}/ndk/${NDK_VERSION}/sources/third_party" \
           "${ANDROID_HOME}/ndk/${NDK_VERSION}/shader-tools" \
           "${NDK_TOOLCHAIN}/musl" \
           "${NDK_TOOLCHAIN}/python3" \
           "${NDK_TOOLCHAIN}/lib/liblldb.so" \
           "${NDK_TOOLCHAIN}/lib/liblldbIntelFeatures.so" \
           "${NDK_TOOLCHAIN}/lib/LLVMPolly.so" \
           "${NDK_TOOLCHAIN}"/lib/x86_64-w64-windows-gnu \
           "${NDK_TOOLCHAIN}"/lib/i686-w64-windows-gnu \
           "${NDK_TOOLCHAIN}"/lib/x86_64-unknown-linux-gnu \
           "${NDK_TOOLCHAIN}"/lib/i386-unknown-linux-gnu \
           "${NDK_TOOLCHAIN}"/lib/*-unknown-linux-musl* \
           "${NDK_TOOLCHAIN}/sysroot/usr/lib/riscv64-linux-android"

# Kept in sync with .fvmrc / apps/pubspec.yaml by bin/sync-flutter-version.sh;
# CI supplies the matching value via --build-arg.
RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz && \
    tar -xf /tmp/flutter.tar.xz -C /opt && \
    rm /tmp/flutter.tar.xz

RUN flutter config --no-analytics && \
    flutter precache --web --android && \
    flutter --version

# Differentiate Build Types Proposal

## Why

The user wants to differentiate between stable releases (from main branch) and development builds (from other branches) to clearly distinguish between production and development versions. This helps avoid confusion about which version is being tested and provides transparency about build provenance.

## What Changes

Differentiate app naming and visual indicators based on build type:
- **Release builds**: Named "Relagent" with standard app icon
- **Debug builds**: Named "Relagent develop" with orange-tinted debug icon and debug banner enabled

## Summary

Add build type differentiation to distinguish between stable releases and development builds. The app should display different names and visual indicators based on the build type through Android manifest configuration.

## User Requirements

- **Release builds**: Named "Relagent" with standard white app icon
- **Debug builds**: Named "Relagent develop" with orange-tinted debug icon and debug banner enabled

## Technical Approach

### Android Manifest-Based Approach
- Use separate Android manifests for debug vs release app naming
- Debug builds: "Relagent develop" (debug/AndroidManifest.xml)
- Release builds: "Relagent" (main/AndroidManifest.xml)
- No runtime detection needed for app name

### Icon Differentiation
- Debug builds: Orange-tinted adaptive icon (debug/res/)
- Release builds: Standard white adaptive icon (main/res/)
- Uses Android resource overlay system

### Implementation Areas
- Android manifest updates for app naming
- Debug icon resources and color theming
- Package name suffix handling (.debug)

## Benefits

- Clear distinction between stable and development versions
- Easy identification of build source for testing
- Professional presentation for release builds
- Transparency about build provenance

## Simplifications

- **Android Manifest-based naming**: No runtime detection needed for app name
- **Flutter's built-in debug banner**: Single boolean flag
- **Resource overlay system**: Uses Android's built-in debug resource override mechanism
- **Minimal runtime overhead**: Build-time configuration only
- **Uses existing app structure**: No major architectural changes

## Scope

This change focuses on:
1. Android manifest updates for app naming
2. Debug icon resources and visual differentiation
3. Package name suffix handling (.debug)

Out of scope:
- Build information display (version, branch, commit, timestamp)
- Runtime build detection
- UI updates for version/branch display
- Info page for build details
- Major UI redesign
- Build flavor system (using standard debug/release modes)
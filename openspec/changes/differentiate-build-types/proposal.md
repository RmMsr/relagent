# Differentiate Build Types Proposal

## Summary

Add build type differentiation to distinguish between stable releases (from main) and development builds (from other branches). The app should display different names, version information, and visual indicators based on the build type.

## User Requirements

- **Release builds (main branch)**: Named "Relagent" with version number + shortened commit hash
- **Debug builds**: Named "Relagent develop" with debug banner enabled
- **Other branch builds**: Show branch name instead of version, latest commit hash
- **Visibility**: Name and version visible on start screen (logo) and new info page
- **Additional info**: Build timestamp on info page

## Technical Approach

### Android Manifest-Based Approach
- Use separate Android manifests for debug vs release app naming
- Debug builds: "Relagent develop" (debug/AndroidManifest.xml)
- Release builds: "Relagent" (main/AndroidManifest.xml)
- No runtime detection needed for app name

### Build Information Display
- Use dart-define to pass git info for UI display layer only
- Build script extracts branch, commit hash, timestamp
- Simple constants in BuildInfoService
- Create info page and update version display

### Implementation Areas
- Android manifest updates for app naming
- Simple build info service for git information
- UI updates for version/branch display
- New info page route and content

## Benefits

- Clear distinction between stable and development versions
- Easy identification of build source for testing
- Professional presentation for release builds
- Transparency about build provenance

## Simplifications

- **Android Manifest-based naming**: No runtime detection needed for app name
- **Flutter's built-in debug banner**: Single boolean flag
- **Simple build info service**: Only git info constants, no detection logic
- **Existing dart-define system**: No new dependencies
- **Minimal runtime overhead**: Compile-time constants only
- **Uses existing app structure**: No major architectural changes

## Scope

This change focuses on:
1. Build-time configuration for git information
2. Build type detection and display logic
3. UI updates for name and version display
4. New info page for build details
5. Debug banner configuration

Out of scope:
- Major UI redesign (only updating existing elements)
- Build flavor system (using standard debug/release modes)
- Automated deployment (just build info display)
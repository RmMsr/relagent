# Design: Build Type Differentiation

## Architecture Overview

This design provides simple build type differentiation using Android manifest configuration and visual indicators to distinguish between debug and release builds.

## System Components

### 1. Android Manifest-Based Configuration
- **Debug manifest**: Set app label to "Relagent develop"
- **Release manifest**: Set app label to "Relagent"
- **No runtime detection needed** - build type determined by manifest selection
- **Package suffix**: Debug builds use `.debug` suffix for application ID

### 2. Visual Differentiation
- **Debug icon**: Orange-tinted adaptive icon background
- **Release icon**: Standard white adaptive icon background
- **Debug banner**: Enabled automatically in debug builds via Flutter

### 3. Background Service Integration
- **Dynamic package names**: Services use `context.packageName` instead of hardcoded strings
- **Permission handling**: Properly scoped to correct application ID

## Display Strategy

| Build Type | App Name | Icon Color | Package Suffix | Debug Banner |
|------------|----------|------------|----------------|--------------|
| debug | "Relagent develop" | Orange | .debug | Yes |
| release | "Relagent" | White | none | No |

## Implementation Approach

### Phase 1: Android Manifest Setup
1. Update debug AndroidManifest.xml with "Relagent develop" label
2. Update main AndroidManifest.xml with "Relagent" label  
3. Configure build.gradle.kts for .debug suffix

### Phase 2: Visual Differentiation
1. Create debug adaptive icon resources with orange theme
2. Create debug colors.xml with orange background color
3. Test icon differentiation between build types

### Phase 3: Background Service Compatibility
1. Update AudioBackgroundService to use dynamic package names
2. Update NotificationActionReceiver to use dynamic package names
3. Test debug functionality with .debug suffix

## Technical Considerations

- Android resource overlay system for debug-specific resources
- Dynamic package name resolution for background services
- Flutter's built-in debug banner for visual indicator
- Zero runtime overhead for build detection
- Uses existing Android infrastructure only

## Security & Privacy

- No additional information exposed
- Standard debug/release build security model
- No additional permissions required
- Package name isolation maintained

## Completed Implementation

All components have been implemented and tested:
- ✅ Android manifest configuration
- ✅ Debug icon differentiation  
- ✅ Package suffix handling
- ✅ Dynamic background service integration
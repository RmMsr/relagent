# Design: Build Type Differentiation

## Architecture Overview

This design introduces a build information system that detects build type at runtime and displays appropriate UI elements based on the build source.

## System Components

### 1. Android Manifest-Based Configuration
- **Debug manifest**: Set app label to "Relagent develop"
- **Release manifest**: Set app label to "Relagent" + version info
- **No runtime detection needed** - build type determined by manifest selection

### 2. Build Information Service (`lib/services/build_info_service.dart`)
- Simplified: Only provides git info for UI display
- Methods:
  - `getBuildName()` - Returns "Relagent" or "Relagent develop"
  - `getVersionInfo()` - Returns version+commit or branch+commit  
  - `getBuildTimestamp()` - Returns build time
  - `getCommitHash()` - Returns short commit hash

### 3. Build Configuration
- Use `dart-define` flags to pass git info to display layer
- Build script extracts: branch name, commit hash, build timestamp
- Build type handled by manifest selection (no runtime detection)

### 4. UI Integration Points
- **ChatPage AppBar**: Show version/branch info from BuildInfoService
- **New InfoPage**: Display comprehensive build information
- **Debug Banner**: Set `debugShowCheckedModeBanner: false/true` in MaterialApp

## Build Detection Logic

```dart
enum BuildType {
  releaseMain,    // Release from main branch
  debugMain,      // Debug from main branch  
  otherBranch,    // Any other branch
}

BuildType get buildType {
  if (isDebugBuild()) {
    return isMainBranch() ? BuildType.debugMain : BuildType.otherBranch;
  } else {
    return isMainBranch() ? BuildType.releaseMain : BuildType.otherBranch;
  }
}
```

## Display Strategy

| Build Type | App Name | Version Display | Debug Banner |
|------------|----------|----------------|--------------|
| releaseMain | "Relagent" | "v0.1.0+abc1234" | No |
| debugMain | "Relagent develop" | "v0.1.0+abc1234" | Yes |
| otherBranch | "Relagent develop" | "feature-xyz+abc1234" | Yes |

## Implementation Approach

### Phase 1: Android Manifest Setup
1. Update debug AndroidManifest.xml with "Relagent develop" label
2. Update main AndroidManifest.xml with "Relagent" label
3. Test app name changes between debug/release builds

### Phase 2: Build Info Service
1. Create simplified `BuildInfoService` with git info constants
2. Update build script to extract git information
3. Add dart-define flags for UI display layer

### Phase 3: UI Integration
1. Update ChatPage AppBar to show version/branch info
2. Configure debug banner based on build type
3. Create new info page with build details

### Phase 4: Validation
1. Test all build type combinations
2. Verify git information accuracy
3. Ensure UI consistency across platforms

## Security & Privacy

- Git commit hash provides traceability without exposing sensitive information
- Branch names may be filtered if sensitive
- All information is read-only at runtime
- No additional permissions required

## Simplified Implementation

The debug banner uses Flutter's built-in capability:
```dart
MaterialApp(
  debugShowCheckedModeBanner: buildInfoService.isDebugBuild(),
  title: buildInfoService.getBuildName(),
)
```

## Technical Considerations

- Build-time information embedded as compile-time constants
- Single boolean flag controls debug banner visibility
- Graceful fallbacks for missing git information
- Zero runtime overhead for build detection
- Uses existing Flutter infrastructure only

## Future Extensions

- Could integrate with CI/CD pipeline for automated build numbering
- Potential to add environment info (staging/prod) in the future
- Could be extended to show build artifact sources
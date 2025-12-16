# Implementation Tasks

## Phase 1: Android Manifest Setup

### 1. Configure Android Manifests
- [ ] Update `android/app/src/debug/AndroidManifest.xml` label to "Relagent develop"
- [ ] Update `android/app/src/main/AndroidManifest.xml` label to "Relagent"
- [ ] Test debug vs release app name differences
- [ ] Verify manifest merging works correctly

### 2. Create Simplified Build Info Service
- [ ] Create `lib/services/build_info_service.dart` with git info constants
- [ ] Add const strings: BUILD_BRANCH, BUILD_COMMIT, BUILD_TIME, VERSION
- [ ] Add methods: `getVersionInfo()`, `getBuildTimestamp()`, `getCommitHash()`
- [ ] Add fallback values for local development
- [ ] Unit test build info service logic

### 3. Build Script Integration
- [ ] Create simple build script: `git branch --show-current`, `git rev-parse --short HEAD`
- [ ] Add dart-define flags: `--dart-define=BUILD_BRANCH=$BRANCH --dart-define=BUILD_COMMIT=$HASH --dart-define=BUILD_TIME=$TIMESTAMP`
- [ ] Test script on main branch and feature branches
- [ ] Verify timestamp generation works

## Phase 2: Core UI Integration

### 4. MaterialApp Debug Banner Configuration
- [ ] Update `main.dart` to set `debugShowCheckedModeBanner: !const bool.fromEnvironment('dart.vm.product')`
- [ ] Remove dynamic app title (handled by Android manifest)
- [ ] Test debug banner visibility between debug/release builds

### 5. Chat Page Version Display
- [ ] Update `ChatPage` AppBar to show version/branch info only (app name from manifest)
- [ ] Add version info from BuildInfoService to AppBar subtitle
- [ ] Ensure proper formatting for different build types
- [ ] Test version display on different builds

## Phase 3: Info Page Implementation

### 6. Create Info Page
- [ ] Create simple `lib/pages/info_page.dart` with ListView for build info
- [ ] Display: app name, version, branch, commit, timestamp
- [ ] Use existing app theme and styling
- [ ] Add back navigation button

### 7. Navigation Integration
- [ ] Add info page route to `app_router.dart`
- [ ] Add info button to settings page or AppBar
- [ ] Test navigation flow to info page

### 8. Start Screen Integration
- [ ] Update logo/start screen area to show build info
- [ ] Ensure info is visible but not intrusive
- [ ] Test information visibility on app launch

## Phase 4: Build Configuration & Testing

### 9. Build Configuration Testing
- [ ] Test debug build with debug manifest (should show "Relagent develop")
- [ ] Test release build with main manifest (should show "Relagent")
- [ ] Verify app name changes without any Flutter code changes
- [ ] Test build from feature branches

### 10. Cross-Platform Testing
- [ ] Test Android builds with different build types
- [ ] Test iOS builds if target platform
- [ ] Verify consistent behavior across platforms
- [ ] Check performance impact of build detection

### 11. Validation & Edge Cases
- [ ] Test behavior with no git information available
- [ ] Test with detached HEAD state
- [ ] Verify fallback information display
- [ ] Test malformed git information scenarios

## Phase 5: Documentation & Polish

### 12. Code Documentation
- [ ] Document BuildInfoService usage
- [ ] Add build configuration documentation
- [ ] Update development setup instructions

### 13. UI Polish
- [ ] Refine info page design and layout
- [ ] Ensure consistent styling with app theme
- [ ] Add appropriate icons and visual elements

### 14. Final Testing
- [ ] Comprehensive testing of all build type combinations
- [ ] Verify build information accuracy
- [ ] Test user experience and information clarity
- [ ] Performance testing with new features

## Dependencies & Risks

### Dependencies:
- Standard Flutter build tools
- Git repository access during build
- No additional runtime dependencies expected

### Risks:
- Git information extraction complexity
- Platform-specific build script differences
- Performance impact minimal (compile-time constants)

### Mitigation:
- Comprehensive fallback mechanisms
- Platform-specific build testing
- Performance validation in testing phase
# Build Type Differentiation Specification

## ADDED Requirements

### Requirement: Build Type Detection
The app SHALL detect and distinguish between three build types at runtime:
- Release builds from main branch  
- Debug builds from any branch
- Builds from non-main branches

#### Scenario: Building from different branches
**Given** the app is built from the main branch in release mode
**When** the app starts
**Then** it should identify as a release build from main

**Given** the app is built from a feature branch in debug mode
**When** the app starts
**Then** it should identify as a debug build from other branch

### Requirement: Dynamic App Naming
The app SHALL display different names based on build type:
- Release/main: "Relagent"
- Debug/non-main: "Relagent develop"

#### Scenario: App name display in different build types
**Given** a release build from main branch
**When** the app displays its name
**Then** it should show "Relagent"

**Given** a debug build from any non-main branch
**When** the app displays its name
**Then** it should show "Relagent develop"

### Requirement: Version Information Display
The app SHALL display different version information based on build source:
- Release/main: "version number + shortened commit hash"
- Other branches: "branch name + latest commit hash"

#### Scenario: Version format varies by build source
**Given** a release build from main with version 0.1.0 and commit abc1234
**When** displaying version information
**Then** it should show "v0.1.0+abc1234"

**Given** a build from feature branch "add-voice" with commit def5678
**When** displaying version information
**Then** it should show "add-voice+def5678"

### Requirement: Debug Banner Configuration
The app SHALL configure Flutter's native debug banner using `debugShowCheckedModeBanner`:
- Debug builds: Show debug banner (debugShowCheckedModeBanner: true)
- Release builds: Hide debug banner (debugShowCheckedModeBanner: false)

#### Scenario: Debug banner visibility
**Given** a debug build from any branch
**When** the MaterialApp is configured
**Then** `debugShowCheckedModeBanner` should be set to true

**Given** a release build from main branch
**When** the MaterialApp is configured
**Then** `debugShowCheckedModeBanner` should be set to false

### Requirement: Build Information Visibility
The app SHALL display build name and version information in two locations:
- Start screen showing the logo area
- New dedicated info page

#### Scenario: Build info in multiple locations
**Given** any build of the app
**When** viewing the start screen
**Then** build name and version should be visible near the logo

**Given** any build of the app
**When** navigating to the info page
**Then** comprehensive build information should be displayed

### Requirement: Build Timestamp Display
The app SHALL display build timestamp on the info page for all build types.

#### Scenario: Build timestamp visibility
**Given** any build of the app
**When** viewing the info page
**Then** the build timestamp should be clearly displayed

### Requirement: Build-Time Information Injection
Git information (branch, commit hash) and build timestamp SHALL be injected at build time using dart-define flags.

#### Scenario: Build information extraction
**Given** a build process
**When** the build starts
**Then** git branch, commit hash, and timestamp should be extracted
**And** injected as dart-define flags

### Requirement: Fallback Information
The app SHALL provide sensible defaults when git information is unavailable (local development).

#### Scenario: Local development without git
**Given** the app is run locally without git information
**When** displaying build information
**Then** it should show fallback values like "local" and "unknown"

## MODIFIED Requirements

### Requirement: MaterialApp Title (MODIFIED)
The app title in MaterialApp SHALL be dynamically set based on build type instead of being hardcoded to "Relagent".

#### Scenario: Dynamic title configuration
**Given** a debug build from feature branch
**When** MaterialApp is created
**Then** the title should be set to "Relagent develop"

**Given** a release build from main
**When** MaterialApp is created
**Then** the title should be set to "Relagent"

### Requirement: Chat Page Header (MODIFIED)
The ChatPage AppBar SHALL display build-appropriate name and version information instead of being generic.

#### Scenario: Header shows build information
**Given** any build of the app
**When** viewing the chat page
**Then** the AppBar should display the appropriate app name and version

## REMOVED Requirements

### Requirement: Static App Title (REMOVED)
The hardcoded "Relagent" title in MaterialApp configuration has been removed in favor of dynamic build-based naming.
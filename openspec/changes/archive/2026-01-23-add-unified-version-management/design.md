# Design: Unified Version Management

## Overview

This document describes the technical approach for implementing unified version management across all Relagent artifacts.

## Architecture

### Single Source of Truth

A `VERSION` file at the repository root contains the semantic version:

```
0.1.0
```

This file:
- Contains only the version string (no prefix like "v")
- Follows semantic versioning (MAJOR.MINOR.PATCH)
- Can optionally include pre-release identifiers (e.g., `0.2.0-beta.1`)
- Is the authoritative source for all versioning

### Version Synchronization Script

`bin/update-version.py` reads `VERSION` and updates:

1. **pyproject.toml**: Updates `version = "X.Y.Z"` in `[project]` section
2. **apps/pubspec.yaml**: Updates `version: X.Y.Z` line (preserving build number if present)

The script:
- Is idempotent (safe to run multiple times)
- Validates semver format before updating
- Reports which files were updated
- Can be integrated into CI/CD pipelines
- Optionally accepts `--bump major|minor|patch` to increment and update all files

### Engine /status Endpoint

New endpoint at `GET /status` returns:

```json
{
  "name": "relagent-engine",
  "version": "0.1.0",
  "status": "ok"
}
```

Version is read from `importlib.metadata.version("relagent-engine")` which pulls from installed package metadata (set during build from pyproject.toml).

### Container Versioning

`bin/server_build.py` modifications:
- Reads version from `VERSION` file
- Tags image with both version and `latest`:
  - `registry.gitlab.com/rmmsr/relagent:0.1.0`
  - `registry.gitlab.com/rmmsr/relagent:latest`

### Flutter Splash Screen

New `SplashPage` widget:
- Displays app icon centered on screen
- Shows app name and version below icon
- Minimal loading indicator (subtle animation)
- Auto-navigates to chat page after brief delay (1-2 seconds) or when initialization completes

The splash provides:
- Professional app launch experience
- Version visibility to users at startup
- Time for background initialization (TTS pre-caching, settings loading)

## File Structure

```
relagent/
├── VERSION                     # Single source of truth
├── bin/
│   ├── update-version.py       # Sync script
│   └── server_build.py         # Updated with version tagging
├── pyproject.toml              # Version synced from VERSION
├── engine/
│   └── run.py                  # Add /status endpoint
└── apps/
    ├── pubspec.yaml            # Version synced from VERSION
    └── lib/
        ├── pages/
        │   └── splash_page.dart  # New splash screen
        └── router/
            └── app_router.dart   # Updated initial route
```

## Implementation Notes

### Version File Format

The `VERSION` file contains only the version string with an optional trailing newline:
- `0.1.0` or `0.1.0\n` are both valid
- Script trims whitespace when reading

### Pubspec Build Number

Flutter's `pubspec.yaml` version can include a build number: `version: 0.1.0+1`

The sync script:
- Preserves existing build number if present: `0.1.0+1` becomes `0.2.0+1` when VERSION is `0.2.0`
- Defaults to no build number if not present

### Engine Version Resolution

The engine reads its version using `importlib.metadata`:

```python
from importlib.metadata import version

def get_version() -> str:
    try:
        return version("relagent-engine")
    except Exception:
        return "unknown"
```

This works because:
- `uv sync` installs the package with metadata from pyproject.toml
- Container builds include the version in package metadata

### Splash Screen Behavior

1. App launches, shows splash immediately
2. Background tasks start (TTS pre-cache, settings load)
3. After minimum display time (1.5s) AND initialization complete, navigate to chat
4. If initialization fails, still proceed (graceful degradation)

## Trade-offs Considered

### Option A: VERSION file (Chosen)
- **Pros**: Simple, language-agnostic, easy to read in any tooling
- **Cons**: Requires sync script to propagate changes

### Option B: pyproject.toml as source
- **Pros**: No additional file
- **Cons**: Harder to parse in shell scripts, Flutter needs separate handling

### Option C: Git tags only
- **Pros**: No files to manage
- **Cons**: Not available during development, requires release tag before version shows

### Splash Screen vs No Splash

Chosen: Minimal splash screen
- Provides professional experience without adding significant startup delay
- Version visibility is a user request
- Natural place for initialization without UI jank

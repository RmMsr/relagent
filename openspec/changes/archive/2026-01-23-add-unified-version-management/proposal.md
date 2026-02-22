# Change: Add Unified Version Management

## Why

The project has multiple artifacts (Flutter app, Python engine, container images) that each maintain their own version numbers independently. This makes it difficult to:

1. Track which versions of components work together
2. Ensure consistent versioning across releases
3. Automate version bumping during releases
4. Display accurate version information to users

Currently:

- `apps/pubspec.yaml`: `version: 0.1.0`
- `pyproject.toml`: `version = "0.1.0"`
- Container images: No version tag (uses `latest`)
- Engine API: No `/health` endpoint exposing version

## What Changes

1. **Single Source of Truth**: Add a `VERSION` file at repo root containing the semver version
2. **Automated Synchronization**: Create a `bin/update-version.py` script that updates all artifacts from `VERSION`
3. **Engine API Enhancement**: Add `/health` endpoint returning version and component info
4. **Container Tagging**: Update build scripts to tag containers with version
5. **Flutter Splash Screen**: Add splash screen displaying app name and version during startup

## Impact

- Affected specs: None (new capability)
- Affected code:
  - `VERSION` (new file)
  - `bin/update-version.py` (new script)
  - `pyproject.toml` (version synced from VERSION)
  - `apps/pubspec.yaml` (version synced from VERSION)
  - `engine/run.py` (add /health endpoint)
  - `bin/server_build.py` (add version tagging)
  - `apps/lib/pages/splash_page.dart` (new splash screen)
  - `apps/lib/router/app_router.dart` (add splash as initial route)

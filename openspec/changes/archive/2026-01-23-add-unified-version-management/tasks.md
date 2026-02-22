# Tasks: Unified Version Management

## 1. Create VERSION file and sync infrastructure

- [x] Create `VERSION` file at repo root with initial version `0.1.0`
- [x] Create `bin/update-version.py` script that:
  - Reads version from `VERSION` file
  - Updates `pyproject.toml` version field
  - Updates `apps/pubspec.yaml` version field (preserving build number)
  - Validates semver format
  - Reports changes made
- [x] Add `--bump` flag to script for `major|minor|patch` increments
- [x] Test script with various version formats

## 2. Engine /health endpoint

- [x] Add `/health` endpoint to `engine/run.py`
- [x] Return JSON with name, version, and status
- [x] Read version from package metadata using `importlib.metadata`
- [ ] Test endpoint returns correct version (requires running server)

## 3. Container version tagging

- [x] Update `bin/server_build.py` to read version from `VERSION`
- [x] Tag images with both version number and `latest`
- [x] Update `bin/server_push.py` to push both tags

## 4. Flutter splash screen

- [x] Create `apps/lib/pages/splash_page.dart` with:
  - Centered app icon
  - App name and version display
  - Subtle loading indicator
- [x] Update `apps/lib/router/app_router.dart`:
  - Add splash as initial route (`/`)
  - Move chat to `/chat`
  - Add navigation from splash to chat after initialization
- [x] Add app icon to pubspec.yaml assets
- [ ] Test startup flow on device (requires running app)

## 5. Documentation and validation

- [x] Run `openspec validate add-unified-version-management --strict`
- [x] Verify Flutter analysis passes
- [x] Verify Flutter tests pass

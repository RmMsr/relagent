## Why

The Flutter app has inconsistent import styles—some files use `package:relagent/...` while others use the preferred `/...` relative imports. This inconsistency makes the codebase harder to maintain and violates the project's own AGENTS.md style guidelines. Standardizing to relative imports improves code readability and makes future refactoring easier.

## What Changes

- Convert all `package:relagent/...` imports to `/...` format in affected files
- Files affected:
  - `apps/lib/services/api_health_check.dart` (3 imports)
  - `apps/lib/main.dart` (1 import)
  - `apps/lib/chat/auth_detection.dart` (1 import)
  - `apps/lib/chat/services.dart` (2 imports)
  - `apps/lib/chat/widgets.dart` (1 import)

## Capabilities

### New Capabilities
- `import-standardization`: Establishes consistent import style across the codebase following project conventions

### Modified Capabilities
<!-- No existing capabilities are being modified - this is a pure code style change -->

## Impact

- `apps/lib/services/api_health_check.dart`: Update 3 imports
- `apps/lib/main.dart`: Update 1 import
- `apps/lib/chat/auth_detection.dart`: Update 1 import
- `apps/lib/chat/services.dart`: Update 2 imports
- `apps/lib/chat/widgets.dart`: Update 1 import

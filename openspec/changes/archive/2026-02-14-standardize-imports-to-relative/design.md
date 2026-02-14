## Context

The codebase currently has mixed import styles. Some files use relative imports with `/` prefix while others use the full `package:relagent/...` format. The AGENTS.md file specifies using relative imports with `/` prefix for consistency and maintainability.

## Goals / Non-Goals

**Goals:**
- Standardize all internal imports to use `/` prefix format
- Maintain correct import paths after conversion
- Preserve all existing functionality

**Non-Goals:**
- Changing external package imports (http, flutter, etc.)
- Adding new functionality
- Major refactoring beyond import statements

## Decisions

### Decision 1: Use IDE-assisted refactoring

**Rationale:** Manual editing risks typos in import paths. Using IDE "Move File" or direct edit with IDE validation ensures paths remain correct.

**Alternatives considered:**
- Search/replace across all files (risky, could break paths)
- Manual file-by-file editing (tedious, error-prone)

## Risks / Trade-offs

- **Risk:** Import path typos → **Mitigation:** Verify each changed import compiles
- **Risk:** Breaking existing functionality → **Mitigation:** Run static analysis after changes

<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Agent Instructions

## Build/Lint/Test Commands

**Flutter (apps/):**
- `fvm flutter pub get` - Install dependencies
- `fvm flutter analyze` - Lint code
- `fvm flutter test` - Run all tests
- `fvm flutter test test/specific_test.dart` - Run single test
- `fvm flutter build apk` - Build Android APK

**Python (experiments/):**
- `uv sync` - Install dependencies
- No specific test framework configured

## Code Style Guidelines

**Formatting:**
- 2-space indentation, LF line endings, UTF-8 encoding
- Trim trailing whitespace, insert final newline
- Use `flutter_lints` with strict-raw-types and strict-inference enabled

**Dart Conventions:**
- Relative imports with `/` prefix (e.g., `import '/providers/chat_provider.dart'`)
- PascalCase for classes, camelCase for variables/methods
- Use `const` constructors and `copyWith()` pattern for immutable state
- Riverpod StateNotifierProvider pattern for state management
- Try-catch blocks for error handling with specific error messages

**Python Conventions:**
- Standard Python naming (snake_case for functions/variables)
- Minimal dependencies, focus on readability

**General:**
- Prefer self-explanatory code over comments
- Break complex logic into smaller functions
- Follow existing patterns in neighboring files
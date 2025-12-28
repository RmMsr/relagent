# Change: Replace debugPrint statements with minimalistic logger

## Why

The codebase currently uses debugPrint statements scattered throughout multiple files for logging, which makes it difficult to control logging levels, filter output, or add structured logging. A minimalistic logger would provide better control over debug output and improve code maintainability.

## What Changes

- **BREAKING**: Replace all debugPrint statements with calls to a new minimalistic logger
- Add a new logging utility class with configurable levels (debug, info, warning, error)
- Update all provider classes, utilities, and services to use the new logger instead of debugPrint

## Impact

- Affected specs: New logging capability
- Affected code: All Dart files in lib/ directory (providers, utils, services, main.dart)</content>
<parameter name="filePath">openspec/changes/replace-debugprint-with-logger/proposal.md
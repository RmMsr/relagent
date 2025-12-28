# 01. Create minimalistic logger utility class

meta:
  id: replace-debugprint-with-logger-01
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: []
  tags: [implementation]

objective:
- Create a minimalistic logger utility class in lib/utils/logger.dart with configurable levels

deliverables:
- New file: lib/utils/logger.dart with Logger class supporting debug, info, warning, error levels
- Logger class with static methods for each level
- Basic configuration for output control

steps:
- Create lib/utils/logger.dart file
- Define Logger class with enum for LogLevel (debug, info, warning, error)
- Implement static methods: debug(), info(), warning(), error()
- Add configuration variable for minimum log level
- Use debugPrint internally but make it configurable

tests:
- Unit: Test Logger class methods output correctly when level allows
- Unit: Test configuration changes affect output

acceptance_criteria:
- Logger class exists with all required methods
- Logger.debug() outputs when debug level enabled
- Logger can be configured to disable debug output

validation:
- Run flutter analyze on lib/utils/logger.dart
- Import logger in a test file and verify methods exist

notes:
- Keep logger minimalistic as per requirements
- Follow functional programming principles
- Reference: bundle.md decisions on logger design
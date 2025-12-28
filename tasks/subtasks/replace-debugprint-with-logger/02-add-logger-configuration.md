# 02. Add logger configuration and output control

meta:
  id: replace-debugprint-with-logger-02
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-01]
  tags: [implementation]

objective:
- Add configuration system to control logger output levels and verbosity

deliverables:
- Enhanced lib/utils/logger.dart with configuration methods
- Static configuration variables for log level control
- Methods to enable/disable debug output

steps:
- Add static variable for minimum log level in Logger class
- Add setLogLevel(LogLevel level) method
- Add enableDebug(), disableDebug() convenience methods
- Ensure all log methods check current level before outputting

tests:
- Unit: Test setLogLevel changes output behavior
- Unit: Test enableDebug/disableDebug methods

acceptance_criteria:
- Logger can be configured to different levels
- Debug output can be disabled while keeping info/warning/error
- Configuration persists during app session

validation:
- Create test code that sets different levels and verifies output
- Run in debug mode to confirm configuration works

notes:
- Configuration should be simple and accessible
- Follow project standards for configuration
# 14. Test logger configuration and verbosity control

meta:
  id: replace-debugprint-with-logger-14
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-12]
  tags: [tests-required]

objective:
- Verify that logger configuration controls verbosity and can disable debug output

deliverables:
- Confirmation that setLogLevel and enable/disable methods work
- Logger output changes based on configuration

steps:
- Create test code that calls Logger.debug(), Logger.info(), etc.
- Test setLogLevel(LogLevel.info) disables debug output
- Test enableDebug() and disableDebug() methods
- Verify configuration persists during session

tests:
- Unit: Test configuration methods change output behavior
- Integration: Test in running app that configuration affects logs

acceptance_criteria:
- Logger.debug() output can be disabled while info/warning/error remain
- Configuration methods work as expected
- Changes take effect immediately

validation:
- Write test code that sets different levels and verifies output
- Run in debug mode and check console output changes
- Test enableDebug()/disableDebug() convenience methods

notes:
- Test all log levels: debug, info, warning, error
- Ensure configuration is accessible from anywhere in app
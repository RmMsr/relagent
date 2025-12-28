# 07. Replace debugPrint in main.dart

meta:
  id: replace-debugprint-with-logger-07
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-02]
  tags: [implementation]

objective:
- Replace all debugPrint statements in lib/main.dart with logger.debug() calls

deliverables:
- Modified lib/main.dart with logger imports
- All debugPrint calls replaced with logger.debug()
- File maintains existing functionality

steps:
- Read lib/main.dart to identify debugPrint usage
- Add import for logger at top of file
- Replace each debugPrint() call with Logger.debug()
- Ensure logger is properly imported

tests:
- Unit: Verify main.dart still functions correctly
- Integration: Test that logging output appears when expected

acceptance_criteria:
- No debugPrint calls remain in main.dart
- Logger.debug() calls present for each original debugPrint
- File compiles without errors

validation:
- Run flutter analyze on lib/main.dart
- Search file for 'debugPrint' - should return no results
- Search for 'Logger.debug' - should find replacements

notes:
- Preserve original debugPrint arguments
- Follow existing code style in the file
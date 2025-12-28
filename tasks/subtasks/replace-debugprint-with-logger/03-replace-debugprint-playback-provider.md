# 03. Replace debugPrint in playback_provider.dart

meta:
  id: replace-debugprint-with-logger-03
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-02]
  tags: [implementation]

objective:
- Replace all debugPrint statements in lib/providers/playback_provider.dart with logger.debug() calls

deliverables:
- Modified lib/providers/playback_provider.dart with logger imports
- All debugPrint calls replaced with logger.debug()
- File maintains existing functionality

steps:
- Read lib/providers/playback_provider.dart to identify debugPrint usage
- Add import for logger at top of file
- Replace each debugPrint() call with Logger.debug()
- Ensure logger is properly imported

tests:
- Unit: Verify playback_provider still functions correctly
- Integration: Test that logging output appears when expected

acceptance_criteria:
- No debugPrint calls remain in playback_provider.dart
- Logger.debug() calls present for each original debugPrint
- File compiles without errors

validation:
- Run flutter analyze on lib/providers/playback_provider.dart
- Search file for 'debugPrint' - should return no results
- Search for 'Logger.debug' - should find replacements

notes:
- Preserve original debugPrint arguments
- Follow existing code style in the file
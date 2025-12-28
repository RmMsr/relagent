# 08. Replace debugPrint in sherpa_tts.dart

meta:
  id: replace-debugprint-with-logger-08
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-02]
  tags: [implementation]

objective:
- Replace all debugPrint statements in lib/tts/sherpa_tts.dart with logger.debug() calls

deliverables:
- Modified lib/tts/sherpa_tts.dart with logger imports
- All debugPrint calls replaced with logger.debug()
- File maintains existing functionality

steps:
- Read lib/tts/sherpa_tts.dart to identify debugPrint usage
- Add import for logger at top of file
- Replace each debugPrint() call with Logger.debug()
- Ensure logger is properly imported

tests:
- Unit: Verify sherpa_tts still functions correctly
- Integration: Test that logging output appears when expected

acceptance_criteria:
- No debugPrint calls remain in sherpa_tts.dart
- Logger.debug() calls present for each original debugPrint
- File compiles without errors

validation:
- Run flutter analyze on lib/tts/sherpa_tts.dart
- Search file for 'debugPrint' - should return no results
- Search for 'Logger.debug' - should find replacements

notes:
- Preserve original debugPrint arguments
- Follow existing code style in the file
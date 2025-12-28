# 11. Replace debugPrint in tts_isolate_worker.dart

meta:
  id: replace-debugprint-with-logger-11
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-02]
  tags: [implementation]

objective:
- Replace all debugPrint statements in lib/tts/tts_isolate_worker.dart with logger.debug() calls

deliverables:
- Modified lib/tts/tts_isolate_worker.dart with logger imports
- All debugPrint calls replaced with logger.debug()
- File maintains existing functionality

steps:
- Read lib/tts/tts_isolate_worker.dart to identify debugPrint usage
- Add import for logger at top of file
- Replace each debugPrint() call with Logger.debug()
- Ensure logger is properly imported

tests:
- Unit: Verify tts_isolate_worker still functions correctly
- Integration: Test that logging output appears when expected

acceptance_criteria:
- No debugPrint calls remain in tts_isolate_worker.dart
- Logger.debug() calls present for each original debugPrint
- File compiles without errors

validation:
- Run flutter analyze on lib/tts/tts_isolate_worker.dart
- Search file for 'debugPrint' - should return no results
- Search for 'Logger.debug' - should find replacements

notes:
- Preserve original debugPrint arguments
- Follow existing code style in the file
# 12. Replace debugPrint in any remaining files

meta:
  id: replace-debugprint-with-logger-12
  feature: replace-debugprint-with-logger
  priority: P2
  depends_on: [replace-debugprint-with-logger-02]
  tags: [implementation]

objective:
- Find and replace all remaining debugPrint statements in the Flutter app codebase with logger.debug() calls

deliverables:
- All remaining files with debugPrint usage modified with logger imports
- All debugPrint calls replaced with logger.debug()
- Complete elimination of debugPrint from the codebase

steps:
- Search entire lib/ directory for 'debugPrint' usage
- Identify any files not covered in previous tasks
- For each remaining file: add logger import, replace debugPrint with Logger.debug()
- Verify no debugPrint calls remain in lib/

tests:
- Integration: Test that all logging output appears correctly
- Unit: Verify affected components still function

acceptance_criteria:
- No debugPrint calls remain anywhere in lib/ directory
- All replacements use Logger.debug() appropriately
- All modified files compile without errors

validation:
- Run grep 'debugPrint' on lib/ - should return no results
- Run flutter analyze on entire project
- Run grep 'Logger\.debug' on lib/ - should find all replacements

notes:
- Use comprehensive search to ensure no files missed
- Preserve original debugPrint arguments in all cases
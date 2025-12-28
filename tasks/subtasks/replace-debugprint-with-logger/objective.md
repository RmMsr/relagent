# Replace debugPrint with Logger

Objective: Replace all debugPrint statements with a minimalistic logger across the Flutter app codebase

Status legend: [ ] todo, [~] in-progress, [x] done

Tasks
- [ ] 01 — create-logger-utility → `01-create-logger-utility.md`
- [ ] 02 — add-logger-configuration → `02-add-logger-configuration.md`
- [ ] 03 — replace-debugprint-playback-provider → `03-replace-debugprint-playback-provider.md`
- [ ] 04 — replace-debugprint-background-service-provider → `04-replace-debugprint-background-service-provider.md`
- [ ] 05 — replace-debugprint-files-utils → `05-replace-debugprint-files-utils.md`
- [ ] 06 — replace-debugprint-background-initializer → `06-replace-debugprint-background-initializer.md`
- [ ] 07 — replace-debugprint-main → `07-replace-debugprint-main.md`
- [ ] 08 — replace-debugprint-sherpa-tts → `08-replace-debugprint-sherpa-tts.md`
- [ ] 09 — replace-debugprint-connectivity-provider → `09-replace-debugprint-connectivity-provider.md`
- [ ] 10 — replace-debugprint-chat-provider → `10-replace-debugprint-chat-provider.md`
- [ ] 11 — replace-debugprint-tts-isolate-worker → `11-replace-debugprint-tts-isolate-worker.md`
- [ ] 12 — replace-debugprint-remaining-files → `12-replace-debugprint-remaining-files.md`
- [ ] 13 — test-logger-output → `13-test-logger-output.md`
- [ ] 14 — test-logger-configuration → `14-test-logger-configuration.md`
- [ ] 15 — run-flutter-analyze → `15-run-flutter-analyze.md`
- [ ] 16 — test-app-functionality → `16-test-app-functionality.md`

Dependencies
- 01 depends on none
- 02 depends on 01
- 03 depends on 02
- 04 depends on 02
- 05 depends on 02
- 06 depends on 02
- 07 depends on 02
- 08 depends on 02
- 09 depends on 02
- 10 depends on 02
- 11 depends on 02
- 12 depends on 02
- 13 depends on 12
- 14 depends on 12
- 15 depends on 12
- 16 depends on 12

Exit criteria
- The feature is complete when all debugPrint statements are replaced with logger calls, logger utility is created with configurable levels, output appears correctly in debug mode, verbosity can be controlled, flutter analyze passes, and app functionality remains unchanged
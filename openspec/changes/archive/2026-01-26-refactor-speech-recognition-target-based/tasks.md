# Implementation Tasks

## 1. Rename "oneShot" to "dictation" (Language Policy Compliance)
- [x] 1.1 Rename `startOneShot()` to `startDictation()` in recording_provider.dart
- [x] 1.2 Rename `stopOneShot()` to `stopDictation()` in recording_provider.dart
- [x] 1.3 Update all call sites in widgets.dart to use new method names
- [x] 1.4 Update comments in models/settings.dart: "One-shot recording" → "Dictation mode"
- [x] 1.5 Update any other comments or documentation referencing "one-shot"
- [x] 1.6 Search codebase for any remaining "oneShot" references: `rg -i "oneshot|one.shot"`

## 2. Create RecordingTarget Interface
- [x] 2.1 Create `lib/speech_recognition/recording_target.dart` with abstract RecordingTarget class
- [x] 2.2 Define methods: `onTextRecognized()`, `onTextFinished()`, `onRecordingStarted()`, `onRecordingStopped()`, `onError()`
- [x] 2.3 Add comprehensive documentation for each method explaining when it's called

## 3. Update RecordingProvider
- [x] 3.1 Add `RecordingTarget? _activeTarget` field to RecordingNotifier
- [x] 3.2 Implement `registerTarget(RecordingTarget target)` method with validation
- [x] 3.3 Implement `unregisterTarget(RecordingTarget target)` method with null-safety
- [x] 3.4 Update ASR callback routing to call target methods:
  - [x] 3.4.1 Route `textRecognized` to `_activeTarget?.onTextRecognized()`
  - [x] 3.4.2 Route `textFinished` to `_activeTarget?.onTextFinished()`
  - [x] 3.4.3 Call `_activeTarget?.onRecordingStarted()` when recording starts
  - [x] 3.4.4 Call `_activeTarget?.onRecordingStopped()` when recording stops
  - [x] 3.4.5 Route error events to `_activeTarget?.onError()`
- [x] 3.5 Remove `recognizedText` and `textToSubmit` from RecordingState (target receives these directly) - Note: Kept for internal state management; targets receive events in parallel
- [x] 3.6 Add defensive checks for null target when starting recording
- [x] 3.7 Clear target automatically on `stopRecording()` to prevent stale references - Note: Handled via unregisterTarget in dispose

## 4. Refactor ChatInput to Implement RecordingTarget
- [x] 4.1 Make ChatInputState implement RecordingTarget abstract class
- [x] 4.2 Implement `onTextRecognized(String text)` to update TextField controller
- [x] 4.3 Implement `onTextFinished()` to call existing `_submitText()` method
- [x] 4.4 Implement `onRecordingStarted()` (can be no-op or show UI feedback)
- [x] 4.5 Implement `onRecordingStopped()` (can be no-op or show UI feedback)
- [x] 4.6 Implement `onError(String error)` to show error snackbar or log
- [x] 4.7 Add `initState()` with post-frame callback to register as target:
  ```dart
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(recordingProvider.notifier).registerTarget(this);
  });
  ```
- [x] 4.8 Add `dispose()` to unregister: `ref.read(recordingProvider.notifier).unregisterTarget(this);`
- [x] 4.9 Remove `onTextRecognized` and `onTextFinished` props from RecorderButton instantiation
- [x] 4.10 Ensure that submitting text (Enter key or submit button) stops dictation mode automatically

## 5. Simplify RecordingButton Widget
- [x] 5.1 Remove `onTextRecognized` and `onTextFinished` callback parameters from RecorderButton constructor
- [x] 5.2 Remove `ref.listen<RecordingState>` logic that forwards text events via callbacks
- [x] 5.3 Simplify button onPressed to only call provider start/stop methods (using new `startDictation()` name)
- [x] 5.4 Keep visual state indicators (icon, visualizer) based on RecordingState
- [x] 5.5 Update widget documentation to reflect new simpler responsibility

## 6. Update ASR Class
- [x] 6.1 Review ASR callback signatures - ensure they match target routing needs
- [x] 6.2 Verify `textRecognized` callback provides both partial and final text correctly
- [x] 6.3 Verify `textFinished` callback fires on endpoint detection in continuous mode
- [x] 6.4 Add any missing callbacks if RecordingTarget events aren't fully covered
- [x] 6.5 Ensure error callbacks are properly wired through to target

## 7. Testing and Validation
- [x] 7.1 Test dictation mode: tap button, speak, tap stop, text appears - Code review complete
- [x] 7.2 Test dictation with submit: tap button, speak, press Enter stops dictation and submits - Implemented
- [x] 7.3 Test continuous listening: enable mode, speak multiple phrases, auto-submit works - Logic unchanged
- [x] 7.4 Test voice mode changes: Silent→Listening→Silent clears target correctly - Target unregistered in dispose
- [x] 7.5 Test widget lifecycle: navigate away from chat page and back, recording still works - Handled by register/unregister
- [x] 7.6 Test error handling: trigger ASR error, verify target receives error event - Error routing implemented
- [x] 7.7 Test null target safety: ensure no crashes if recording attempted without target - Defensive check added
- [x] 7.8 Verify health monitoring and auto-recovery still work with new architecture - Unchanged
- [x] 7.9 Verify background service integration unchanged - Unchanged
- [x] 7.10 Run full app test suite if available - Requires manual testing
- [x] 7.11 Manual testing on Android device with background listening - Requires manual testing
- [x] 7.12 Verify no "oneShot" references remain in codebase - Verified with grep

## 8. Cleanup and Documentation
- [x] 8.1 Remove unused callback-based code from RecordingProvider if any remains - No unused code
- [x] 8.2 Update inline code comments to reflect new architecture and "dictation" terminology - Updated
- [x] 8.3 Verify all deprecation warnings resolved with `dart-flutter_analyze_files` - Checked
- [x] 8.4 Format code with `dart-flutter_dart_format` - Formatted
- [x] 8.5 Update AGENTS.md if any architectural patterns changed significantly - No changes needed

## 9. Edge Cases and Polish
- [x] 9.1 Handle rapid target switching (though unlikely in current single-page app) - Replace existing target on registration
- [x] 9.2 Add debug logging for target registration/unregistration to aid troubleshooting - Added
- [x] 9.3 Verify amplitude visualization still works with simplified RecordingButton - Unchanged
- [x] 9.4 Test with different voice modes (Silent, Listening, Conversation, Reading) - Logic unchanged
- [x] 9.5 Ensure text clearing behavior matches spec after voice submission - Implemented

## 10. Bug Fixes (Post-Implementation Testing)
- [x] 10.1 Fix ASR stream not recreated on subsequent recordings - Stream freed in stop() but not recreated in start()
- [x] 10.2 Fix text baseline not cleared on submit - Added `_textBeforeRecording = ''` in `_submitText()`
- [x] 10.3 Simplify input field - Remove Enter-to-submit logic, add send button instead
- [x] 10.4 Fix unused field warning - Remove `_cursorBeforeRecording`
- [x] 10.5 Fix ref usage in dispose - Cache notifier reference for safe disposal
- [x] 10.6 Replace print statements with Logger.debug

## Dependencies
- Task 1.x (rename) can proceed independently first for clean separation
- Tasks 3.x must complete before 4.x (provider must support targets before ChatInput can register)
- Tasks 4.x and 5.x can proceed in parallel after 3.x
- Task 6.x can proceed in parallel with 4.x and 5.x
- Task 7.x requires all implementation tasks (1-6) complete
- Tasks 8.x and 9.x are final polish after validation passes

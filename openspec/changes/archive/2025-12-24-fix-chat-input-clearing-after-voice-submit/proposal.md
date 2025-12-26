# Change: Fix Chat Input Clearing After Voice Submit

## Why

When a chat message is composed using voice input in continuous listening/conversation mode, the input text sometimes does not clear after successful submission. This creates a poor user experience where text appears to persist in the input field even after sending.

The issue occurs because speech recognition continues immediately after submission, repopulating the cleared input field with newly recognized text.

## What Changes

- Fix input clearing behavior in voice input scenarios
- Prevent speech recognition from repopulating cleared input fields after submission
- Ensure consistent input clearing across all submission methods

## Impact

- Affected code: `apps/lib/chat/widgets.dart`, `apps/lib/speech_recognition/widgets.dart`
- User experience improvement for voice input users
- No breaking changes to existing functionality
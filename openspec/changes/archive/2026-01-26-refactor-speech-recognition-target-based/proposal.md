# Change: Refactor Speech Recognition to bind to a specific input

## Why

Current speech recognition architecture uses a global ASR instance with callbacks that don't target specific TextInput destinations, making it impossible to support multiple recording targets and ensuring proper text routing. Also is the logic and interaction of page specific audio modes and the ChatInput and RecordingButton too complex and leads to state errors.

## What Changes

- ASR can only be used in combination with an input
- Refactor ASR class to support target-based speech recognition
- Add TextInput destination binding to speech recognition
- Remove global callbacks in favor of target-specific actions
- Update RecordingProvider to manage targets instead of global state
- Rename "oneShot" to "dictation" throughout codebase (language policy compliance)
- Clarify that submitting input (e.g., pressing Enter) stops dictation mode

## Requirements

- Only one input can receive speech input at a time
- The default input on the Simple Chat page is the ChatInput widget
- A bound recording input sould receive those events: recognized text (replaces
  previous text), end of input (submitting text in continous mode), starting (waiting
indicator), recording (show amplitude visualization), stopped (resets state)
- The recording button is used for all state indication
- If a new target should start receiving speech input, the existing one must be
  stopped first. Setting the input into a non listening state
- A target input should only know about state changes relevant to itself
- One entity must be responsible for changing recording states during a specific
  target.

## Impact

- Affected specs: speech-recognition (new), chat-input (modified)
- Affected code: apps/lib/speech_recognition/services.dart, apps/lib/providers/recording_provider.dart, apps/lib/chat/widgets.dart, apps/lib/speech_recognition/widgets.dart, apps/lib/models/settings.dart

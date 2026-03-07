# chat-input Specification

## Purpose
TBD - created by archiving change fix-chat-input-clearing-after-voice-submit. Update Purpose after archive.
## Requirements
### Requirement: Input Clearing After Successful Submission
The system SHALL clear the chat input field immediately after a successful message submission.

#### Scenario: Text input submission clears field
- **GIVEN** user types text in chat input
- **WHEN** user submits the message (Enter key or submit action)
- **AND** message is successfully sent
- **THEN** the input field SHALL be cleared immediately
- **AND** no text SHALL remain visible in the input field

#### Scenario: Voice input submission clears field
- **GIVEN** user uses voice input in continuous mode
- **WHEN** speech endpoint is detected and message is submitted via `onTextFinished()` callback
- **AND** message is successfully sent
- **THEN** the input field SHALL be cleared immediately
- **AND** subsequent speech recognition SHALL NOT repopulate the cleared field

#### Scenario: Input clearing is immediate
- **GIVEN** user submits a message
- **WHEN** the submission is initiated
- **THEN** input clearing SHALL happen synchronously
- **AND** SHALL NOT wait for server response

### Requirement: RecordingTarget Implementation
The ChatInput widget SHALL implement the RecordingTarget interface to receive speech recognition events directly.

#### Scenario: ChatInput registers as recording target
- **GIVEN** ChatInput widget is initialized
- **WHEN** widget lifecycle reaches post-frame callback
- **THEN** ChatInput SHALL register itself with RecordingProvider via `registerTarget(this)`
- **AND** ChatInput SHALL become the active recording target

#### Scenario: ChatInput unregisters on disposal
- **GIVEN** ChatInput widget is registered as recording target
- **WHEN** widget is disposed (user navigates away or widget unmounts)
- **THEN** ChatInput SHALL call `unregisterTarget(this)` in dispose method
- **AND** RecordingProvider SHALL clear the active target
- **AND** recording SHALL stop if active

#### Scenario: Direct text recognition
- **GIVEN** ChatInput is the active recording target
- **WHEN** RecordingProvider calls `onTextRecognized(text)`
- **THEN** ChatInput SHALL update its TextField controller with the recognized text
- **AND** the text SHALL be visible to the user immediately

#### Scenario: Direct submission on completion
- **GIVEN** ChatInput is the active recording target and continuous listening is enabled
- **WHEN** RecordingProvider calls `onTextFinished()`
- **THEN** ChatInput SHALL invoke its existing `_submitText()` method
- **AND** the message SHALL be sent to the chat provider
- **AND** the input field SHALL be cleared per existing submission behavior

#### Scenario: Error handling from speech recognition
- **GIVEN** ChatInput is the active recording target
- **WHEN** RecordingProvider calls `onError(error)`
- **THEN** ChatInput SHALL handle the error appropriately (log, show snackbar, or ignore)
- **AND** the user SHALL be informed if the error is user-facing

#### Scenario: Recording state feedback
- **GIVEN** ChatInput is the active recording target
- **WHEN** RecordingProvider calls `onRecordingStarted()` or `onRecordingStopped()`
- **THEN** ChatInput MAY update UI to indicate recording state (optional)
- **OR** ChatInput MAY ignore these events if RecordingButton provides sufficient visual feedback

### Requirement: Simplified Widget Integration
The ChatInput widget SHALL use RecordingButton without providing callback props for event routing.

#### Scenario: RecordingButton instantiation without callbacks
- **GIVEN** ChatInput renders RecordingButton
- **WHEN** constructing the RecordingButton widget
- **THEN** ChatInput SHALL NOT provide `onTextRecognized` callback
- **AND** ChatInput SHALL NOT provide `onTextFinished` callback
- **AND** RecordingButton SHALL function independently for visual state and actions

#### Scenario: Independent event flows
- **GIVEN** recording is active via RecordingButton
- **WHEN** speech is recognized or completed
- **THEN** events SHALL flow directly from RecordingProvider to ChatInput
- **AND** RecordingButton SHALL NOT be involved in event routing
- **AND** ChatInput and RecordingButton SHALL remain decoupled

### Requirement: Dictation Stops on Submission
The ChatInput SHALL stop dictation mode when the user submits text, allowing seamless transition from speech input to message sending.

#### Scenario: Enter key stops dictation and submits
- **GIVEN** dictation mode is active via RecordingButton
- **AND** recognized text is displayed in ChatInput
- **WHEN** user presses Enter key
- **THEN** ChatInput SHALL stop dictation via RecordingProvider
- **AND** ChatInput SHALL submit the message
- **AND** the input field SHALL be cleared

#### Scenario: Submit button stops dictation
- **GIVEN** dictation mode is active
- **AND** recognized text is in the input field
- **WHEN** user clicks a submit button or triggers submission
- **THEN** dictation SHALL be stopped automatically
- **AND** the message SHALL be sent
- **AND** user SHALL not need to manually stop dictation first

#### Scenario: Submission during continuous listening
- **GIVEN** continuous listening mode is active (not dictation)
- **WHEN** user submits text
- **THEN** continuous listening SHALL NOT be stopped
- **AND** only the current text SHALL be submitted
- **AND** listening SHALL continue for next input

### Requirement: Input Focus on Chat Open
The chat input SHALL receive focus automatically when a chat opens, allowing immediate text entry or voice input without manual input activation.

#### Scenario: New chat receives focus
- **GIVEN** user creates a new chat (via clear chat action or fresh session)
- **WHEN** the chat page becomes visible
- **THEN** the chat input field SHALL automatically receive focus

#### Scenario: Existing chat receives focus
- **GIVEN** user navigates to a chat with existing message history
- **WHEN** the chat page becomes visible
- **THEN** the chat input field SHALL automatically receive focus

#### Scenario: Focus enables immediate input
- **GIVEN** the chat input has received focus
- **WHEN** user starts typing
- **THEN** text SHALL appear immediately without requiring input field activation
- **AND** voice input activation SHALL work without requiring input field tap


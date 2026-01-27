## ADDED Requirements

### Requirement: Target-Based Speech Recognition
The system SHALL bind speech recognition to specific input targets, ensuring only one target receives speech input at a time.

#### Scenario: Single active target enforcement
- **GIVEN** a recording target is registered
- **WHEN** another target attempts to register
- **THEN** the previous target SHALL be unregistered first
- **AND** only the new target SHALL receive speech recognition events

#### Scenario: Target receives recognized text
- **GIVEN** a target is registered and recording is active
- **WHEN** speech recognition produces partial or final text
- **THEN** the registered target SHALL receive the text via `onTextRecognized()` callback
- **AND** no other components SHALL receive the recognized text

#### Scenario: Target receives completion signal
- **GIVEN** a target is registered and continuous listening is active
- **WHEN** speech endpoint is detected
- **THEN** the registered target SHALL receive completion signal via `onTextFinished()` callback
- **AND** the target SHALL handle text submission

### Requirement: RecordingTarget Interface
The system SHALL define a RecordingTarget interface that input widgets implement to receive speech recognition events.

#### Scenario: Target implements required callbacks
- **GIVEN** a widget wants to receive speech input
- **WHEN** the widget implements RecordingTarget interface
- **THEN** the widget SHALL implement `onTextRecognized(String text)` for text updates
- **AND** the widget SHALL implement `onTextFinished()` for submission signals
- **AND** the widget SHALL implement `onRecordingStarted()` for recording start events
- **AND** the widget SHALL implement `onRecordingStopped()` for recording stop events
- **AND** the widget SHALL implement `onError(String error)` for error handling

#### Scenario: Target lifecycle management
- **GIVEN** a RecordingTarget widget
- **WHEN** the widget is initialized
- **THEN** the widget SHALL register itself with RecordingProvider
- **AND** WHEN the widget is disposed
- **THEN** the widget SHALL unregister itself from RecordingProvider
- **AND** recording SHALL stop if this target was active

### Requirement: RecordingProvider Target Management
The RecordingProvider SHALL manage the currently active RecordingTarget and route all speech events to it.

#### Scenario: Target registration
- **GIVEN** RecordingProvider is initialized
- **WHEN** a target calls `registerTarget(RecordingTarget)`
- **THEN** the target SHALL become the active recording target
- **AND** any previous active target SHALL be cleared

#### Scenario: Target unregistration
- **GIVEN** a target is currently active
- **WHEN** the target calls `unregisterTarget(RecordingTarget)`
- **THEN** the active target SHALL be cleared
- **AND** recording SHALL stop if active
- **AND** subsequent speech events SHALL not be delivered

#### Scenario: Safe recording without target
- **GIVEN** no target is registered
- **WHEN** recording is attempted
- **THEN** the system SHALL either prevent recording start or safely ignore events
- **AND** no crashes or errors SHALL occur

### Requirement: Direct Event Routing
The system SHALL route speech recognition events directly from RecordingProvider to the active target without intermediate callbacks.

#### Scenario: Text recognition event routing
- **GIVEN** recording is active with a registered target
- **WHEN** ASR produces recognized text
- **THEN** RecordingProvider SHALL call `activeTarget.onTextRecognized(text)` directly
- **AND** no callback chains through other widgets SHALL be used

#### Scenario: Completion event routing
- **GIVEN** continuous listening is active with a registered target
- **WHEN** speech endpoint is detected
- **THEN** RecordingProvider SHALL call `activeTarget.onTextFinished()` directly
- **AND** the target SHALL handle submission without additional coordination

#### Scenario: Error event routing
- **GIVEN** recording is active with a registered target
- **WHEN** an ASR error occurs
- **THEN** RecordingProvider SHALL call `activeTarget.onError(error)` directly
- **AND** the target SHALL handle error display or logging

### Requirement: Simplified Recording Button
The RecordingButton widget SHALL focus solely on displaying recording state and triggering recording actions, without routing speech events.

#### Scenario: Button triggers recording actions
- **GIVEN** RecordingButton is displayed
- **WHEN** user taps the button to start recording
- **THEN** the button SHALL call RecordingProvider start methods (e.g., `startDictation()`)
- **AND** the button SHALL NOT need to know about the target
- **AND** RecordingProvider SHALL route events to the registered target

#### Scenario: Button displays recording state
- **GIVEN** RecordingButton is displayed
- **WHEN** recording state changes in RecordingProvider
- **THEN** the button SHALL update its visual state (icon, visualizer)
- **AND** the button SHALL NOT forward text or completion events

#### Scenario: Button removed from event routing
- **GIVEN** speech recognition is active
- **WHEN** text is recognized or recording completes
- **THEN** the button SHALL NOT receive text events
- **AND** the button SHALL NOT forward events via callbacks
- **AND** events SHALL flow directly from provider to target

### Requirement: Dictation Mode Terminology
The system SHALL use "dictation" terminology instead of "oneShot" for manual speech-to-text input sessions.

#### Scenario: Method naming uses dictation
- **GIVEN** the codebase contains recording methods
- **WHEN** methods for manual speech input are named
- **THEN** they SHALL use "dictation" terminology (e.g., `startDictation()`, `stopDictation()`)
- **AND** they SHALL NOT use "oneShot" terminology for language policy compliance

#### Scenario: Comments and documentation use dictation
- **GIVEN** code comments and documentation describe manual speech input
- **WHEN** referring to the recording mode
- **THEN** the term "dictation mode" SHALL be used
- **AND** "one-shot recording" SHALL NOT be used

### Requirement: Dictation Stops on Input Submission
When dictation mode is active and the user submits the input field, the system SHALL stop dictation automatically.

#### Scenario: Enter key stops dictation and submits
- **GIVEN** dictation mode is active with text in the input field
- **WHEN** user presses Enter key to submit
- **THEN** dictation SHALL stop immediately
- **AND** the text SHALL be submitted
- **AND** the input field SHALL be cleared per submission behavior

#### Scenario: Submit action stops dictation
- **GIVEN** dictation mode is active
- **WHEN** user triggers any input submission action (button, keyboard shortcut, etc.)
- **THEN** dictation SHALL stop before or during submission
- **AND** submission SHALL proceed normally
- **AND** user SHALL not need to manually stop dictation first

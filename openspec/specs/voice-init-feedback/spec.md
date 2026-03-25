## Purpose

Provide visible feedback to the user when voice recognition models are being loaded, preventing apparent UI freeze during the blocking initialization.

## Requirements

### Requirement: Voice Initialization Overlay
The app SHALL display a visible full-screen overlay when voice models are being loaded for the first time, so the user sees an informative message instead of a frozen UI.

#### Scenario: Overlay shown during first ASR initialization
- **WHEN** the user starts recording for the first time in a session
- **AND** the ASR recognizer has not been initialized yet
- **THEN** a full-screen semi-transparent overlay SHALL be displayed
- **AND** it SHALL show a message like "Initializing voice recognition…"
- **AND** it SHALL indicate that the operation may take a few seconds

#### Scenario: Overlay visible before UI freezes
- **WHEN** the recording provider sets `isInitializing` to true
- **THEN** the overlay SHALL be rendered in the current frame
- **AND** the blocking model loading SHALL start only after the overlay frame is painted
- **AND** the user SHALL see the overlay message during the freeze

#### Scenario: Overlay dismissed after initialization completes
- **WHEN** the ASR recognizer has finished loading
- **THEN** the overlay SHALL be removed
- **AND** recording SHALL proceed normally

#### Scenario: Overlay not shown on subsequent recordings
- **WHEN** the user starts a second or later recording in the same session
- **AND** the ASR recognizer is already initialized
- **THEN** no overlay SHALL be displayed
- **AND** recording SHALL start immediately

#### Scenario: Overlay blocks user interaction
- **WHEN** the initialization overlay is displayed
- **THEN** user interaction with the underlying UI SHALL be blocked
- **AND** the overlay SHALL absorb all touch/click events

#### Scenario: Overlay shown globally regardless of active page
- **WHEN** the initialization overlay is triggered
- **THEN** it SHALL appear over the entire app UI
- **AND** it SHALL NOT be tied to a specific page or route

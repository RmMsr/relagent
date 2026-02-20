## MODIFIED Requirements

### Requirement: Settings Page Layout

The system SHALL organize settings into sections, with voice-related sections conditionally visible based on platform voice capabilities. The chat backend switch SHALL toggle visibility of the relevant input sections without affecting their stored values.

#### Scenario: Engine settings section
- **GIVEN** the user opens the settings page
- **WHEN** the page is displayed
- **THEN** an "Engine" section SHALL be visible when the Relagent Engine backend is selected
- **AND** it SHALL contain Engine URL and authentication settings

#### Scenario: Simple chat settings section
- **GIVEN** the user opens the settings page
- **WHEN** the page is displayed
- **THEN** the "API" section for simple chat SHALL be visible when the OpenAI-compatible backend is selected

#### Scenario: Backend switch preserves input values
- **GIVEN** the user has entered a base URL for OpenAI-compatible mode
- **WHEN** the user switches to Relagent Engine backend
- **AND** then switches back to OpenAI-compatible backend
- **THEN** the previously entered base URL SHALL still be present in the input field
- **AND** no values from engine inputs SHALL appear in OpenAI-compatible inputs or vice versa

#### Scenario: Voice settings hidden when unavailable
- **GIVEN** the user opens the settings page on a platform without voice capabilities
- **WHEN** the page is displayed
- **THEN** the voice mode selector SHALL NOT be displayed
- **AND** the background listening duration setting SHALL NOT be displayed
- **AND** TTS-related settings (speaker, speed) SHALL NOT be displayed

#### Scenario: Voice settings visible when available
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the page is displayed
- **THEN** the voice mode selector SHALL be displayed
- **AND** the background listening duration setting SHALL be displayed
- **AND** TTS-related settings SHALL be displayed

## ADDED Requirements

### Requirement: Chat app bar has no settings button
The chat pages SHALL NOT display a settings icon button in the app bar. Settings SHALL be accessible only via the navigation drawer.

#### Scenario: Simple chat page app bar
- **WHEN** the simple chat page is displayed
- **THEN** the app bar SHALL NOT contain a settings icon button
- **AND** settings SHALL be reachable via the navigation drawer

#### Scenario: Agentic chat page app bar
- **WHEN** the agentic chat page is displayed
- **THEN** the app bar SHALL NOT contain a settings icon button
- **AND** settings SHALL be reachable via the navigation drawer

### Requirement: Consistent settings save behavior
Settings SHALL only be persisted when the user explicitly presses the "Save" button. No implicit saves SHALL occur from field navigation or editing completion.

#### Scenario: Enter key moves to next field
- **GIVEN** the user is editing the API Base URL field
- **WHEN** the user presses Enter
- **THEN** focus SHALL move to the next field (e.g., Model Name)
- **AND** settings SHALL NOT be saved

#### Scenario: Tab key moves to next field
- **GIVEN** the user is editing any text field
- **WHEN** the user presses Tab
- **THEN** focus SHALL move to the next field
- **AND** settings SHALL NOT be saved

#### Scenario: Model name field does not auto-save
- **GIVEN** the user is editing the Model Name field
- **WHEN** the user presses Enter or completes editing
- **THEN** focus SHALL move to the next field
- **AND** settings SHALL NOT be saved until the Save button is pressed

### Requirement: Engine base URL change resets engine state
When the engine base URL is changed to a different value, the system SHALL reset all engine-specific state to prevent stale data from the previous engine.

#### Scenario: Engine URL change clears session
- **GIVEN** the user has an active agentic session
- **WHEN** the user changes the engine base URL and saves settings
- **THEN** the agentic session ID SHALL be cleared
- **AND** the chat messages SHALL be cleared on next load

#### Scenario: Engine URL change clears SSE state
- **GIVEN** the app has a persisted SSE last event ID
- **WHEN** the user changes the engine base URL and saves settings
- **THEN** the persisted last event ID SHALL be cleared to zero
- **AND** the SSE connection SHALL reconnect from the beginning

#### Scenario: Engine URL change clears sessions list
- **GIVEN** the user has a list of recent sessions from the previous engine
- **WHEN** the user changes the engine base URL and saves settings
- **THEN** the sessions list SHALL be cleared

#### Scenario: Engine URL change clears health check
- **GIVEN** a previous engine health check result exists
- **WHEN** the user changes the engine base URL and saves settings
- **THEN** the engine health check result SHALL be cleared

### Requirement: Autocomplete closes on focus lost
All autocomplete dropdowns on the settings page SHALL automatically close when the user moves focus to another input field, ensuring a clean UI without orphaned suggestion lists.

#### Scenario: Autocomplete closes when tapping another field
- **GIVEN** the user has opened the API Base URL autocomplete suggestions
- **WHEN** the user taps on the Model Name field
- **THEN** the autocomplete suggestions dropdown SHALL close immediately
- **AND** focus SHALL move to the Model Name field

#### Scenario: Autocomplete closes when tabbing to next field
- **GIVEN** the user has opened autocomplete suggestions on any field
- **WHEN** the user presses Tab to move to the next field
- **THEN** the autocomplete suggestions dropdown SHALL close
- **AND** focus SHALL move to the next field

#### Scenario: Autocomplete closes when selecting from suggestions
- **GIVEN** the user has opened autocomplete suggestions
- **WHEN** the user selects an option from the dropdown
- **THEN** the suggestions dropdown SHALL close
- **AND** the selected value SHALL populate the field

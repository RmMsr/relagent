## ADDED Requirements

### Requirement: Web Build Compiles and Runs
The Flutter app SHALL compile for web (`flutter build web`) without errors and run in modern browsers (Chrome, Firefox, Safari, Edge).

#### Scenario: Web build succeeds
- **WHEN** `flutter build web` is executed
- **THEN** the build SHALL complete without compilation errors
- **AND** the output SHALL be a functional web application

#### Scenario: App loads in browser
- **WHEN** the web build is served and opened in a modern browser
- **THEN** the app SHALL load and display the chat page
- **AND** no JavaScript console errors SHALL occur from missing native dependencies

### Requirement: Chat Functionality on Web
The web app SHALL provide full text-based chat functionality including message input, API communication, and message display.

#### Scenario: Text chat works on web
- **WHEN** the user types a message and submits it on web
- **THEN** the message SHALL be sent to the configured API endpoint
- **AND** the response SHALL be displayed in the chat

#### Scenario: Settings page works on web
- **WHEN** the user navigates to settings on web
- **THEN** API configuration settings (base URL, model name) SHALL be editable
- **AND** settings SHALL persist using browser localStorage via SharedPreferences

#### Scenario: Navigation works on web
- **WHEN** the user navigates between chat and settings pages
- **THEN** go_router navigation SHALL function correctly
- **AND** browser back/forward buttons SHALL work

### Requirement: Voice UI Hidden on Web
The system SHALL hide voice-related UI elements when voice capabilities are unavailable.

#### Scenario: Recorder button hidden on web
- **WHEN** the chat page is displayed on web
- **THEN** the RecorderButton (microphone button) SHALL NOT be visible
- **AND** the chat input area SHALL use a text-only layout

#### Scenario: Volume visualizer hidden on web
- **WHEN** the chat page is displayed on web
- **THEN** the VolumeBarVisualizer SHALL NOT be rendered
- **AND** the RecordingStateIndicator SHALL NOT be rendered

#### Scenario: Voice mode settings hidden on web
- **WHEN** the settings page is displayed on web
- **THEN** voice mode selector SHALL NOT be visible
- **AND** background listening duration setting SHALL NOT be visible
- **AND** TTS speaker and speed settings SHALL NOT be visible

#### Scenario: TTS play buttons hidden on web
- **WHEN** assistant messages are displayed on web
- **THEN** the TTS play/pause button on each message SHALL NOT be visible

### Requirement: Capability-Based UI Guards
The system SHALL use `VoiceCapabilities` queries (not `kIsWeb` directly) to determine whether to show voice UI elements.

#### Scenario: Guards use capability provider
- **WHEN** a widget decides whether to show a voice control
- **THEN** it SHALL query the voice capabilities provider
- **AND** it SHALL NOT check `kIsWeb` directly

#### Scenario: Guards work for future platforms
- **WHEN** a native platform lacks a specific voice capability (e.g., no microphone)
- **THEN** the same capability guard SHALL correctly hide the relevant UI
- **AND** no platform-specific checks SHALL be needed in widget code

### Requirement: Web Asset Handling
Large model assets SHALL not prevent web builds from functioning, even if they remain declared in pubspec.yaml.

#### Scenario: Web app loads without model assets
- **WHEN** the web app starts
- **THEN** the stub VoiceService SHALL NOT attempt to load model files
- **AND** the app SHALL function normally without model assets being available at runtime

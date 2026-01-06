# background-audio-management Specification

## Purpose
TBD - created by archiving change add-reliable-background-listening. Update Purpose after archive.
## Requirements
### Requirement: Audio Stream Health Monitoring
The system SHALL continuously monitor the health of audio recording streams during active listening sessions.

#### Scenario: Periodic health check passes
- **GIVEN** the app is in continuous listening mode
- **WHEN** the periodic health check runs
- **AND** the audio stream state is recording
- **AND** audio data was received within the last 2 minutes
- **THEN** health check passes and recording continues normally

#### Scenario: Health check detects stopped stream
- **GIVEN** the app is in continuous listening mode
- **WHEN** the periodic health check runs
- **AND** the audio stream state is NOT recording
- **THEN** the system SHALL attempt automatic recovery

#### Scenario: Health check detects silent stream
- **GIVEN** the app is in continuous listening mode
- **WHEN** the periodic health check runs
- **AND** no audio data has been received for more than 2 minutes
- **THEN** the system SHALL attempt automatic recovery

### Requirement: Automatic Recovery from Audio Failures
The system SHALL attempt to automatically recover from audio recording failures using exponential backoff.

#### Scenario: First recovery attempt succeeds
- **GIVEN** a health check has detected an audio failure
- **WHEN** the first recovery attempt is made
- **THEN** the system SHALL immediately stop and restart the audio stream
- **AND** if successful, recording SHALL resume normally
- **AND** the recovery attempt counter SHALL be reset

#### Scenario: Second recovery attempt succeeds
- **GIVEN** the first recovery attempt failed
- **WHEN** the second recovery attempt is made
- **THEN** the system SHALL wait 2 seconds before restarting
- **AND** if successful, recording SHALL resume normally
- **AND** the recovery attempt counter SHALL be reset

#### Scenario: Third recovery attempt succeeds
- **GIVEN** the first two recovery attempts failed
- **WHEN** the third recovery attempt is made
- **THEN** the system SHALL wait 5 seconds before restarting
- **AND** if successful, recording SHALL resume normally
- **AND** the recovery attempt counter SHALL be reset

#### Scenario: All recovery attempts fail
- **GIVEN** three recovery attempts have been made
- **WHEN** all attempts have failed
- **THEN** the system SHALL transition to graceful degradation

### Requirement: Graceful Degradation to Silent Mode
The system SHALL gracefully degrade to Silent voice mode when audio recording cannot be recovered.

#### Scenario: Degradation after recovery failure
- **GIVEN** all recovery attempts have failed
- **WHEN** graceful degradation is triggered
- **THEN** the voice mode SHALL be changed to Silent
- **AND** a notification SHALL be displayed to the user
- **AND** the notification SHALL contain the message "Listening stopped - could not recover audio recording"
- **AND** the notification SHALL include an "Open Settings" action
- **AND** health monitoring SHALL be stopped
- **AND** audio resources SHALL be released

#### Scenario: No automatic re-enable after degradation
- **GIVEN** the system has degraded to Silent mode due to recovery failure
- **WHEN** the user does not manually change the voice mode
- **THEN** the system SHALL NOT automatically attempt to re-enable listening
- **AND** the system SHALL remain in Silent mode

### Requirement: Time-Limited Background Listening
The system SHALL support user-configurable time limits for background listening sessions.

#### Scenario: Timeout after configured duration
- **GIVEN** the user has set background listening duration to 1 hour
- **WHEN** continuous listening starts
- **AND** 1 hour passes
- **THEN** the voice mode SHALL automatically change to Silent
- **AND** audio recording SHALL stop
- **AND** resources SHALL be released normally

#### Scenario: Unlimited duration setting
- **GIVEN** the user has set background listening duration to unlimited
- **WHEN** continuous listening starts
- **THEN** no timeout timer SHALL be created
- **AND** listening SHALL continue indefinitely until manually stopped

#### Scenario: Duration timer cancelled on manual stop
- **GIVEN** continuous listening is active with a timeout timer
- **WHEN** the user manually stops listening before timeout
- **THEN** the timeout timer SHALL be cancelled
- **AND** no automatic transition to Silent SHALL occur

### Requirement: Audio Stream Error Detection
The system SHALL detect and handle errors from the audio input stream.

#### Scenario: Stream error detected
- **GIVEN** audio recording is active
- **WHEN** the audio stream emits an error event
- **THEN** the error SHALL be logged
- **AND** automatic recovery SHALL be triggered
- **AND** the error SHALL be stored in recording state

#### Scenario: Stream unexpectedly closes
- **GIVEN** audio recording is active
- **WHEN** the audio stream onDone event fires without an explicit stop call
- **THEN** the unexpected closure SHALL be logged
- **AND** automatic recovery SHALL be triggered

### Requirement: Audio Data Flow Tracking
The system SHALL track when audio data is received to detect silent failures.

#### Scenario: Audio data timestamp updated
- **GIVEN** audio recording is active
- **WHEN** an audio data chunk is received from the stream
- **THEN** the last audio data timestamp SHALL be updated to current time
- **AND** the timestamp SHALL be accessible for health monitoring

#### Scenario: Data flow timeout detection
- **GIVEN** audio recording is active
- **WHEN** the health check runs
- **AND** current time minus last audio data timestamp exceeds 2 minutes
- **THEN** a data flow timeout SHALL be detected
- **AND** automatic recovery SHALL be triggered

### Requirement: Wake Lock Duration Management
The system SHALL manage Android wake lock duration based on user-configured time limits.

#### Scenario: Wake lock timeout for limited duration
- **GIVEN** the user has set background listening duration to 1 hour
- **WHEN** the audio background service starts
- **THEN** the wake lock SHALL be acquired with a timeout of 65 minutes (duration + 5 minute buffer)

#### Scenario: Wake lock timeout for unlimited duration
- **GIVEN** the user has set background listening duration to unlimited
- **WHEN** the audio background service starts
- **THEN** the wake lock SHALL be acquired with a timeout of 24 hours

#### Scenario: Wake lock released on service stop
- **GIVEN** the audio background service is running with an active wake lock
- **WHEN** the service stops
- **THEN** the wake lock SHALL be released immediately

### Requirement: End Time Display
The system SHALL display end time in the foreground notification when background listening has a time limit.

#### Scenario: Notification shows end time
- **GIVEN** continuous listening is active with 1 hour duration limit
- **WHEN** 20 minutes have passed
- **THEN** the notification content SHALL display "Listening... (ends at 3:45 PM)"
- **AND** the time SHALL update every 60 seconds

#### Scenario: Notification omits time for unlimited
- **GIVEN** continuous listening is active with unlimited duration
- **WHEN** the notification is displayed
- **THEN** the notification SHALL NOT include remaining time text
- **AND** the notification SHALL display "Listening..." only

### Requirement: Health Monitoring Lifecycle
The system SHALL start and stop health monitoring aligned with recording lifecycle.

#### Scenario: Health monitoring starts with continuous recording
- **GIVEN** the user enables continuous listening
- **WHEN** audio recording starts
- **THEN** health monitoring SHALL be started
- **AND** a periodic timer SHALL be created (30 second interval)

#### Scenario: Health monitoring stops when leaving continuous mode
- **GIVEN** health monitoring is active
- **WHEN** the user disables continuous listening
- **THEN** the health monitoring timer SHALL be cancelled
- **AND** health monitoring state SHALL be reset

#### Scenario: Recovery counter resets on successful recording
- **GIVEN** recovery attempts have been made (counter > 0)
- **WHEN** audio recording is successfully established
- **AND** at least one health check passes
- **THEN** the recovery attempt counter SHALL be reset to 0

### Requirement: Notification Permission Check on Service Start

The system SHALL check and request notification permission when the background audio service starts.

#### Scenario: Permission granted

- **WHEN** continuous audio mode is activated and background service starts
- **AND** notification permission is not granted
- **THEN** the system SHALL request notification permission using Android's newer interface
- **AND** if granted, service SHALL start normally

#### Scenario: Permission denied

- **WHEN** notification permission is requested
- **AND** user denies permission
- **THEN** the system SHALL show appropriate error message
- **AND** service SHALL not start or SHALL degrade gracefully


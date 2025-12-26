## ADDED Requirements

### Requirement: Recording State Visualization

The recording button SHALL display distinct visual states for each recording mode to provide clear feedback to users.

#### Scenario: Idle state (not recording)

- **WHEN** voice mode is Silent or Reading and recording is not active
- **THEN** button displays a static microphone icon indicating "ready to record"
- **AND** clicking the button initiates recording

#### Scenario: Initializing state (starting up)

- **WHEN** user starts recording and ASR is initializing
- **THEN** button displays a loading animation or spinner
- **AND** button is non-interactive until initialization completes (typically < 1 second)

#### Scenario: Active recording state (manual)

- **WHEN** recording is active in manual mode (Silent or Reading voice modes)
- **THEN** button displays volume bars showing audio amplitude
- **AND** button shows a stop icon or indication that clicking will stop recording

#### Scenario: Continuous recording state (always listening)

- **WHEN** voice mode is Listening or Conversation and recording is active
- **THEN** button displays volume bars showing audio amplitude (same as manual recording)
- **AND** button shows indication that clicking will turn off continuous mode

#### Scenario: Paused state (interrupted)

- **WHEN** recording is paused due to audio interruption (e.g., phone call)
- **THEN** button displays a distinct pause icon or frozen volume bars
- **AND** visual indicates recording is suspended but will resume

#### Scenario: Error state

- **WHEN** recording encounters an error (permission denied, hardware failure, etc.)
- **THEN** button displays an error icon with appropriate color (e.g., red)
- **AND** error state is visually distinct from all other states

### Requirement: Audio Signal Amplitude Visualization

The recording button SHALL display real-time audio signal strength using animated vertical bars during active recording.

#### Scenario: Volume bars display during recording

- **WHEN** recording is active (manual or continuous mode)
- **THEN** 5 vertical bars are displayed centered horizontally in the button
- **AND** bar heights represent recent audio amplitude levels
- **AND** bars update smoothly as new audio data arrives

#### Scenario: Volume bars animation direction

- **WHEN** new audio data is captured
- **THEN** new amplitude data appears on the right side
- **AND** existing data shifts left (right-to-left flow)
- **AND** animation creates a flowing effect showing audio activity

#### Scenario: Volume bars during silence

- **WHEN** recording is active but no audio is detected
- **THEN** all bars display at minimum height
- **AND** bars remain visible to show recording is active

#### Scenario: Volume bars hide when not recording

- **WHEN** recording is stopped or in idle state
- **THEN** volume bars are not displayed
- **AND** appropriate state icon is shown instead

### Requirement: Audio Quality Indicator

The recording button SHALL provide visual feedback about audio quality issues to help users troubleshoot recording problems.

#### Scenario: Low signal detection

- **WHEN** audio amplitude is consistently below threshold (e.g., < -40 dBFS)
- **THEN** button displays a low-signal warning indicator (e.g., amber color or icon)
- **AND** volume bars remain visible with warning overlay

#### Scenario: Noise or clipping detection

- **WHEN** audio amplitude is too high (near 0 dBFS) or highly erratic
- **THEN** button displays a noise/clipping warning (e.g., red color or icon)
- **AND** indicates audio quality may be degraded

#### Scenario: Good audio quality

- **WHEN** audio amplitude is in acceptable range (-40 to -10 dBFS)
- **THEN** no quality warning is displayed
- **AND** volume bars show normal visualization without overlay

#### Scenario: Quality indicator does not block interaction

- **WHEN** quality warning is displayed
- **THEN** button remains clickable and functional
- **AND** quality indicator does not prevent stopping/starting recording

### Requirement: Visual State Transitions

The recording button SHALL provide smooth, clear transitions between states to avoid visual confusion.

#### Scenario: Smooth state transitions

- **WHEN** recording state changes (e.g., idle to initializing to recording)
- **THEN** visual elements transition smoothly with brief animation (< 300ms)
- **AND** new state is immediately recognizable

#### Scenario: Immediate error indication

- **WHEN** an error occurs during recording
- **THEN** error state is displayed immediately without delay
- **AND** previous state visualization is replaced

#### Scenario: No performance degradation

- **WHEN** volume bars are animating during recording
- **THEN** UI remains responsive and smooth (60 fps minimum)
- **AND** animations do not cause battery drain or CPU spikes

### Requirement: Amplitude Data Integration

The system SHALL integrate amplitude monitoring from the audio recorder into the recording state management.

#### Scenario: Amplitude stream integration

- **WHEN** recording starts
- **THEN** amplitude monitoring stream is activated
- **AND** amplitude values are delivered at regular intervals (e.g., 100ms)

#### Scenario: Amplitude data callback

- **WHEN** new amplitude data arrives
- **THEN** RecordingProvider updates amplitude in RecordingState
- **AND** UI components observing the state are notified

#### Scenario: Amplitude stream cleanup

- **WHEN** recording stops
- **THEN** amplitude monitoring stream is cancelled
- **AND** resources are properly released

### Requirement: Documentation Synchronization

The audio mode documentation SHALL be updated to reflect the visual states and remain synchronized with implementation.

#### Scenario: Documentation describes all states

- **WHEN** documentation is reviewed
- **THEN** each visual state (idle, initializing, active, continuous, paused, error) is described
- **AND** screenshots or diagrams illustrate the states

#### Scenario: Quality indicator documentation

- **WHEN** users encounter quality warnings
- **THEN** documentation explains what each indicator means
- **AND** troubleshooting steps are provided for quality issues

#### Scenario: Documentation stays current

- **WHEN** visual states are modified in code
- **THEN** documentation is updated in the same change
- **AND** no state mismatches exist between code and docs

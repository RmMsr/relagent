# bluetooth-audio-routing Specification Delta

## ADDED Requirements

### Requirement: Automatic Bluetooth Microphone Routing for ASR

The system SHALL automatically route speech recognition audio input to a connected Bluetooth headset microphone when available.

#### Scenario: Bluetooth headset connected at recording start

- **GIVEN** a Bluetooth headset is connected and paired
- **WHEN** the user starts continuous listening or push-to-talk recording
- **THEN** the system SHALL use the Bluetooth microphone as the audio input source
- **AND** the Android AudioManager SHALL use communication mode (Bluetooth SCO)
- **AND** the audio session SHALL be configured with voiceCommunication usage

#### Scenario: Bluetooth headset connects during active recording

- **GIVEN** the app is actively recording audio from the phone microphone
- **WHEN** a Bluetooth headset connects and pairs
- **THEN** the system SHALL detect the device change
- **AND** the system SHALL seamlessly switch audio input to the Bluetooth microphone
- **AND** recording SHALL continue without interruption or dropouts

#### Scenario: Bluetooth headset disconnects during active recording

- **GIVEN** the app is actively recording audio from a Bluetooth microphone
- **WHEN** the Bluetooth headset disconnects (out of range, powered off, etc.)
- **THEN** the system SHALL detect the device change
- **AND** the system SHALL seamlessly switch audio input to the phone microphone
- **AND** recording SHALL continue without interruption
- **AND** health monitoring SHALL NOT trigger false recovery attempts

#### Scenario: No Bluetooth headset available

- **GIVEN** no Bluetooth audio devices are connected
- **WHEN** the user starts recording
- **THEN** the system SHALL use the phone's built-in microphone
- **AND** no errors or warnings SHALL be displayed

#### Scenario: Bluetooth microphone quality monitoring

- **GIVEN** the app is recording from a Bluetooth microphone
- **WHEN** audio data is received from the Bluetooth input
- **THEN** the health monitoring system SHALL track audio data flow normally
- **AND** the system SHALL apply the same health checks as phone microphone
- **AND** ASR processing SHALL work identically to phone microphone input

### Requirement: Automatic Bluetooth Speaker Routing for TTS

The system SHALL automatically route text-to-speech audio output to connected Bluetooth headset speakers when available.

#### Scenario: Bluetooth headset connected at playback start

- **GIVEN** a Bluetooth headset is connected and paired
- **WHEN** the system starts TTS playback
- **THEN** the system SHALL route audio output to the Bluetooth speakers
- **AND** the audio session SHALL be configured with allowBluetooth category options
- **AND** playback quality SHALL be comparable to phone speaker quality

#### Scenario: Bluetooth headset connects during active playback

- **GIVEN** TTS is actively playing through the phone speaker
- **WHEN** a Bluetooth headset connects and pairs
- **THEN** the system SHALL detect the device change
- **AND** the system SHALL seamlessly switch audio output to the Bluetooth speakers
- **AND** playback SHALL continue without interruption

#### Scenario: Bluetooth headset disconnects during active playback

- **GIVEN** TTS is actively playing through Bluetooth speakers
- **WHEN** the Bluetooth headset disconnects
- **THEN** the system SHALL detect the device change
- **AND** the system SHALL seamlessly switch audio output to the phone speaker
- **AND** playback SHALL continue without interruption

#### Scenario: No Bluetooth headset available for playback

- **GIVEN** no Bluetooth audio devices are connected
- **WHEN** the system starts TTS playback
- **THEN** the system SHALL use the phone's built-in speaker
- **AND** no errors or warnings SHALL be displayed

### Requirement: Mode-Specific Audio Session Configuration

The system SHALL configure the audio session differently for recording mode versus playback mode to optimize Bluetooth routing.

#### Scenario: Audio session configured for recording mode

- **GIVEN** the audio coordinator transitions to recording mode
- **WHEN** the background service configures the audio session
- **THEN** the system SHALL use playAndRecord category (iOS)
- **AND** the system SHALL enable allowBluetooth and defaultToSpeaker category options (iOS)
- **AND** the system SHALL use voiceCommunication audio usage (Android)
- **AND** the system SHALL use speech content type (Android)
- **AND** the audio session SHALL be activated

#### Scenario: Audio session configured for playback mode

- **GIVEN** the audio coordinator transitions to playback mode
- **WHEN** the background service configures the audio session
- **THEN** the system SHALL use playback category (iOS)
- **AND** the system SHALL enable allowBluetooth category option (iOS)
- **AND** the system SHALL use media audio usage (Android)
- **AND** the system SHALL use speech content type (Android)
- **AND** the audio session SHALL be activated

#### Scenario: Audio session configuration failure

- **GIVEN** the system attempts to configure the audio session
- **WHEN** the configuration fails with an error
- **THEN** the system SHALL log the error for debugging
- **AND** the system SHALL continue with the previous audio session configuration
- **AND** audio recording or playback SHALL continue to work (possibly without Bluetooth)

### Requirement: Bluetooth Device Change Detection

The system SHALL detect when Bluetooth audio devices connect or disconnect and log these events for debugging and potential adaptation.

#### Scenario: Bluetooth device connects

- **GIVEN** the app is running (idle, recording, or playing)
- **WHEN** a Bluetooth audio device connects and becomes available
- **THEN** the system SHALL receive a device change notification
- **AND** the system SHALL log the available input devices
- **AND** the system SHALL log the available output devices
- **AND** if the audio coordinator is in recording or playback mode, the system MAY reconfigure the audio session

#### Scenario: Bluetooth device disconnects

- **GIVEN** the app is using a Bluetooth audio device
- **WHEN** the Bluetooth device disconnects
- **THEN** the system SHALL receive a device change notification
- **AND** the system SHALL log the remaining available devices
- **AND** the system SHALL automatically fall back to phone audio without user intervention

#### Scenario: Device change during idle mode

- **GIVEN** the audio coordinator is in idle mode (no recording or playback)
- **WHEN** a Bluetooth device connects or disconnects
- **THEN** the system SHALL log the device change
- **AND** the system SHALL NOT reconfigure the audio session
- **AND** the next recording or playback session SHALL use the newly available device

### Requirement: Android Bluetooth Permissions

The system SHALL request appropriate Bluetooth permissions based on the Android API level to enable device detection and connection.

#### Scenario: Android 12+ Bluetooth permission

- **GIVEN** the app is installed on an Android 12 (API 31) or higher device
- **WHEN** the app manifest is processed
- **THEN** the BLUETOOTH_CONNECT permission SHALL be declared
- **AND** the system SHALL request this permission at runtime if needed
- **AND** if permission is denied, the app SHALL continue to function with phone audio only

#### Scenario: Android pre-12 Bluetooth support

- **GIVEN** the app is installed on an Android device below API 31
- **WHEN** the app starts
- **THEN** the MODIFY_AUDIO_SETTINGS permission (already present) SHALL be sufficient
- **AND** Bluetooth audio routing SHALL work without additional permissions

#### Scenario: Bluetooth permission denial

- **GIVEN** the user denies the BLUETOOTH_CONNECT permission on Android 12+
- **WHEN** the app attempts to use audio features
- **THEN** the system SHALL fall back to phone audio devices
- **AND** no errors or crashes SHALL occur
- **AND** the app SHALL continue to function normally with phone microphone and speaker

### Requirement: Bluetooth Audio Profile Management

The system SHALL use appropriate Bluetooth audio profiles for recording versus playback to optimize quality and compatibility.

#### Scenario: Bluetooth SCO for recording

- **GIVEN** the app is in recording mode with a Bluetooth headset connected
- **WHEN** audio recording starts
- **THEN** the system SHALL use Bluetooth SCO (Synchronous Connection-Oriented) profile
- **AND** the Android AudioManager SHALL be in communication mode
- **AND** echo cancellation SHALL be enabled automatically
- **AND** audio SHALL be mono with voice-optimized quality

#### Scenario: Bluetooth A2DP for playback

- **GIVEN** the app is in playback mode with a Bluetooth headset connected
- **WHEN** TTS audio playback starts
- **THEN** the system SHALL use Bluetooth A2DP (Advanced Audio Distribution Profile) profile
- **AND** audio quality SHALL be optimized for media playback
- **AND** audio MAY be stereo depending on the device and content

#### Scenario: Profile switching during mode transitions

- **GIVEN** the app transitions from recording to playback (or vice versa)
- **WHEN** the audio mode changes
- **THEN** the system SHALL reconfigure the audio session for the new mode
- **AND** Bluetooth profile switching SHALL happen automatically via the OS
- **AND** the transition SHALL be seamless without audio dropouts

### Requirement: Audio Focus Handling with Bluetooth Devices

The system SHALL maintain existing audio focus handling behavior when using Bluetooth audio devices.

#### Scenario: Phone call interrupts Bluetooth recording

- **GIVEN** the app is recording from a Bluetooth microphone
- **WHEN** an incoming phone call arrives
- **THEN** the audio coordinator SHALL receive a temporary focus loss event
- **AND** recording SHALL pause
- **AND** the phone call SHALL use the Bluetooth headset
- **WHEN** the call ends
- **THEN** the audio coordinator SHALL regain focus
- **AND** recording SHALL resume using the Bluetooth microphone

#### Scenario: Phone call interrupts Bluetooth playback

- **GIVEN** the app is playing TTS through Bluetooth speakers
- **WHEN** an incoming phone call arrives
- **THEN** the audio coordinator SHALL receive a temporary focus loss event
- **AND** TTS playback SHALL pause
- **AND** the phone call SHALL use the Bluetooth headset
- **WHEN** the call ends
- **THEN** the audio coordinator SHALL regain focus
- **AND** TTS playback SHALL resume using the Bluetooth speakers

#### Scenario: User starts music app during Bluetooth session

- **GIVEN** the app is using Bluetooth audio (recording or playback)
- **WHEN** the user starts a music app
- **THEN** the audio coordinator SHALL receive a permanent focus loss event
- **AND** the system SHALL transition to silent mode
- **AND** the Bluetooth device SHALL be available for the music app

### Requirement: Background Listening Bluetooth Support

The system SHALL support Bluetooth audio devices during background listening sessions with time limits.

#### Scenario: Background listening with Bluetooth microphone

- **GIVEN** the user enables continuous listening mode with a Bluetooth headset connected
- **WHEN** the app is backgrounded or the screen is locked
- **THEN** the system SHALL continue recording from the Bluetooth microphone
- **AND** the wake lock SHALL maintain the Bluetooth connection
- **AND** the background duration timer SHALL function normally
- **AND** when the duration expires, the system SHALL release the Bluetooth microphone

#### Scenario: Bluetooth disconnects during background listening

- **GIVEN** the app is in background listening mode using a Bluetooth microphone
- **WHEN** the Bluetooth headset disconnects
- **THEN** the system SHALL seamlessly switch to the phone microphone
- **AND** background listening SHALL continue
- **AND** the duration timer SHALL not be affected
- **AND** health monitoring SHALL detect this as normal device change, not a failure

### Requirement: Cross-Platform Bluetooth Consistency

The system SHALL provide consistent Bluetooth audio routing behavior across supported platforms (Android, iOS, Linux).

#### Scenario: Android Bluetooth behavior

- **GIVEN** the app is running on an Android device
- **WHEN** a Bluetooth headset is connected
- **THEN** audio routing SHALL use Android AudioManager with communication mode for recording
- **AND** audio routing SHALL use Android audio session with media usage for playback
- **AND** Bluetooth SCO SHALL be activated for recording automatically

#### Scenario: iOS Bluetooth behavior

- **GIVEN** the app is running on an iOS device
- **WHEN** a Bluetooth headset is connected
- **THEN** audio routing SHALL use iOS AVAudioSession with playAndRecord category for recording
- **AND** audio routing SHALL use iOS AVAudioSession with playback category for playback
- **AND** allowBluetooth category option SHALL enable Bluetooth routing
- **AND** the system SHALL respect user's "Call Audio Routing" preference in iOS Settings

#### Scenario: Linux Bluetooth behavior (future support)

- **GIVEN** the app is running on a Linux desktop
- **WHEN** a Bluetooth headset is connected
- **THEN** audio routing SHALL use PulseAudio or PipeWire default behavior
- **AND** Bluetooth routing SHALL work if the underlying audio system supports it
- **AND** no Linux-specific code changes SHALL be required for basic routing

### Requirement: Bluetooth Audio Debugging and Diagnostics

The system SHALL provide adequate logging and diagnostic information for troubleshooting Bluetooth audio issues.

#### Scenario: Bluetooth audio session configuration logging

- **GIVEN** the system configures the audio session for Bluetooth usage
- **WHEN** the configuration is applied
- **THEN** the system SHALL log the audio session category (iOS)
- **AND** the system SHALL log the audio session mode (iOS)
- **AND** the system SHALL log the audio usage and content type (Android)
- **AND** the system SHALL log whether Bluetooth is explicitly enabled

#### Scenario: Device change event logging

- **GIVEN** a Bluetooth device connects or disconnects
- **WHEN** the device change event is received
- **THEN** the system SHALL log the event with a timestamp
- **AND** the system SHALL log all available input devices
- **AND** the system SHALL log all available output devices
- **AND** the system SHALL log the current audio coordinator mode

#### Scenario: Bluetooth connection delay logging

- **GIVEN** the app starts recording with a Bluetooth microphone
- **WHEN** audio data begins flowing
- **THEN** the system SHALL log the time from recording start to first audio data
- **AND** if the delay exceeds 500ms, a warning SHALL be logged
- **AND** diagnostic information SHALL help identify device-specific issues

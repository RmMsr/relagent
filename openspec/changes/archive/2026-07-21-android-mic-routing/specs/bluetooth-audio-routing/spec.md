# bluetooth-audio-routing Delta Specification

## MODIFIED Requirements

### Requirement: Automatic Bluetooth Microphone Routing for ASR

The system SHALL automatically route speech recognition audio input to a connected Bluetooth headset microphone when available, on a best-effort basis: the route is requested through the platform APIs and confirmed by the platform's own readiness signal, and the system records on whatever route the platform then reports. On Android this capability requires Android 12 (API 31) or higher; older Android versions use the built-in microphone. Device- or vendor-specific divergence below the platform API layer is out of scope (see "Best-Effort Routing with Diagnostic-Only Verification").

#### Scenario: Bluetooth headset connected at recording start

- **GIVEN** a Bluetooth headset is connected and paired on Android 12+
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
- **AND** no routing state SHALL be modified and no readiness wait SHALL occur
- **AND** no errors or warnings SHALL be displayed

#### Scenario: Pre-Android-12 device

- **GIVEN** the app is running on Android below API 31 with a Bluetooth headset connected
- **WHEN** the user starts recording
- **THEN** the system SHALL use the phone's built-in microphone
- **AND** no routing calls SHALL be made and no errors SHALL occur

#### Scenario: Bluetooth microphone quality monitoring

- **GIVEN** the app is recording from a Bluetooth microphone
- **WHEN** audio data is received from the Bluetooth input
- **THEN** the health monitoring system SHALL track audio data flow normally
- **AND** the system SHALL apply the same health checks as phone microphone
- **AND** ASR processing SHALL work identically to phone microphone input

### Requirement: Mode-Specific Audio Session Configuration

The system SHALL configure the audio session differently for recording mode versus playback mode to optimize Bluetooth routing. On Android, all routing state (audio mode, communication device) SHALL be written exclusively by the native MicRouter component.

#### Scenario: Audio session configured for recording mode

- **GIVEN** the audio coordinator transitions to recording mode
- **WHEN** `requestRecording()` is called on the audio coordinator
- **THEN** the system SHALL call `configureAudioSessionForRecording()` on the voice service
- **AND** the system SHALL use playAndRecord category with voiceChat mode (iOS)
- **AND** the system SHALL enable allowBluetooth and defaultToSpeaker category options (iOS)
- **AND** the system SHALL use voiceCommunication audio usage (Android)
- **AND** the system SHALL use speech content type (Android)
- **AND** the audio session SHALL be activated
- **AND** on Android 12+ the MicRouter SHALL select the target input device and, when it is not the current route, set it via `setCommunicationDevice()`
- **AND** the system SHALL NOT return from recording configuration until the target route is actually active or a bounded timeout has elapsed, so the recorder opens on the intended microphone

#### Scenario: Route readiness is awaited via the communication-device-changed callback

- **GIVEN** a Bluetooth headset is connected and MicRouter has called `setCommunicationDevice()`
- **WHEN** the system prepares to open the audio recorder
- **THEN** the system SHALL await the `onCommunicationDeviceChanged` callback reporting the target device, bounded by a timeout of approximately 3 seconds
- **AND** the system SHALL NOT rely on the sticky Bluetooth SCO broadcast, whose replayed state can be stale, nor on polling loops
- **AND** if the current communication device already matches the target, readiness SHALL complete immediately without any wait
- **AND** if the route does not become active within the timeout, the system SHALL proceed with recording on the current route and report a timeout status rather than block

#### Scenario: Audio session configured for playback mode

- **GIVEN** the audio coordinator transitions to playback mode
- **WHEN** `requestPlayback()` is called on the audio coordinator
- **THEN** the system SHALL call `configureAudioSessionForPlayback()` on the voice service
- **AND** the system SHALL use playback category with spokenAudio mode (iOS)
- **AND** the system SHALL enable allowBluetooth and allowBluetoothA2dp category options (iOS)
- **AND** the system SHALL use assistant audio usage (Android)
- **AND** the system SHALL use speech content type (Android)
- **AND** the audio session SHALL be activated
- **AND** on Android 12+ the MicRouter SHALL release the communication device immediately (`clearCommunicationDevice()` and restore normal audio mode) so playback can use A2DP

#### Scenario: Recording stops

- **GIVEN** audio recording is active with Bluetooth SCO enabled
- **WHEN** recording stops (voice mode change, timeout, or error)
- **THEN** the system SHALL schedule release of the communication device after the idle period (5 seconds) rather than tearing it down immediately
- **AND** if no new recording starts within the idle period, the communication device SHALL be cleared and the audio mode restored to normal
- **AND** audio routing SHALL then revert to the default device

#### Scenario: Audio session configuration failure

- **GIVEN** the system attempts to configure the audio session
- **WHEN** the configuration fails with an error
- **THEN** the system SHALL log the error for debugging
- **AND** the system SHALL continue with the previous audio session configuration
- **AND** audio recording or playback SHALL continue to work (possibly without Bluetooth)

### Requirement: Android Bluetooth Permissions

The system SHALL request appropriate Bluetooth permissions based on the Android API level to enable device detection and connection.

#### Scenario: Android 12+ Bluetooth permission

- **GIVEN** the app is installed on an Android 12 (API 31) or higher device
- **WHEN** the app manifest is processed
- **THEN** the BLUETOOTH_CONNECT permission SHALL be declared
- **AND** the system SHALL request this permission at runtime if needed
- **AND** if permission is denied, the app SHALL continue to function with phone audio only

#### Scenario: Android pre-12 behavior

- **GIVEN** the app is installed on an Android device below API 31
- **WHEN** the app starts
- **THEN** no Bluetooth routing permissions SHALL be required
- **AND** Bluetooth microphone routing SHALL NOT be available; the built-in microphone SHALL be used
- **AND** Bluetooth audio output (A2DP playback) SHALL continue to work via OS default routing

#### Scenario: Bluetooth permission denial

- **GIVEN** the user denies the BLUETOOTH_CONNECT permission on Android 12+
- **WHEN** the app attempts to use audio features
- **THEN** the system SHALL fall back to phone audio devices
- **AND** no errors or crashes SHALL occur
- **AND** the app SHALL continue to function normally with phone microphone and speaker

## ADDED Requirements

### Requirement: Single Owner of Android Audio Routing State

On Android, exactly one component (the native MicRouter) SHALL write audio routing state — audio mode and communication device. No other component SHALL set or reset these.

#### Scenario: Background service does not reset audio mode

- **GIVEN** the MicRouter holds an active communication-device route
- **WHEN** the AudioBackgroundService handles a mode change or lifecycle event
- **THEN** the AudioBackgroundService SHALL NOT modify the audio mode or communication device
- **AND** the route held by MicRouter SHALL remain in effect

#### Scenario: Dart layer does not manipulate routing

- **GIVEN** a recording is being configured from Dart
- **WHEN** the voice service prepares Android routing
- **THEN** it SHALL do so only via the MicRouter channel interface
- **AND** no Dart code SHALL call Android AudioManager routing APIs (SCO start/stop, communication device) directly

### Requirement: Best-Effort Routing with Diagnostic-Only Verification

Microphone routing is best effort: the system SHALL request the target route through the platform APIs and record on whatever route the platform then reports. While a recording session is active on Android, the system SHALL observe the actual device the recording is routed to (via the AudioManager recording-configuration callback) and log it, for diagnostics only. The system SHALL NOT attempt to detect or correct divergence below the platform API layer, and SHALL NOT automatically restart the stream.

#### Scenario: Actual route logged at recording start

- **GIVEN** a recording has started with a target input device
- **WHEN** the recording configuration callback reports the active recording
- **THEN** the system SHALL log the device the recording is actually routed to

#### Scenario: Route mismatch observed

- **GIVEN** a recording has started targeting the Bluetooth microphone
- **WHEN** the recording configuration callback reports a different routed device
- **THEN** the system SHALL log a warning identifying target and actual device
- **AND** the recording SHALL continue uninterrupted
- **AND** the system SHALL NOT restart, reconfigure, or otherwise alter the recording

#### Scenario: Platform reports a route the hardware does not honor

- **GIVEN** the platform reports the Bluetooth route as active
- **WHEN** the audio hardware in fact captures from a different microphone, with no divergence visible through any platform API
- **THEN** the system SHALL accept the platform's report and continue recording
- **AND** no compensating behavior SHALL be attempted, since no app-level signal can distinguish this case from a correctly routed recording

### Requirement: Session-Scoped Bluetooth SCO Lifetime

The Bluetooth communication route SHALL be held across consecutive recordings and released after 5 seconds of idle time, so that back-to-back utterances avoid SCO reconnect latency while other applications' A2DP playback resumes promptly.

#### Scenario: Consecutive recordings reuse the active route

- **GIVEN** a recording stopped less than 5 seconds ago with the Bluetooth route active
- **WHEN** a new recording starts
- **THEN** the pending idle release SHALL be cancelled
- **AND** route readiness SHALL complete immediately with no SCO reconnect

#### Scenario: Idle release restores other apps' audio

- **GIVEN** a recording stopped with the Bluetooth route active
- **WHEN** 5 seconds pass without a new recording
- **THEN** the communication device SHALL be cleared and the audio mode restored to normal
- **AND** other applications SHALL be able to resume A2DP playback

#### Scenario: Playback transition releases immediately

- **GIVEN** the Bluetooth route is active after a recording
- **WHEN** the app transitions to TTS or media playback
- **THEN** the route SHALL be released immediately without waiting for the idle period

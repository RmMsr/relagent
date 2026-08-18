## MODIFIED Requirements

### Requirement: Automatic Bluetooth Microphone Routing for ASR

The system SHALL automatically route speech recognition audio input to a connected Bluetooth headset microphone when available, on a best-effort basis: the target device is set on the recorder directly and the system records on whatever route the platform then reports. On Android this capability requires API 23 or higher; older Android versions use the built-in microphone. Device- or vendor-specific divergence below the platform API layer is out of scope (see "Best-Effort Routing with Diagnostic-Only Verification").

#### Scenario: Bluetooth headset connected at recording start

- **GIVEN** a Bluetooth headset is connected and paired on Android API 23+
- **WHEN** the user starts continuous listening or push-to-talk recording
- **THEN** the system SHALL use the Bluetooth microphone as the audio input source
- **AND** the recorder SHALL be configured with the Bluetooth device as its preferred input device
- **AND** the audio source SHALL be configured for voice-communication-quality capture (acoustic echo cancellation / noise suppression)

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
- **AND** no preferred device SHALL be set on the recorder
- **AND** no errors or warnings SHALL be displayed

#### Scenario: Pre-Android-12 device

- **GIVEN** the app is running on Android below API 23 with a Bluetooth headset connected
- **WHEN** the user starts recording
- **THEN** the system SHALL use the phone's built-in microphone
- **AND** no preferred-device calls SHALL be made and no errors SHALL occur

#### Scenario: Bluetooth microphone quality monitoring

- **GIVEN** the app is recording from a Bluetooth microphone
- **WHEN** audio data is received from the Bluetooth input
- **THEN** the health monitoring system SHALL track audio data flow normally
- **AND** the system SHALL apply the same health checks as phone microphone
- **AND** ASR processing SHALL work identically to phone microphone input

### Requirement: Mode-Specific Audio Session Configuration

The system SHALL configure the audio session differently for recording mode versus playback mode to optimize Bluetooth routing. On Android, microphone device selection for recording SHALL be set directly on the recorder instance (preferred input device); no shared, process-wide routing state (audio mode, communication device) is written for this purpose.

#### Scenario: Audio session configured for recording mode

- **GIVEN** the audio coordinator transitions to recording mode
- **WHEN** `requestRecording()` is called on the audio coordinator
- **THEN** the system SHALL call `configureAudioSessionForRecording()` on the voice service
- **AND** the system SHALL use playAndRecord category with voiceChat mode (iOS)
- **AND** the system SHALL enable allowBluetooth and defaultToSpeaker category options (iOS)
- **AND** the system SHALL use voice-communication-quality audio source (Android)
- **AND** the recorder SHALL be configured with the resolved input device (built-in or Bluetooth) as its preferred device before recording starts

#### Scenario: Route readiness is awaited via the communication-device-changed callback

- **GIVEN** a Bluetooth headset is connected and the recorder's preferred device has been set to it
- **WHEN** the system prepares to open the audio recorder
- **THEN** the system SHALL NOT await any separate device-readiness callback before opening the recorder — `setPreferredDevice()` takes effect synchronously from the app's perspective, unlike the previous communication-device-changed callback wait
- **AND** the system SHALL rely on the post-start recording-configuration callback (see "Best-Effort Routing with Diagnostic-Only Verification") purely for diagnostic confirmation of the actual route, not for gating recorder startup

#### Scenario: Audio session configured for playback mode

- **GIVEN** the audio coordinator transitions to playback mode
- **WHEN** `requestPlayback()` is called on the audio coordinator
- **THEN** the system SHALL call `configureAudioSessionForPlayback()` on the voice service
- **AND** the system SHALL use playback category with spokenAudio mode (iOS)
- **AND** the system SHALL enable allowBluetooth and allowBluetoothA2dp category options (iOS)
- **AND** the system SHALL use assistant audio usage (Android)
- **AND** the system SHALL use speech content type (Android)
- **AND** the audio session SHALL be activated
- **AND** playback routing SHALL be independent of any recording-side device preference

#### Scenario: Recording stops

- **GIVEN** audio recording is active on a Bluetooth microphone
- **WHEN** recording stops (voice mode change, timeout, or error)
- **THEN** the recorder instance SHALL be released
- **AND** no held routing state SHALL persist beyond the recorder's own lifetime

#### Scenario: Audio session configuration failure

- **GIVEN** the system attempts to configure the audio session
- **WHEN** the configuration fails with an error
- **THEN** the system SHALL log the error for debugging
- **AND** the system SHALL continue with the previous audio session configuration
- **AND** audio recording or playback SHALL continue to work (possibly without Bluetooth)

### Requirement: Bluetooth Audio Profile Management

The system SHALL use appropriate Bluetooth audio profiles for recording versus playback to optimize quality and compatibility.

#### Scenario: Bluetooth SCO for recording

- **GIVEN** the app is in recording mode with a Bluetooth headset connected
- **WHEN** audio recording starts
- **THEN** the system SHALL target the Bluetooth SCO (Synchronous Connection-Oriented) input device as the recorder's preferred device
- **AND** echo cancellation SHALL be enabled automatically via the voice-communication audio source
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

### Requirement: Best-Effort Routing with Diagnostic-Only Verification

Microphone routing is best effort: the system SHALL set the target device as the recorder's preferred device and record on whatever route the platform then reports. While a recording session is active on Android, the system SHALL observe the actual device the recording is routed to (via the AudioManager recording-configuration callback) and log it, for diagnostics only. The system SHALL NOT attempt to detect or correct divergence below the platform API layer, and SHALL NOT automatically restart the stream.

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

- **GIVEN** the recorder's preferred device has been set to the Bluetooth microphone
- **WHEN** the platform declines or silently ignores the preference, with no divergence visible through any platform API
- **THEN** the system SHALL accept whatever the platform reports and continue recording
- **AND** no compensating behavior SHALL be attempted, since no app-level signal can distinguish this case from a correctly routed recording

### Requirement: Cross-Platform Bluetooth Consistency

The system SHALL provide consistent Bluetooth audio routing behavior across supported platforms (Android, iOS, Linux).

#### Scenario: Android Bluetooth behavior

- **GIVEN** the app is running on an Android device
- **WHEN** a Bluetooth headset is connected
- **THEN** audio input routing SHALL set the Bluetooth device as the recorder's preferred input device
- **AND** audio output routing SHALL use Android audio session with media usage for playback
- **AND** no process-wide communication-device or audio-mode state SHALL be set for recording

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

## REMOVED Requirements

### Requirement: Single Owner of Android Audio Routing State

**Reason**: This requirement existed because `setCommunicationDevice()`/audio mode are shared, process-wide state that any component could clobber if more than one component wrote to them. `AudioRecord.setPreferredDevice()` is scoped to a single recorder instance, not shared process state, so there is no longer a single mutable resource requiring one designated owner.

**Migration**: No migration needed — no other component ever wrote this state, and none needs to going forward. Device selection is now a parameter passed when constructing each recorder.

### Requirement: Session-Scoped Bluetooth SCO Lifetime

**Reason**: The idle-hold/release cycle existed to amortize the latency of establishing a `setCommunicationDevice()` SCO connection across back-to-back recordings. `AudioRecord.setPreferredDevice()` has no equivalent explicit connection-establishment step for the app to hold open or release; the SCO link's lifecycle is managed by the platform in response to the preferred-device setting on each recorder instance.

**Migration**: No app-level migration needed. If back-to-back-recording latency proves worse under the new mechanism, that is a performance question for design.md / follow-up measurement, not a routing-ownership concern.

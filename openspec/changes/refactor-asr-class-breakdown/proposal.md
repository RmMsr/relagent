# Change: Refactor ASR Class Breakdown

## Why

The ASR class in `apps/lib/speech_recognition/services.dart` has grown to 235 lines and handles audio recording, stream processing, device management, and Bluetooth configuration. This violates the project's guideline of "smaller, focused classes with distinct purpose" and makes testing individual components difficult.

Include a review of the Architecture specialist as quality control.

## What Changes

- **BREAKING**: Split ASR class into focused components:
  - `AudioDeviceManager` for device enumeration and Bluetooth configuration
  - `AudioStreamProcessor` for stream handling and processing
  - `RecordingCoordinator` for recording lifecycle management
- Refactor ASR to coordinate these components
- Improve testability of individual audio concerns

## Impact

- Affected specs: bluetooth-audio-routing
- Affected code: `apps/lib/speech_recognition/services.dart`
- Breaking changes to public ASR API are ok if it improves architecture

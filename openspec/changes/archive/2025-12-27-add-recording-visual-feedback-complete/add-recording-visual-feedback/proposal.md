# Change: Add Visual Feedback to Recording Button

## Why

The recording button currently provides minimal visual feedback about its state and audio signal strength. Users cannot easily distinguish between different recording states (idle, initializing, active, paused) or see if audio is being captured properly. This creates uncertainty during hands-free usage and makes troubleshooting audio issues difficult.

Adding visual feedback will:
- Improve user confidence that the app is listening and processing audio correctly
- Support hands-free usage by providing clear visual state indicators
- Enable users to detect audio quality issues (noise, low volume) in real-time
- Align with the project's goal of an intuitive interface requiring minimal attention

## What Changes

- **Recording State Visualization**: Display distinct visual states for:
  - (a) Mic off (idle - click to start recording)
  - (b) Mic initializing (ASR starting up, brief transition)
  - (c) Mic active (recording and processing audio)
  - (d) Continuous listening (always-on recording mode)
  - (e) Paused (temporarily suspended due to interruption)
  - (f) Error (recording failure)

- **Audio Signal Visualization**: Show real-time audio amplitude using 5 vertical bars:
  - Bars update based on microphone input level (dBFS from `record` package)
  - Animation flows right-to-left, centered horizontally in the button
  - Visible during active recording (both manual and continuous modes)

- **Audio Quality Indicator**: Display quality feedback:
  - Detect low signal (too quiet)
  - Detect noise/clipping (too loud or distorted)
  - Visual warning when quality issues detected

- **Documentation Update**: Ensure audio mode documentation stays synchronized with visual states

## Impact

- Affected specs: `recording-button` (new capability)
- Affected code:
  - `apps/lib/speech_recognition/widgets.dart` (RecorderButton widget)
  - `apps/lib/speech_recognition/services.dart` (ASR integration for amplitude)
  - `apps/lib/providers/recording_provider.dart` (state management for quality metrics)
  - Documentation files describing audio modes

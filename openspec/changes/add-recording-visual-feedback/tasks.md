## 1. Implementation

- [ ] 1.1 Add amplitude monitoring to ASR service
  - [ ] 1.1.1 Integrate `onAmplitudeChanged()` stream from record package
  - [ ] 1.1.2 Add callback to RecordingProvider for amplitude updates
  - [ ] 1.1.3 Store current amplitude in RecordingState

- [ ] 1.2 Create audio quality detector
  - [ ] 1.2.1 Implement low signal detection (amplitude threshold)
  - [ ] 1.2.2 Implement noise/clipping detection (high amplitude or fluctuation)
  - [ ] 1.2.3 Add quality state to RecordingState (good, low_signal, noisy)

- [ ] 1.3 Build recording state visualization components
  - [ ] 1.3.1 Create RecordingStateIndicator widget for different states
  - [ ] 1.3.2 Implement idle state icon (mic icon)
  - [ ] 1.3.3 Implement initializing state icon (loading animation)
  - [ ] 1.3.4 Implement paused state icon (pause icon with visual distinction)
  - [ ] 1.3.5 Implement error state icon (error icon with color)

- [ ] 1.4 Build audio signal visualization (5-bar amplitude display)
  - [ ] 1.4.1 Create VolumeBarVisualizer widget
  - [ ] 1.4.2 Implement 5 vertical bars with height based on amplitude
  - [ ] 1.4.3 Add right-to-left animation for audio data flow
  - [ ] 1.4.4 Center visualization horizontally in button
  - [ ] 1.4.5 Add amplitude history buffer (last 5 samples for bars)

- [ ] 1.5 Integrate quality indicator into button
  - [ ] 1.5.1 Add visual warning overlay for quality issues
  - [ ] 1.5.2 Use color coding (e.g., amber for low signal, red for noise)
  - [ ] 1.5.3 Ensure quality indicator doesn't obscure volume bars

- [ ] 1.6 Update RecorderButton widget
  - [ ] 1.6.1 Replace static icon with state-aware visualization
  - [ ] 1.6.2 Integrate VolumeBarVisualizer for active states
  - [ ] 1.6.3 Add smooth transitions between states
  - [ ] 1.6.4 Maintain existing button behavior (click handling)

- [ ] 1.7 Testing
  - [ ] 1.7.1 Test all recording states display correctly
  - [ ] 1.7.2 Test volume bars update smoothly during recording
  - [ ] 1.7.3 Test quality indicators trigger appropriately
  - [ ] 1.7.4 Test continuous vs manual recording visualization
  - [ ] 1.7.5 Test paused state during phone call interruption
  - [ ] 1.7.6 Verify no performance degradation from animations

- [ ] 1.8 Documentation
  - [ ] 1.8.1 Update audio mode documentation with visual state descriptions
  - [ ] 1.8.2 Document quality indicator thresholds and meanings
  - [ ] 1.8.3 Add visual state diagram if helpful

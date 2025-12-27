# Design: Recording Visual Feedback

## Context

The recording button currently provides minimal visual feedback, making it difficult for users to understand the recording state or detect audio issues. This design adds comprehensive visual feedback including state indicators, real-time amplitude visualization, and quality warnings.

### Background

- Current button shows static icons that change based on voice mode
- No real-time feedback about audio signal strength
- Users cannot tell if microphone is capturing audio properly
- Hands-free usage requires clear visual confirmation

### Constraints

- Button size is limited (IconButton in chat input row)
- Must not degrade performance (60 fps minimum)
- Must work on all platforms (Android, iOS, Linux)
- Must maintain existing button click behavior

### Stakeholders

- End users: Need clear visual feedback for hands-free operation
- Developers: Need maintainable, testable code structure

## Goals / Non-Goals

### Goals

- Provide clear visual distinction between all recording states
- Display real-time audio amplitude with smooth animations
- Detect and warn about audio quality issues (low signal, noise)
- Maintain 60 fps performance during animations
- Keep design simple and centered in the button area

### Non-Goals

- Not implementing waveform or spectrogram visualization (too complex for button size)
- Not adding ASR confidence scores (sherpa-onnx streaming doesn't provide them)
- Not creating a separate dedicated visualization screen
- Not implementing advanced audio processing (EQ, filters)

## Decisions

### Decision 1: Use record package's onAmplitudeChanged stream

**What:** Integrate the existing `record` package's amplitude monitoring via `onAmplitudeChanged(Duration)` stream.

**Why:**
- Already a dependency, no new package needed
- Provides dBFS values across all platforms
- Updates at configurable intervals (we'll use 100ms)
- Proven solution used by the package's example

**Alternatives considered:**
- Raw audio data processing: Too CPU-intensive, requires DSP knowledge
- Third-party visualization packages: Adds dependencies, may not fit button size constraints
- Sherpa-ONNX audio features: Not exposed in streaming API

**Implementation:**
```dart
_audioRecorder
  .onAmplitudeChanged(const Duration(milliseconds: 100))
  .listen((amplitude) {
    // amplitude.current: double (dBFS, typically -160 to 0)
    // amplitude.max: double (peak since recording started)
  });
```

### Decision 2: 5-bar amplitude visualization with ring buffer

**What:** Display 5 vertical bars representing the last 5 amplitude samples, updated as new data arrives.

**Why:**
- Limited button space requires compact visualization
- 5 bars provide enough detail without clutter
- Ring buffer approach is efficient (no array shifting)
- Right-to-left flow creates intuitive "data flowing" effect

**Alternatives considered:**
- Single bar showing current amplitude: Too simplistic, no history
- Waveform drawing: Too complex for button size, harder to implement
- More bars (e.g., 10): Would be cramped in button space

**Data structure:**
```dart
class AmplitudeHistory {
  final List<double> _buffer = List.filled(5, -80.0); // Initialize with silence
  int _index = 0;

  void add(double amplitude) {
    _buffer[_index] = amplitude;
    _index = (_index + 1) % 5;
  }

  List<double> get bars => [
    _buffer[(_index + 0) % 5],  // Oldest
    _buffer[(_index + 1) % 5],
    _buffer[(_index + 2) % 5],
    _buffer[(_index + 3) % 5],
    _buffer[(_index + 4) % 5],  // Newest
  ];
}
```

### Decision 3: Quality thresholds based on dBFS ranges

**What:** Define amplitude ranges for quality detection:
- **Low signal**: < -40 dBFS (too quiet)
- **Good range**: -40 to -10 dBFS (optimal)
- **Clipping/noise**: > -10 dBFS (too loud, likely clipping)

**Why:**
- dBFS scale is industry standard for digital audio
- -40 dBFS threshold catches very quiet speech
- -10 dBFS threshold catches near-clipping situations
- Simple range checks, no complex DSP required

**Alternatives considered:**
- Dynamic threshold adjustment: Too complex, unreliable
- Frequency analysis for noise detection: CPU-intensive, overkill
- User-configurable thresholds: Adds complexity, most users won't adjust

**Quality detection logic:**
```dart
enum AudioQuality { good, lowSignal, noisy }

AudioQuality detectQuality(double currentAmplitude) {
  if (currentAmplitude < -40) return AudioQuality.lowSignal;
  if (currentAmplitude > -10) return AudioQuality.noisy;
  return AudioQuality.good;
}
```

### Decision 4: Widget composition structure

**What:** Create separate composable widgets:
- `VolumeBarVisualizer`: Displays 5 bars with animation
- `RecordingStateIcon`: Shows icon for current state (idle, error, pause, etc.)
- `RecorderButton`: Orchestrates which visualization to show

**Why:**
- Separation of concerns (visualization vs state logic)
- Easier to test individual components
- Reusable if needed in other parts of UI
- Follows Flutter best practices for widget composition

**Alternatives considered:**
- Monolithic RecorderButton with all visualization inline: Harder to test, less maintainable
- Separate AnimatedVolumeBar widgets for each bar: Over-engineering, unnecessary complexity

**Widget hierarchy:**
```
RecorderButton (ConsumerStatefulWidget)
├─ IconButton
    ├─ (when recording) VolumeBarVisualizer
    │   └─ Row of 5 Container bars with AnimatedContainer
    ├─ (when idle/paused/error) RecordingStateIcon
    │   └─ Icon with appropriate color/animation
    └─ (quality warning overlay) QualityIndicatorOverlay
        └─ Positioned icon or border
```

### Decision 5: State determination logic

**What:** Map RecordingState to visual state enum for clarity.

**Why:**
- RecordingState has multiple fields (isRecording, isContinuous, recordState, error)
- Deriving visual state in widget build is error-prone
- Centralized logic ensures consistency

**Visual state enum:**
```dart
enum RecordingVisualState {
  idle,           // Not recording, ready to start
  initializing,   // Starting up (brief)
  recording,      // Active recording (manual or continuous)
  paused,         // Interrupted (phone call)
  error,          // Error occurred
}

RecordingVisualState determineVisualState(RecordingState state) {
  if (state.error != null) return RecordingVisualState.error;
  if (state.recordState == RecordState.pause) return RecordingVisualState.paused;
  if (state.isRecording && state.recordState == RecordState.record) {
    return RecordingVisualState.recording;
  }
  if (state.isRecording && state.recordState != RecordState.record) {
    return RecordingVisualState.initializing;
  }
  return RecordingVisualState.idle;
}
```

## Risks / Trade-offs

### Risk: Animation performance impact

**Risk:** Updating 5 animated bars every 100ms could cause frame drops on low-end devices.

**Mitigation:**
- Use `AnimatedContainer` with short duration (100-200ms) instead of custom animations
- Profile on low-end Android device before finalizing
- Add performance test to ensure 60 fps maintained
- Consider increasing update interval to 150-200ms if needed

### Risk: Quality detection false positives

**Risk:** Fixed dBFS thresholds may not work well in all environments (noisy backgrounds, quiet speakers).

**Mitigation:**
- Use generous thresholds that only flag extreme cases
- Ensure quality warnings are non-intrusive (color change, not blocking dialog)
- Monitor user feedback and adjust thresholds in future iteration
- Consider adding "dismiss warning" option if too many false positives

### Trade-off: Button space vs. information density

**Trade-off:** Limited button size constrains how much visual information can be displayed.

**Decision:**
- Prioritize amplitude bars over detailed state text/labels
- Use color coding for quality (amber, red) instead of text
- Rely on tooltips for state explanations
- Accept that very detailed information requires separate screen (future enhancement)

### Risk: State transition confusion

**Risk:** Rapid state changes could cause visual flicker or confusion.

**Mitigation:**
- Add brief (200ms) transition animations between states
- Ensure minimum state duration (don't flash initializing if startup < 100ms)
- Test with common state transition flows (idle -> recording -> idle)

## Migration Plan

### Implementation Steps

1. **Phase 1: Amplitude integration** (no UI changes)
   - Add amplitude stream to ASR service
   - Wire amplitude to RecordingProvider
   - Add amplitude to RecordingState
   - Test amplitude values are correct

2. **Phase 2: Volume bars widget** (isolated component)
   - Create VolumeBarVisualizer widget
   - Test with mock data
   - Verify animation smoothness
   - Profile performance

3. **Phase 3: State icons** (isolated components)
   - Create RecordingStateIcon widget
   - Implement all state variations
   - Test state determination logic

4. **Phase 4: Integration** (update RecorderButton)
   - Replace static icon with state-aware visualization
   - Wire volume bars to recording state
   - Add quality indicator overlay
   - Test all state transitions

5. **Phase 5: Quality detection** (add logic layer)
   - Implement quality detection in provider
   - Add quality state to RecordingState
   - Test threshold detection

6. **Phase 6: Documentation**
   - Update audio mode docs
   - Add troubleshooting guide
   - Include visual state diagram

### Rollback Plan

- If performance issues arise: Disable animations, fall back to static icons
- If quality detection too noisy: Remove quality indicator, keep volume bars
- If users confused by visualization: Add settings toggle to disable/simplify

### Testing Strategy

**Unit tests:**
- AmplitudeHistory ring buffer logic
- Quality detection threshold checks
- Visual state determination logic

**Widget tests:**
- VolumeBarVisualizer renders correctly for different amplitudes
- RecordingStateIcon shows correct icon for each state
- RecorderButton switches between visualizations

**Integration tests:**
- Full recording flow with visual state changes
- Quality warnings trigger correctly
- Performance profiling (60 fps check)

**Manual testing:**
- Test on low-end Android device
- Test in noisy environment (quality detection)
- Test during phone call interruption (paused state)
- Test continuous vs manual recording visualization

## Open Questions

1. **Should we persist quality warning dismissals?**
   - If user dismisses a low-signal warning, should we remember and not show again?
   - Decision: Defer to user feedback, start with no persistence

2. **Should volume bars be visible in paused state?**
   - Show frozen bars from when paused, or hide them?
   - Decision: Show frozen bars to indicate it was recording before pause

3. **Should we add haptic feedback on state changes?**
   - Brief vibration when recording starts/stops
   - Decision: Defer to future iteration, focus on visual first

4. **Should error state be dismissible or auto-clear?**
   - How long should error visual remain after error is resolved?
   - Decision: Auto-clear when recording successfully resumes, otherwise persist

5. **Should we log amplitude values for debugging?**
   - Helpful for threshold tuning, but could be verbose
   - Decision: Add debug logging behind feature flag or compile-time constant

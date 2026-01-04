# Voice Mode State Diagram

## State Properties

```
┌─────────────┬───────────────┬─────────────────┬─────────────────────────┐
│ Voice Mode  │ Recording     │ Auto-Submit     │ Auto-Playback           │
├─────────────┼───────────────┼─────────────────┼─────────────────────────┤
│ silent      │ single        │ NO (manual)     │ NO                      │
│ listening   │ continuous    │ YES (on pause)  │ NO                      │
│ conversation│ continuous    │ YES (on pause)  │ YES                     │
│ reading     │ single        │ NO (manual)     │ YES                     │
└─────────────┴───────────────┴─────────────────┴─────────────────────────┘
```

**Key behaviors:**
- **Single recording**: Press button to start, press again to stop. Text stays in input field for editing/manual submit.
- **Continuous recording**: Always listening. When speech pause detected (endpoint), text auto-submits as message.
- **Auto-playback**: Assistant responses automatically play via TTS when received.

Default is "Silent". But the app remembers the last state.

## Toggle Control Mapping

```
Playback OFF + Mic OFF    = silent       (one-shot, no playback)
Playback OFF + Mic ON     = listening    (continuous, no playback)
Playback ON  + Mic ON     = conversation (continuous, playback)
Playback ON  + Mic OFF    = reading      (one-shot, playback)
```

## State Transition Diagram

```
                    ┌──────────────────────────────────────────┐
                    │                                          │
                    │          Toggle Playback ON              │
                    │    ┌─────────────────────────────┐       │
                    ▼    │                             ▼       │
          ┌─────────────────┐                  ┌─────────────────┐
          │     SILENT      │                  │    READING      │
          │                 │                  │                 │
          │  Recording: 1x  │                  │  Recording: 1x  │
          │  Playback: NO   │                  │  Playback: YES  │
          └─────────────────┘                  └─────────────────┘
                    │    ▲                             │      ▲
                    │    │                             │      │
                    │    └─────────────────────────────┘      │
                    │          Toggle Playback OFF            │
                    │                                         │
                    │          Toggle Mic ON                  │
                    │    ┌─────────────────────────────┐      │
                    ▼    │                             ▼      │
          ┌─────────────────┐                  ┌─────────────────┐
          │   LISTENING     │                  │  CONVERSATION   │
          │                 │                  │                 │
          │  Recording: ∞   │                  │  Recording: ∞   │
          │  Playback: NO   │                  │  Playback: YES  │
          └─────────────────┘                  └─────────────────┘
                    │    ▲                             │      ▲
                    │    │                             │      │
                    │    └─────────────────────────────┘      │
                    │          Toggle Playback ON             │
                    │                                         │
                    └─────────────────────────────────────────┘
                              Toggle Mic OFF

Legend:
  1x = One-shot recording (press to start, press to stop)
  ∞  = Continuous recording (always listening)
```

## Toggle Interaction Examples

### Example 1: Silent → Conversation

```
Start:  Silent (Playback: OFF, Mic: OFF)
Step 1: User taps "Mic ON"
        → listening (Playback: OFF, Mic: ON)
Step 2: User taps "Playback ON"
        → conversation (Playback: ON, Mic: ON)
```

### Example 2: Conversation → Silent

```
Start: Conversation (Playback: ON, Mic: ON)
Step 1: User taps "Playback OFF"
        → listening (Playback: OFF, Mic: ON)
Step 2: User taps "Mic OFF"
        → silent (Playback: OFF, Mic: OFF)
```

### Example 3: Listening → Reading

```
Start:  listening (Playback: OFF, Mic: ON)
Step 1: User taps "Playback ON"
        → conversation (Playback: ON, Mic: ON)
Step 2: User taps "Mic OFF"
        → reading (Playback: ON, Mic: OFF)
```

## RecorderButton Behavior by Mode

```
┌─────────────┬────────────────────────────────────────────────┐
│ Voice Mode  │ RecorderButton Behavior                        │
├─────────────┼────────────────────────────────────────────────┤
│ silent      │ Tap to start recording, tap again to stop      │
│             │ Icon: mic (idle) or stop_circle (recording)    │
│             │ Visual: State indicator + volume bars when rec │
│             │                                                 │
│ listening   │ Tap to toggle OFF listening mode               │
│             │ Switches to: silent or reading                 │
│             │ Icon: pulsing mic (always on)                  │
│             │ Visual: State indicator + volume bars + quality│
│             │                                                 │
│ conversation│ Tap to toggle OFF listening mode               │
│             │ Switches to: silent or reading                 │
│             │ Icon: pulsing mic (always on)                  │
│             │ Visual: State indicator + volume bars + quality│
│             │                                                 │
│ reading     │ Tap to start recording, tap again to stop      │
│             │ Icon: mic (idle) or stop_circle (recording)    │
│             │ Visual: State indicator + volume bars when rec │
└─────────────┴────────────────────────────────────────────────┘
```

### Visual Feedback States

**State Indicator Icons:**
- **Idle**: mic_none (ready to record)
- **Recording Active**: mic (blue, when recording)
- **Continuous Listening**: mic (blue, always on)
- **Paused**: pause_circle_outline (orange, during interruptions)
- **Error**: error_outline (red, recording failure)

**Amplitude Bar Visualization:**

**Layout & Appearance:**
- **5 Bars**: Fixed positions with 4px spacing between bars
- **Dimensions**: 3px width × 24px height each
- **Style**: Rounded corners (1.5px radius), color-coded by audio quality
- **Position**: Bars overlay microphone icon with 10% transparency

**Baseline Calculation:**
- **Monitored Span**: Rolling history of 30 amplitude samples
- **Trimmed Median**: Remove min/max from 30 samples (28 remaining)
- **Median Calculation**: `(samples[13] + samples[14]) / 2` of sorted trimmed array
- **Baseline Formula**: `trimmed_median` (represents current noise floor)

**Scaling & Range:**
- **Upper Limit**: -6 dBFS (90% of microphone capability)
- **Scale Formula**: `(amplitude - baseline) / (upper_limit - baseline)`
- **Output Range**: 0.0 to 1.0 (0% to 100% bar height)
- **Minimum Height**: 5% (bars always visible)

**Animation Behavior:**
- **Fast Attack**: 100ms animation duration for rising values
- **Slow Decay**: 300ms animation duration for falling values
- **Curve**: easeOut for natural motion
- **Update Trigger**: New amplitude value shifts bar data left, animates heights

**Color Coding:**
- **Good Quality**: Primary theme color (blue)
- **Low Signal**: Orange warning
- **Noisy**: Red error

**Data Flow:**
1. New dBFS amplitude arrives every 200ms
2. Scale against baseline (-6 dBFS upper limit)
3. Shift existing bar values left (oldest discarded)
4. Add new scaled value to rightmost bar
5. Animate all bars to new heights with attack/decay timing

**Algorithm Benefits:**
- **Adaptive**: Baseline adjusts to ambient noise automatically
- **Stable**: 30-sample rolling window prevents jitter
- **Responsive**: 200ms updates with smooth 100ms/300ms animations
- **Professional**: Attack/decay timing matches audio equipment standards
- **Efficient**: Hardware-accelerated animations, no performance impact

**Audio Quality Indicators:**
- **Good**: Blue bars (normal amplitude)
- **Low Signal**: Orange bars (amplitude < -40dBFS)
- **Noisy**: Red bars (amplitude > -6dBFS)

## Provider State Flow

```
┌─────────────────────────────────────────────────────────┐
│                   User Interaction                      │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              VoiceModeSelector                          │
│  - User taps toggle button                              │
│  - Calculates new VoiceMode from boolean states         │
│  - Calls: settingsProvider.notifier.updateVoiceMode()   │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              SettingsProvider                           │
│  - Updates state.voiceMode                              │
│  - Persists to SharedPreferences                        │
│  - Notifies listeners                                   │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│           RecordingProvider (listening)                 │
│  - Receives voiceMode change notification               │
│  - If continuous mode: starts ASR                       │
│  - If one-shot mode: stops ASR                          │
└─────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              TtsProvider (listening)                    │
│  - Receives voiceMode change notification               │
│  - If auto-playback mode: queues new messages           │
│  - If manual mode: waits for user tap                   │
└─────────────────────────────────────────────────────────┘
```

## Testing State Coverage

To ensure complete coverage, tests should verify:

1. **All 4 modes have correct properties**

   - silent: !autoPlay && !continuous
   - listening: !autoPlay && continuous
   - conversation: autoPlay && continuous
   - reading: autoPlay && !continuous

2. **All 16 transitions work**

   - From each mode to every other mode (4 × 4 = 16)
   - Includes self-transitions (no-ops)

3. **Toggle mapping is bidirectional**

   - Every (playback, mic) combination maps to unique mode
   - Every mode maps back to unique (playback, mic) state

4. **Provider reactions work**

   - RecordingProvider starts/stops ASR correctly
   - TtsProvider queues/doesn't queue correctly
   - Settings persist across app restarts

5. **UI updates correctly**
   - Toggles show correct position for each mode
   - RecorderButton shows correct icon/behavior
   - Tooltips are accurate

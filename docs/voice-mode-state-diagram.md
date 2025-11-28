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
│             │                                                 │
│ listening   │ Tap to toggle OFF listening mode               │
│             │ Switches to: silent or reading                 │
│             │ Icon: pulsing mic (always on)                  │
│             │                                                 │
│ conversation│ Tap to toggle OFF listening mode               │
│             │ Switches to: silent or reading                 │
│             │ Icon: pulsing mic (always on)                  │
│             │                                                 │
│ reading     │ Tap to start recording, tap again to stop      │
│             │ Icon: mic (idle) or stop_circle (recording)    │
└─────────────┴────────────────────────────────────────────────┘
```

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

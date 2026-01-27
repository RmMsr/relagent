# Design: Refactor Speech Recognition to Target-Based Architecture

## Context

The current speech recognition architecture uses a global ASR instance with callbacks that deliver recognized text to all listeners. This creates several problems:

1. **Ambiguous Text Routing**: When text is recognized, there's no clear destination - it goes to whoever is listening via callbacks
2. **Complex State Management**: The RecordingProvider manages global recording state, while ChatInput and RecordingButton try to coordinate through indirect callbacks
3. **No Support for Multiple Targets**: Cannot support multiple input fields that might need speech recognition (e.g., search fields, chat input, form fields)
4. **Tight Coupling**: RecordingButton directly listens to RecordingProvider state changes and forwards them via callbacks to ChatInput

## Goals / Non-Goals

**Goals:**
- Bind ASR instance to specific input targets (widgets that receive text)
- Simplify state coordination between recording and input widgets
- Enable future support for multiple recording targets
- Clear ownership of recording state per target
- Reduce callback chains and indirect communication

**Non-Goals:**
- Change ASR algorithm or Sherpa-ONNX integration
- Modify health monitoring or auto-recovery mechanisms
- Change background service integration
- Alter voice mode behavior (Silent/Listening/Conversation/Reading)

## Decisions

### Decision 1: Introduce RecordingTarget abstraction

**What:** Create a `RecordingTarget` interface/protocol that input widgets implement to receive speech recognition events.

**Why:**
- Makes the contract explicit - what events does a target receive?
- Decouples ASR from specific widget types
- Allows different widgets to be recording targets in the future

**Target Events:**
```dart
abstract class RecordingTarget {
  void onTextRecognized(String text);  // Partial/final recognized text
  void onTextFinished();                // Endpoint detected, submit text
  void onRecordingStarted();           // Recording started
  void onRecordingStopped();           // Recording stopped
  void onError(String error);          // Error occurred
}
```

### Decision 2: RecordingProvider manages active target

**What:** RecordingProvider tracks the currently active RecordingTarget and routes all ASR events to it.

**Why:**
- Central authority for "who is receiving speech input right now"
- Enforces "only one target at a time" rule
- Simplifies state management - provider knows the target, not callbacks

**API:**
```dart
class RecordingNotifier {
  RecordingTarget? _activeTarget;

  void startRecording(RecordingTarget target, {bool continuous = false});
  void stopRecording();
  // Existing methods...
}
```

### Decision 3: ChatInput implements RecordingTarget

**What:** ChatInput becomes a RecordingTarget that directly receives speech events.

**Why:**
- Eliminates callback chain: RecordingProvider → RecordingButton → ChatInput
- ChatInput directly manages its own state based on speech events
- Clear ownership: ChatInput owns its text field and speech input

**Implementation:**
```dart
class ChatInputState extends State<ChatInput> implements RecordingTarget {
  @override
  void onTextRecognized(String text) {
    setState(() { _controller.text = text; });
  }

  @override
  void onTextFinished() {
    _submitText();
  }
  // ...
}
```

### Decision 4: RecordingButton as simple state indicator

**What:** RecordingButton becomes a pure UI widget that:
- Displays recording state (mic icon, visualizer)
- Triggers start/stop actions via RecordingProvider
- Does NOT route events or manage text

**Why:**
- Single responsibility: visual indication and action trigger
- No longer a middleman between provider and input
- Can be reused with any RecordingTarget

**Simplified Implementation:**
```dart
class RecorderButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(recordingProvider);

    return IconButton(
      onPressed: () {
        // Start/stop recording without caring about target
        // Provider knows the target from ChatInput registration
        if (recordingState.isRecording) {
          ref.read(recordingProvider.notifier).stopRecording();
        } else {
          ref.read(recordingProvider.notifier).startDictation();
        }
      },
      // Visual state indicator...
    );
  }
}
```

### Decision 5: Rename "oneShot" to "dictation"

**What:** Rename all occurrences of "oneShot" to "dictation" throughout the codebase.

**Why:**
- Language policy compliance: "one-shot" is potentially offensive terminology
- "Dictation" is more descriptive and user-friendly in the context of text input
- Better conveys the intent: temporary recording for text input

**Affected Methods:**
- `startOneShot()` → `startDictation()`
- `stopOneShot()` → `stopDictation()`
- Comments referring to "one-shot recording" → "dictation mode"

**Dictation Mode Behavior:**
- User presses button to start dictating
- Speaks text that appears in input field
- User presses button again to stop, OR
- User submits the input (Enter key), which stops dictation automatically
- Submitting input stops dictation and sends the message in one action

### Decision 6: Target registration in ChatInput lifecycle

**What:** ChatInput registers itself as the active target when mounted, unregisters when unmounted.

**Why:**
- Automatic lifecycle management
- Prevents stale target references
- Works with Flutter widget lifecycle naturally

**Implementation:**
```dart
class ChatInputState extends State<ChatInput> {
  @override
  void initState() {
    super.initState();
    // Register as recording target when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recordingProvider.notifier).registerTarget(this);
    });
  }

  @override
  void dispose() {
    // Unregister when widget is destroyed
    ref.read(recordingProvider.notifier).unregisterTarget(this);
    super.dispose();
  }
}
```

## Alternatives Considered

### Alternative 1: Keep callback-based architecture
**Rejected because:**
- Doesn't solve multiple target problem
- Maintains tight coupling between components
- Complex callback chains are hard to debug and maintain

### Alternative 2: Stream-based communication
**Rejected because:**
- Adds complexity with stream subscriptions
- Harder to manage lifecycle (when to subscribe/unsubscribe)
- Doesn't provide clear ownership model

### Alternative 3: Global event bus
**Rejected because:**
- Makes target destination ambiguous
- Difficult to enforce "one target at a time" rule
- Harder to track event flow for debugging

## Risks / Trade-offs

### Risk: Widget lifecycle complexity
**Concern:** ChatInput must properly register/unregister on lifecycle events, or we could have stale references.

**Mitigation:**
- Use weak references or nullable target in RecordingProvider
- Clear target on disposal automatically
- Add debug assertions to detect lifecycle issues early

### Risk: Breaking change for existing code
**Concern:** RecordingButton API changes, ChatInput significantly refactored.

**Mitigation:**
- Single-step migration since this is internal app code
- Comprehensive testing after refactor
- No external API impact (internal architecture only)

### Trade-off: More direct coupling between ChatInput and RecordingProvider
**Concern:** ChatInput now directly implements RecordingTarget interface, creating compile-time dependency.

**Accepted because:**
- Makes relationship explicit and type-safe
- Better than implicit callback coupling
- Easy to mock for testing
- Clear contract for future RecordingTarget implementations

## Migration Plan

### Step 1: Create RecordingTarget interface
- Define interface with all event methods
- Add to RecordingProvider as nullable active target
- No breaking changes yet

### Step 2: Update RecordingProvider
- Add `registerTarget()` and `unregisterTarget()` methods
- Update ASR callback routing to call target methods instead of state updates
- Keep existing callback-based API temporarily for compatibility

### Step 3: Refactor ChatInput
- Implement RecordingTarget interface
- Add lifecycle registration/unregistration
- Remove callback props from RecorderButton usage
- Test thoroughly

### Step 4: Simplify RecordingButton
- Remove `onTextRecognized` and `onTextFinished` callback props
- Remove listener logic that forwards events
- Keep only visual state and action triggering
- Update all usages (only ChatInput currently)

### Step 5: Cleanup
- Remove old callback-based APIs from RecordingProvider if unused
- Update tests
- Verify health monitoring and background service still work

## Open Questions

1. **Should RecordingTarget be a concrete class or interface?**
   - **Answer:** Use abstract class so we can add optional methods with default implementations later if needed.

2. **How to handle voice mode changes (Silent/Listening) with targets?**
   - **Answer:** Voice mode changes trigger stopRecording() which clears the target. Starting new recording re-registers target. No special handling needed.

3. **What happens if RecordingButton is pressed when no target is registered?**
   - **Answer:** Provider should no-op or show error. In current app, ChatInput is always present when RecordingButton is visible, so this is unlikely. Add defensive check anyway.

4. **Should we support multiple concurrent targets in the future?**
   - **Answer:** Out of scope for this refactor. The "one target at a time" rule is sufficient and simpler. If needed later, can extend RecordingProvider to manage a target stack.

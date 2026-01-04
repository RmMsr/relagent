# TTS Future Improvements

This document captures potential improvements and enhancements for the TTS system, organized by priority and effort.

## Phase 3: Robustness (Medium Priority)

### Background Generation Queue
**Status:** Not implemented
**Current:** Audio generates on-demand when playback is requested
**Proposed:** Generate audio in background as soon as message arrives

**Benefits:**
- Reduces perceived latency when user clicks play
- Better user experience for quick message switching
- Utilizes idle time between messages

**Implementation:**
- Add background worker that pre-generates audio for queued messages
- Show generation progress indicator
- Handle cancellation if user clears queue

### Cache Size Management
**Status:** Not implemented
**Current:** Unbounded memory cache - audio accumulates indefinitely
**Proposed:** LRU cache with configurable size limit (e.g., 50MB)

**Benefits:**
- Prevents memory exhaustion on long conversations
- Graceful handling of resource constraints
- Predictable memory usage

**Implementation:**
- Track cache size in bytes
- Implement LRU eviction policy
- Add cache statistics to settings page
- Configurable max cache size setting

### Enhanced Error Handling
**Status:** Basic error handling exists
**Current:** Errors logged to console, basic state updates
**Proposed:** User-visible error notifications with retry

**Improvements:**
- Toast/snackbar notifications for TTS failures
- Retry mechanism for transient failures (network, busy resources)
- Better error messages ("Failed to generate audio" → "Audio generation failed. Try again?")
- Error recovery strategies (fallback to different voice, etc.)

**Implementation:**
- Add error notification system
- Retry logic with exponential backoff
- User-friendly error messages
- Error state UI in chat messages

## Phase 4: Polish (Low Priority)

### TTS Settings UI
**Status:** Settings exist but no UI
**Current:** Speaker ID and speed in settings model, but not exposed to user
**Proposed:** Settings page section for TTS configuration

**Features:**
- Voice/speaker selection dropdown (0-N available speakers)
- Speech speed slider (0.5x - 2.0x)
- Preview button to test current settings
- Reset to defaults button

**Implementation:**
- Add TTS section to settings page
- Query available speakers from Kokoro model
- Add preview functionality (speak sample text)
- Wire up to existing settings provider

### Voice Previews
**Status:** Not implemented
**Proposed:** Preview different voices before selecting

**Features:**
- Play sample audio for each available voice
- Preview at current speed setting
- Compare voices side-by-side

**Implementation:**
- Sample text: "Hello, this is voice number X"
- Generate previews on-demand or cache common ones
- UI: voice list with play buttons

### Cache Statistics
**Status:** Not implemented
**Proposed:** Show cache usage and statistics

**Features:**
- Current cache size (MB)
- Number of cached messages
- Memory usage indicator
- "Clear cache" button

**Implementation:**
- Add statistics tracking to TtsService
- Display in settings page or debug panel
- Clear cache action

## Phase 5: Advanced Features (Future)

### Multi-Voice Support
**Status:** Infrastructure exists (speakerId parameter)
**Proposed:** Use different voices for user vs assistant

**Features:**
- Assign different voices to different roles
- Voice selection per role in settings
- Preview voices in conversation context

**Implementation:**
- Settings: user voice, assistant voice
- Pass appropriate speakerId based on message role
- UI to configure voice per role

### Background Playback
**Status:** Not implemented
**Proposed:** Continue playback when app is backgrounded

**Platform Integration:**
- Android: MediaSession with notification controls
- iOS: Background audio capabilities
- Notification with play/pause/skip controls

**Features:**
- Playback continues in background
- Lock screen controls
- Notification shows current message
- Handle interruptions (phone calls, other apps)

**Challenges:**
- Platform-specific implementations
- Battery usage concerns
- Background task management

### Streaming TTS Generation
**Status:** Not implemented (batch generation)
**Current:** Wait for full audio generation before playback
**Proposed:** Stream audio chunks as they're generated

**Benefits:**
- Reduced latency for long messages
- Start playback immediately
- Better responsiveness

**Implementation:**
- Check if Sherpa-ONNX supports streaming generation
- Queue-based audio chunk generation
- Seamless playback of chunks
- Handle cancellation mid-stream

**Challenges:**
- Sherpa-ONNX API support unclear
- Complexity of streaming playback
- Chunk boundary handling

### Sentence-by-Sentence Playback
**Status:** Not implemented
**Proposed:** Split long responses, generate and play sentence-by-sentence

**Benefits:**
- Immediate feedback on long responses
- User can interrupt sooner
- More natural conversation flow

**Implementation:**
- Split text by sentence boundaries
- Generate audio for each sentence
- Queue sentences for playback
- Handle interruption/skip

## Implementation Notes

### Priority Order Recommendation:
1. **Cache Size Management** - Prevents memory issues in production
2. **TTS Settings UI** - Exposes existing functionality to users
3. **Enhanced Error Handling** - Better user experience for failures
4. **Background Generation Queue** - Nice performance improvement
5. **Voice Previews** - Polish for settings UI
6. Everything else as needed

### Quick Wins:
- TTS Settings UI (1-2 hours) - Most of the code already exists
- Cache Statistics (1 hour) - Simple UI addition
- Enhanced Error Handling (2-3 hours) - Improves UX significantly

### High Effort:
- Background Playback (2-3 days) - Platform-specific implementations
- Streaming TTS (unknown) - Depends on Sherpa-ONNX capabilities
- Sentence-by-Sentence (1-2 days) - Complex text processing and queueing

## Related Files

**TTS Core:**
- `apps/lib/providers/tts_provider.dart`
- `apps/lib/tts/services.dart`
- `apps/lib/tts/audio_source.dart`
- `apps/lib/tts/sherpa_tts.dart`

**Settings:**
- `apps/lib/models/settings.dart`
- `apps/lib/providers/settings_provider.dart`
- `apps/lib/pages/settings_page.dart`

**UI:**
- `apps/lib/chat/widgets.dart`
- `apps/lib/widgets/voice_mode_selector.dart`

## Notes

- All improvements should maintain the current privacy-first approach (on-device processing)
- Keep simplicity as a core value - avoid over-engineering
- Test thoroughly on resource-constrained devices (Android mid-range phones)
- Consider battery impact for any background processing features

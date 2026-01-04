# Mobile Performance Optimization Research

## Problem Statement

The Relagent Android app experiences Application Not Responding (ANR) errors and performance degradation, particularly around:

- Speech recognition model initialization and usage
- Text-to-speech (TTS) model initialization and audio generation
- HTTP communication with the backend
- Audio data processing and caching

ANRs occur when the main thread is blocked for more than 5 seconds, causing the Android system to show a "App not responding" dialog.

## Root Cause Analysis

### Critical Issues Identified

#### 1. Model Initialization on Main Thread (CRITICAL)

**Speech Recognition (ASR)**

- Location: `apps/lib/speech_recognition/services.dart:43-50`
- Problem: `ASR.start()` performs heavy initialization synchronously on the main thread:
  - `sherpa_onnx.initBindings()` - Native library initialization
  - `createOnlineRecognizer()` - Loads 3 ONNX models (encoder, decoder, joiner)
  - `copyAssetFileToCache()` - Copies large model files from assets to cache
- Impact: Can block main thread for 1-5+ seconds depending on device and model size
- Trigger: Every time recording starts (first time or when resuming)

**Text-to-Speech (TTS)**

- Location: `apps/lib/tts/services.dart:26-37`
- Problem: `TtsService._init()` performs heavy initialization synchronously:
  - `sherpa_onnx.initBindings()` - Native library initialization
  - `createOfflineTts()` - Loads TTS ONNX model
- Impact: Blocks main thread for 1-3+ seconds on first TTS request
- Trigger: First call to `speak()` method

#### 2. Audio Generation on Main Thread (HIGH)

**TTS Audio Generation**

- Location: `apps/lib/tts/services.dart:48`
- Problem: `_tts!.generate(text: text, sid: speakerId, speed: speed)` runs synchronously
- Impact: Blocks main thread during speech synthesis (varies by text length)
- Trigger: Every TTS playback request without cached audio

#### 3. Memory Management Issues (MEDIUM)

**TTS Audio Cache**

- Location: `apps/lib/tts/services.dart:14`
- Problem: `Map<String, Uint8List> _audioCache` stores all generated audio in memory
- Impact: Memory consumption grows unbounded with conversation length
- Can cause:
  - Out of memory errors on low-end devices
  - Garbage collection pauses
  - Reduced performance as memory pressure increases
- No cleanup strategy for old/unused audio

**Asset File Copying**

- Location: `apps/lib/utils/files.dart:11-39`
- Problem: Entire ONNX models (potentially 10-50+ MB each) loaded into memory during copying
- Impact: High memory usage during initialization

#### 4. HTTP Communication (LOW-MEDIUM)

**Missing Timeout**

- Location: `apps/lib/chat/services.dart:56`
- Problem: `http.post()` has no timeout parameter
- Impact: Can hang indefinitely if network is slow or server unresponsive
- Default timeout varies by platform and can be very long

**No Connection Pooling**

- Problem: Each request creates new connection
- Impact: Higher latency on subsequent requests

#### 5. Audio Processing on Main Thread (LOW-MEDIUM)

**Stream Processing**

- Location: `apps/lib/speech_recognition/services.dart:83-105`
- Problem: Audio stream listener processes on main thread:
  - Byte-to-float32 conversion
  - Sherpa recognizer `decode()` and `getResult()` calls
- Impact: Continuous CPU load on main thread during recording
- Frequency: Every audio chunk (potentially 100ms intervals)

### Architecture Constraints

The app is designed to run in the background waiting for events:

- Continuous voice listening in certain modes
- Must remain responsive during model operations
- Limited device resources (especially on budget Android devices)
- Large ONNX models (ASR models can be 30-50MB+, TTS models 20-40MB+)

## Performance Profiling Tools & Techniques

### Flutter DevTools

**Observatory Performance View**

- Timeline view to identify janky frames
- CPU profiler to find hot spots
- Memory profiler to detect leaks
- Usage: `flutter run --profile` then open DevTools

**CPU Flame Charts**

- Visualize method execution time
- Identify synchronous blocking operations
- Command: Available in DevTools Performance tab

### Android-Specific Tools

**Android Studio Profiler**

- CPU profiling with method tracing
- Memory allocation tracking
- Network profiling
- Usage: Attach to running Flutter app

**ADB Logcat with Timeline**

- Monitor for "Choreographer" frame skip warnings
- ANR traces in system logs
- Command: `adb logcat | grep -E "(Choreographer|ANR|skipped)"`

**StrictMode**

- Add to Android-specific code to detect main thread violations
- Warns about disk reads, network access on main thread

### Flutter-Specific Profiling

**Performance Overlay**

- Shows frame rendering times
- Red bars indicate janky frames (>16ms)
- Enable with: `flutter run --profile` + overlay button in app

**Dart Observatory**

- Isolate view to monitor background work
- GC events and pauses
- Timeline events for async operations

**Custom Performance Markers**

```dart
// Add timeline events
import 'dart:developer';

Timeline.startSync('model_loading');
// ... heavy operation ...
Timeline.finishSync();
```

### Benchmarking Commands

```bash
# Profile mode (optimized with profiling enabled)
flutter run --profile

# Release mode testing (production performance)
flutter run --release

# Memory usage monitoring
adb shell dumpsys meminfo org.venkado.relagent

# CPU usage monitoring
adb shell top -m 10 -s cpu

# Method tracing
flutter run --profile --trace-startup
```

## Proposed Solutions

### 1. Isolate-Based Model Loading (CRITICAL - Highest Priority)

**Goal:** Move all model initialization off the main thread

**Implementation:**

- Use Dart isolates to load ONNX models in background
- Initialize models once at app startup in dedicated isolate
- Keep models loaded for app lifetime (or until memory pressure)
- Communicate with model isolate via SendPort/ReceivePort

**Benefits:**

- Eliminates ANRs from model loading
- App remains responsive during initialization
- Can show progress indicator to user

**Challenges:**

- Sherpa-ONNX FFI bindings may not be isolate-safe (need to verify)
- SendPort can only transfer primitive types and some collections
- May need to use Platform Channels for model initialization

**Alternative: Platform Channels**

- Initialize models in native Android code (Kotlin/Java)
- Use MethodChannel to call from Dart
- Native code runs on background thread automatically
- Better control over lifecycle and memory

### 2. Lazy Model Loading with Progress Indicators

**Goal:** Prevent blocking UI with clear user feedback

**Implementation:**

- Show loading overlay during model initialization
- Load models on first use, not at startup
- Cache initialized models for session lifetime
- Implement warmup period during app splash screen

**User Experience:**

- First TTS: "Initializing voice system..."
- First ASR: "Loading speech recognition..."
- Subsequent uses: Instant

### 3. Audio Generation in Background

**Goal:** Move TTS generation off main thread

**Implementation:**

```dart
Future<Uint8List> _generateAudioInBackground(String text) async {
  return await compute(_generateAudioIsolate, GenerateParams(
    text: text,
    speakerId: speakerId,
    speed: speed,
  ));
}

static Uint8List _generateAudioIsolate(GenerateParams params) {
  // This runs in separate isolate
  final tts = createOfflineTts(); // Need to verify if this works in isolate
  final audio = tts.generate(...);
  return generateWavBytes(audio);
}
```

**Benefits:**

- Main thread stays responsive during generation
- Can generate multiple audio clips concurrently
- User can continue interacting with app

### 4. Memory Management & Caching Strategy

**TTS Audio Cache Improvements:**

```dart
class TtsAudioCache {
  final int maxCacheSizeBytes;
  final int maxCacheItems;
  final Map<String, CachedAudio> _cache = {};
  int _totalBytes = 0;

  // LRU eviction policy
  void _evictIfNeeded(int newBytes) {
    if (_totalBytes + newBytes > maxCacheSizeBytes ||
        _cache.length >= maxCacheItems) {
      // Remove oldest/least recently used items
    }
  }
}
```

**Strategies:**

- Limit cache to last N messages (e.g., 20)
- Limit total cache size (e.g., 50MB)
- Clear cache on memory pressure (use WidgetsBindingObserver)
- Consider disk caching for long-term storage

**Asset Loading:**

- Stream file copying instead of loading entire file into memory
- Use `RandomAccessFile` for chunked operations
- Check available memory before copying large files

### 5. HTTP Timeout & Connection Management

**Add Timeouts:**

```dart
final client = http.Client();
try {
  response = await client.post(
    uri,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  ).timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      throw ChatApiException(
        userMessage: 'Request timed out',
        technicalDetails: 'Server did not respond within 30 seconds',
      );
    },
  );
} finally {
  client.close();
}
```

**Connection Pooling:**

- Create singleton HTTP client for reuse
- Configure keep-alive settings
- Set reasonable connection limits

### 6. Audio Processing Optimization

**Options:**

- Verify if Sherpa-ONNX processes audio in native thread
- If not, consider processing in background isolate
- Batch audio chunks if possible
- Use lower sample rates if acceptable (16kHz vs 48kHz)

### 7. Background Processing Architecture

**Android WorkManager Integration:**

- Use WorkManager for deferrable background tasks
- Schedule model preloading during device charging/WiFi
- Handle model updates in background

**Foreground Service for Always-On Listening:**

```dart
// Platform channel to Android Service
class VoiceListeningService {
  // Keep app alive in background
  // Show persistent notification (required for foreground service)
  // Receive audio even when app not visible
}
```

**Considerations:**

- Foreground services require persistent notification
- Battery impact must be minimal
- Respect Android Doze mode
- Handle service lifecycle properly

### 8. Multi-App Architecture (Optional)

For very resource-constrained scenarios, consider splitting:

**App 1: Lightweight Frontend**

- UI only
- Minimal dependencies
- Quick startup

**App 2: Model Service**

- Runs as Android Service
- Loads and manages ONNX models
- Accessed via AIDL or Messenger
- Can be shared by multiple apps
- Started once, used by all

**Benefits:**

- Frontend stays responsive
- Models stay loaded across sessions
- Can update models independently
- Better resource isolation

**Drawbacks:**

- Increased complexity
- Inter-process communication overhead
- More difficult to debug
- Requires two APKs or complex installation

## Implementation Priorities

### Phase 1: Quick Wins (1-2 weeks)

1. **Add HTTP timeouts** - 1 hour
2. **Add performance profiling markers** - 2 hours
3. **Implement TTS audio cache limits** - 4 hours
4. **Show loading indicators during model init** - 4 hours
5. **Profile app with DevTools to confirm bottlenecks** - 4 hours

### Phase 2: Core Optimizations (2-4 weeks)

1. **Move model loading to background (isolates or platform channels)** - 1-2 weeks
2. **Implement TTS generation in background** - 3-5 days
3. **Optimize asset file copying** - 2 days
4. **Implement proper cache eviction** - 3 days

### Phase 3: Advanced Optimizations (1-2 months)

1. **Implement foreground service for background listening** - 1 week
2. **Add memory pressure handling** - 3 days
3. **Optimize audio processing pipeline** - 1 week
4. **Consider model quantization/compression** - 2 weeks

### Phase 4: Architecture (Future)

1. **Evaluate multi-app architecture** - Research phase
2. **Prototype model service** - 2-3 weeks
3. **Performance comparison** - 1 week

## Monitoring & Validation

### Success Metrics

- Zero ANR errors in production
- Frame rate consistently above 55 FPS (out of 60)
- Model initialization < 200ms perceived delay
- Memory usage stable over long sessions (no leaks)
- TTS generation doesn't block UI

### Testing Strategy

1. **Device Matrix Testing**

   - Test on low-end devices (1-2GB RAM, older SoCs)
   - Test on mid-range devices
   - Test on high-end devices
   - Focus on worst-case scenarios

2. **Load Testing**

   - Long conversation sessions (100+ messages)
   - Rapid TTS requests
   - Continuous recording for extended periods
   - Background/foreground transitions

3. **Profiling Checkpoints**
   - Profile before optimizations (baseline)
   - Profile after each phase
   - Automated performance regression tests

### Key Performance Indicators

```dart
// Add telemetry
class PerformanceMetrics {
  static void trackModelLoadTime(String modelType, Duration duration) {
    debugPrint('$modelType load time: ${duration.inMilliseconds}ms');
    // Send to analytics if applicable
  }

  static void trackTtsGeneration(String messageId, int textLength, Duration duration) {
    debugPrint('TTS generation for $textLength chars: ${duration.inMilliseconds}ms');
  }

  static void trackMemoryUsage() {
    // Periodically log memory stats
  }
}
```

## Additional Considerations

### Device Resource Constraints

**Memory Limits:**

- Budget Android devices: 1-2GB total RAM
- App may get 200-500MB max before OOM
- ONNX models: 50-100MB combined
- Audio cache: Can grow to 10-50MB
- System reserves significant portion for UI

**CPU Considerations:**

- Low-end SoCs struggle with ONNX inference
- May need model quantization (INT8 vs FP32)
- Consider model size vs accuracy tradeoffs

**Storage:**

- Models stored in app cache directory
- Can be cleared by system under pressure
- Need strategy to re-download if cleared

### Battery Impact

**Continuous Listening:**

- Audio recording drains battery
- ONNX inference is CPU-intensive
- Need to balance responsiveness vs battery life

**Optimization Strategies:**

- Use lower sample rates when possible
- Implement VAD (Voice Activity Detection) to reduce processing
- Pause listening when screen off (configurable)
- Batch processing where possible

### Android Background Restrictions

**Doze Mode:**

- System limits background processing
- Foreground service exempt from most restrictions
- Need persistent notification

**App Standby:**

- System restricts network and jobs
- Foreground service keeps app active
- Must handle standby bucket changes

**Battery Optimization:**

- Users can enable aggressive optimization
- May kill background services
- Need to request exemption for critical use cases

## References & Resources

### Flutter Performance

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter Performance Profiling](https://docs.flutter.dev/perf/ui-performance)
- [Using Isolates](https://dart.dev/guides/language/concurrency)

### Android Development

- [Android Background Execution Limits](https://developer.android.com/about/versions/oreo/background)
- [Foreground Services](https://developer.android.com/guide/components/foreground-services)
- [WorkManager](https://developer.android.com/topic/libraries/architecture/workmanager)
- [ANR Detection](https://developer.android.com/topic/performance/vitals/anr)

### ONNX & ML Performance

- [Sherpa-ONNX Documentation](https://k2-fsa.github.io/sherpa/onnx/)
- [ONNX Runtime Mobile](https://onnxruntime.ai/docs/tutorials/mobile/)
- [Model Quantization](https://onnxruntime.ai/docs/performance/quantization.html)

### Tools

- [Flutter DevTools](https://docs.flutter.dev/development/tools/devtools/overview)
- [Android Profiler](https://developer.android.com/studio/profile/android-profiler)
- [Memory Profiler](https://developer.android.com/studio/profile/memory-profiler)

## Next Steps

1. **Consult with project architect** for architectural recommendations
2. **Profile current app** to validate assumptions and measure baseline
3. **Implement Phase 1 quick wins** to get immediate improvements
4. **Prototype isolate-based model loading** to validate feasibility
5. **Test on low-end Android devices** to confirm improvements
6. **Document findings** and update implementation plan

---

## Architect Review & Recommendations

### Executive Summary

The project architect has reviewed the performance analysis and provided strategic recommendations prioritizing simplicity and cross-platform compatibility while addressing critical ANR issues.

### Key Architectural Decisions

#### 1. Isolates Over Platform Channels (APPROVED)

**Decision:** Start with Dart isolates and `compute()` for background processing. Only use platform channels if FFI proves incompatible.

**Rationale:**

- Maintains cross-platform code (Android, iOS, Linux)
- Aligns with project simplicity principle
- Easier to maintain and debug
- Must verify Sherpa-ONNX FFI isolate safety through profiling first

#### 2. Model Preloading at Startup (APPROVED)

**Decision:** Load all models during app splash screen, not on-demand.

**Implementation:**

```dart
// In main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(...);

  // Preload models during splash with progress indicator
  final modelLoader = container.read(modelLoaderProvider.notifier);
  await modelLoader.preloadModels();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const MyApp(),
  ));
}
```

**Rationale:**

- Models are core functionality, not optional features
- One-time startup cost (1-2 seconds) for instant functionality
- Eliminates first-use delays entirely
- Aligns with "always-ready assistant" vision
- 50-100MB memory acceptable on modern devices (4GB+ RAM)
- For low-end devices (<2GB RAM), add optional lazy-load setting

#### 3. Simple LRU Cache (APPROVED)

**Decision:** Fixed-size cache with 20 messages, simple eviction.

**Implementation:**

```dart
class TtsService {
  final int _maxCacheItems = 20; // ~10-20MB total
  final List<String> _cacheOrder = []; // LRU tracking

  void _addToCache(String messageId, Uint8List audio) {
    if (_cacheOrder.length >= _maxCacheItems) {
      final oldest = _cacheOrder.removeAt(0);
      _audioCache.remove(oldest);
    }
    _cacheOrder.remove(messageId);
    _cacheOrder.add(messageId);
    _audioCache[messageId] = audio;
  }
}
```

**Rationale:**

- Simple implementation (no byte-level tracking needed)
- 20 messages × ~500KB = ~10MB total (acceptable)
- Cleanup already exists, just needs eviction logic

#### 4. Multi-App Architecture (REJECTED)

**Decision:** Do not pursue separate model service app.

**Rationale:**

- Violates simplicity principle
- Introduces IPC complexity, dual APKs, difficult debugging
- Premature optimization - simpler solutions can address issues
- Maintenance burden too high
- Alternative: Model quantization if memory becomes critical

#### 5. Foreground Service (CONDITIONALLY APPROVED)

**Decision:** Implement only as optional "background listening mode" with user consent.

**Requirements:**

- Must be optional, not default behavior
- Requires persistent notification: "Relagent is listening for commands"
- User explicitly enables in settings
- Proper service lifecycle management
- Document battery impact honestly

**Rationale:**

- Necessary for ambient assistant use case
- Notification ensures transparency (privacy-first)
- Optional preserves simplicity for users who don't need it
- Aligns with vision while maintaining user control

### Revised Implementation Plan

#### Phase 0: Profiling & Validation (Week 1)

**CRITICAL: Must complete before implementing optimizations**

1. Add performance markers to critical paths:

   ```dart
   import 'dart:developer' as developer;

   Future<void> _init() async {
     developer.Timeline.startSync('TTS_Initialization');
     try {
       sherpa_onnx.initBindings();
       _tts = await createOfflineTts();
       _isInitialized = true;
     } finally {
       developer.Timeline.finishSync();
     }
   }
   ```

2. Profile on low-end Android device (1-2GB RAM)
3. Measure:
   - Exact model load times
   - Memory usage over 30-minute session
   - Frame drops during TTS generation
   - Verify Sherpa-ONNX FFI isolate safety
4. Establish baseline metrics

**Tools:**

```bash
flutter run --profile
# Open DevTools for timeline analysis
adb shell dumpsys meminfo org.venkado.relagent
```

#### Phase 1: Quick Wins (Week 2)

1. **HTTP timeouts** (2 hours)

   - Add 30-second timeout to all requests
   - Create singleton HTTP client for connection pooling

2. **Loading indicators** (4 hours)

   - Show progress during model initialization
   - "Initializing voice system..." overlay

3. **Simple LRU cache** (4 hours)

   - Fixed 20-message limit
   - Simple eviction on overflow

4. **Asset copying optimization** (conditional)
   - Only if profiling shows this is a bottleneck

#### Phase 2: Background Processing (Weeks 3-4)

1. **Model preloading** (3 days)

   - Create `modelLoaderProvider` in Riverpod
   - Load during splash screen with progress
   - Services receive pre-initialized models

2. **TTS generation via compute()** (3 days)

   - If isolates work with Sherpa-ONNX FFI
   - Background audio generation

3. **Fallback implementation** (2 days)
   - If isolates fail: main-thread with progress UI
   - Ensure graceful degradation

#### Phase 3: Advanced Features (Month 2+, if needed)

1. **Optional foreground service** (1 week)

   - Background listening mode
   - User opt-in required
   - Persistent notification

2. **Memory pressure handling** (3 days)

   - WidgetsBindingObserver for system warnings
   - Unload models under pressure

3. **Model optimization research** (ongoing)
   - INT8 quantization if needed
   - Smaller model variants

#### Phase 4: Deprecated

- Multi-app architecture - not pursuing

### Riverpod Integration Pattern

**New Provider: Model Loader**

```dart
// lib/providers/model_loader_provider.dart
enum ModelLoadState { unloaded, loading, loaded, error }

class ModelLoaderState {
  final ModelLoadState asrState;
  final ModelLoadState ttsState;
  final String? errorMessage;
  final double progress; // 0.0 to 1.0

  bool get isReady => asrState == ModelLoadState.loaded &&
                       ttsState == ModelLoadState.loaded;
}

class ModelLoaderNotifier extends StateNotifier<ModelLoaderState> {
  ModelLoaderNotifier() : super(ModelLoaderState.initial());

  Future<void> preloadModels() async {
    state = state.copyWith(asrState: ModelLoadState.loading, progress: 0.0);

    try {
      await _loadAsrModel();
      state = state.copyWith(asrState: ModelLoadState.loaded, progress: 0.5);

      await _loadTtsModel();
      state = state.copyWith(ttsState: ModelLoadState.loaded, progress: 1.0);
    } catch (e) {
      state = state.copyWith(
        asrState: ModelLoadState.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final modelLoaderProvider =
    StateNotifierProvider<ModelLoaderNotifier, ModelLoaderState>(
  (ref) => ModelLoaderNotifier(),
);
```

**Service Integration:**

```dart
// Services receive already-initialized models
class ASR {
  final sherpa_onnx.OnlineRecognizer recognizer;

  ASR(this.recognizer); // Injected, not created
  // No more _init() needed!
}

final asrServiceProvider = Provider<ASR>((ref) {
  final modelState = ref.watch(modelLoaderProvider);
  if (!modelState.isReady) {
    throw Exception('Models not loaded');
  }
  return ASR(modelManager.asrRecognizer);
});
```

**UI Integration:**

```dart
class SplashScreen extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final modelState = ref.watch(modelLoaderProvider);

    return Scaffold(
      body: Center(
        child: Column(
          children: [
            CircularProgressIndicator(value: modelState.progress),
            Text('Initializing voice system...'),
            if (modelState.errorMessage != null)
              Text('Error: ${modelState.errorMessage}'),
          ],
        ),
      ),
    );
  }
}
```

### Critical Success Factors

1. **Measure before optimizing** - Avoid premature complexity
2. **Maintain cross-platform code** - Isolates over platform channels
3. **Preserve simplicity** - Reject architectural complexity where possible
4. **Be transparent** - Document battery impact, show notifications
5. **Stay pragmatic** - Good enough beats perfect

### Memory Budget Guidelines

**Target Devices:**

- Modern devices (4GB+ RAM): No special considerations needed
- Mid-range (2-3GB RAM): Should work fine with current plan
- Low-end (<2GB RAM): Add optional lazy loading setting

**Memory Allocation:**

- ONNX models loaded: 50-100MB
- TTS audio cache: ~10-20MB (20 messages)
- App overhead: ~50MB
- **Total: ~150-170MB** (acceptable on most devices)

### Performance Targets

**Success Metrics:**

- Zero ANR errors in production
- Frame rate consistently above 55 FPS
- Model initialization perceived delay < 2 seconds (splash screen)
- TTS generation doesn't block UI (runs in background)
- Memory stable over 1-hour session (no leaks)

### Future Considerations

**Scaling Concerns:**

- Adding vision, RAG, or other ML models will increase startup time
- Consider progressive loading: ASR first, then TTS, then optional models
- May need dedicated model manager service for multiple ML features

**Battery Optimization:**

- Implement VAD (Voice Activity Detection) to reduce processing during silence
- Configurable sample rates (8kHz for low-power, 16kHz for quality)
- Show battery usage metrics to user

**Platform-Specific ML Acceleration:**

- iOS: CoreML
- Android: NNAPI
- Only pursue after exhausting cross-platform solutions
- Investigate only if profiling shows performance critical issues

### Alignment with Project Principles

The architect confirms these optimizations align with project values:

- **Privacy:** All processing remains on-device
- **Simplicity:** Solutions prioritize simple, cross-platform code
- **Open source:** No proprietary dependencies introduced
- **Accessibility:** Optimized for consumer-grade hardware
- **Transparency:** User-visible loading states, clear notifications

---

_Document created: 2025-11-28_
_Last updated: 2025-11-28_
_Status: Architect review complete - ready for Phase 0 profiling_

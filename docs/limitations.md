# Limitations and failures

## Kokoro TTS licensing

The [kokoro TTS models](https://github.com/thewh1teagle/kokoro-onnx) released by sherpa-onnx include espeak-ng-data. This might lead to licensing issues if distributed together.

espeak-ng is only available as a GPL library. Requiring all derived work to be also released under GPL. But Relagent tries to remain less restrictive using a more permissive license. Future models might no longer require espeak-ng-data. Then the model might be bundled with the app. See: https://github.com/hexgrad/kokoro/issues/247

## Performance

This software should be usable and fluent enough for daily use. But no extensive effort will be put into optimizations that are very likely to be solved by advances in available models or libraries. Also increased hardware capabilities can be expected to get ideal performance.

## Audio recording stops background music (Android)

**Issue:** When the app starts voice recording (continuous or one-time), background music from other apps (Spotify, YouTube Music, etc.) is stopped instead of ducked (volume lowered).

**Root cause:** The `record` package (v6.1.2) manages Android audio focus internally and does not expose configuration options for audio mixing behavior. Despite attempts to configure audio session settings via:

- `audio_session` package (tried versions 0.1.25 and 0.2.2)
- `AndroidRecordConfig.audioManagerMode = modeNormal`
- Various audio session configurations (mixWithOthers, duckOthers, voiceChat mode, etc.)

The package continues to request exclusive audio focus, causing other apps' audio to stop completely.

## Phone call notification state (Android)

**Issue:** During phone calls or audio interruptions, the app notification may not update to show "Waiting..." status, continuing to display "Listening..." or "Speaking..." even though audio has paused.

**Root cause:** Phone call interruptions cannot be reliably detected:

- The `record` package handles audio focus internally but doesn't emit state change events during interruptions
- The `audio_session` package's interruption events are inconsistent (work for playback, not for recording)
- Internal app transitions (TTS→recording) trigger false positive interruption events

**Impact:** Low - Audio correctly pauses during calls and resumes after, but notification state is misleading. The underlying functionality works correctly.

**Potential solutions:** Monitor Android telephony broadcasts via platform channels, or contribute audio focus event handling to the `record` package.

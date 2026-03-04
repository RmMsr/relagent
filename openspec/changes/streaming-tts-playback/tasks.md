## 1. Isolate protocol — streaming messages

- [ ] 1.1 Add `StreamGenerateAudioMessage` to the `TtsWorkerMessage` sealed class in `tts_isolate_worker.dart` with fields: `text`, `messageId`, `speakerId`, `speed`, `chunkSendPort: SendPort`
- [ ] 1.2 Add `AudioChunkResponse(Float32List samples, int sampleRate)` to the `TtsWorkerResponse` sealed class
- [ ] 1.3 Add `AudioStreamDoneResponse()` to the `TtsWorkerResponse` sealed class

## 2. Isolate worker — streaming generation

- [ ] 2.1 Handle `StreamGenerateAudioMessage` in the isolate `receivePort.listen` switch: call `tts.generateWithCallback` with a callback that sends `AudioChunkResponse` via `chunkSendPort`
- [ ] 2.2 After the callback loop ends, send `AudioStreamDoneResponse` via `chunkSendPort`
- [ ] 2.3 Add `TtsIsolateWorker.generateAudioStream()` method that sends `StreamGenerateAudioMessage` and returns a `Stream<(Float32List samples, int sampleRate)>` by listening to a dedicated `ReceivePort`

## 3. StreamingWavAudioSource

- [ ] 3.1 Create `apps/lib/tts/streaming_wav_audio_source.dart` with `StreamingWavAudioSource extends StreamAudioSource`
- [ ] 3.2 Implement constructor accepting `Stream<List<int>> pcmStream` and `int sampleRate`
- [ ] 3.3 Implement `request([int? start, int? end])`: emit 44-byte WAV header with `0xFFFFFFFF` sentinel sizes, then forward `pcmStream` bytes; return `StreamAudioResponse` with `contentType: 'audio/wav'` and `contentLength: null`
- [ ] 3.4 Add `float32ToInt16Le(Float32List samples)` helper that converts each sample (clamped to −1.0…1.0) to a signed 16-bit LE byte pair

## 4. PlaybackItem — stream support

- [ ] 4.1 Add `Stream<List<int>>? streamContent` field to `PlaybackItem` (nullable; exactly one of `content` or `streamContent` is non-null)
- [ ] 4.2 Add a named constructor or factory `PlaybackItem.stream({required String id, required Stream<List<int>> streamContent, ...})`

## 5. PlaybackService — streaming playback path

- [ ] 5.1 In `PlaybackService._processNext`, branch on whether the next item has `streamContent` set
- [ ] 5.2 For streaming items, skip `await nextItem.content` and proceed directly to `_playStreamItem`
- [ ] 5.3 Implement `_playStreamItem(Stream<List<int>> stream, int sampleRate)`: create `StreamingWavAudioSource`, call `_player.setAudioSource(source)`, then `_player.play()`

## 6. VoiceService interface and implementations

- [ ] 6.1 Add `Stream<List<int>> generateSpeechStream(String text, String messageId, {required int speakerId, required double speed})` to the abstract `VoiceService` class
- [ ] 6.2 Implement `generateSpeechStream` in the native `VoiceService` implementation: call `TtsIsolateWorker.generateAudioStream`, convert `Float32List` chunks to 16-bit LE bytes via `float32ToInt16Le`, pipe through a `StreamController<List<int>>`
- [ ] 6.3 Implement `generateSpeechStream` in the web stub: return `const Stream.empty()`

## 7. TtsService — streaming generate method

- [ ] 7.1 Add `bool streamingDisabled = false` property to `TtsService`
- [ ] 7.2 Add `Stream<List<int>> generateStream(String text, String messageId)` method to `TtsService` that calls `_voiceService.generateSpeechStream(...)` (bypasses the audio cache)

## 8. TtsNotifier — mode selection

- [ ] 8.1 In `TtsNotifier._getService` / `_handleTtsModelChanged`, read `settings.ttsModelBenchmarks[selectedTtsModelId]` and set `service.streamingDisabled = rtf != null && rtf > 1.10`
- [ ] 8.2 In `TtsNotifier.enqueue` and `playNow`, check `service.streamingDisabled`: if false, call `service.generateStream` and build a `PlaybackItem.stream`; otherwise use the existing `service.generate` path

## 9. Pre-playback pause

- [ ] 9.1 In `AudioCoordinator.requestPlayback()`, change the `await Future<void>.delayed(const Duration(milliseconds: 200))` in the recording→playback transition branch to `const Duration(milliseconds: 900)`, giving ≈ 1 s total from recording stop to playback start

## 10. Isolate crash safety

- [ ] 9.1 In `TtsIsolateWorker`, listen to `_isolate.errors` and close the chunk `StreamController` with an error if the isolate crashes during streaming

## 11. Analysis and tests

- [ ] 11.1 Run `dart-flutter_analyze_files` on `apps/`; fix all issues
- [ ] 11.2 Run `dart-flutter_run_tests` on `apps/`; confirm all tests pass
- [ ] 11.3 Manually test streaming playback on Android: confirm first word plays before synthesis completes on a slow model
- [ ] 11.4 Manually verify ASR does not pick up TTS output: enable conversation mode, trigger a TTS response, confirm no loopback text appears

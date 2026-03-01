## Context

`AsrModelMetadata` is a plain Dart class with no `==` override. Every call to `resolveAsrMetadata()` returns a new object instance. The identity check in `VoiceServiceNative._startRecording()` uses object reference (`!=`), which always evaluates to "different model" — triggering full model disposal and recreation (InitEncoder/InitDecoder/InitJoiner, several seconds) on every recording start after the first.

## Goals / Non-Goals

**Goals:**
- ASR recognizer is reused across recordings when the selected model has not changed
- Second and subsequent recordings start immediately instead of after several seconds of model reload

**Non-Goals:**
- Changing `AsrModelMetadata` equality (would require touching the model class and all usages)

## Decisions

### 1. Compare by `modelId` string instead of object reference

**Decision:** Change the model identity comparison in `VoiceServiceNative._startRecording()` from `_currentModel != metadata` (object reference) to `_currentModel?.modelId != metadata?.modelId` (string comparison).

**Why:** `modelId` is the stable identifier for a model across instances. String comparison is a minimal, targeted fix with no side effects. Adding `==` to `AsrModelMetadata` would be a larger change affecting more code and is not necessary for this fix.

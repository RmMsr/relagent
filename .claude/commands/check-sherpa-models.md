# Check Sherpa-ONNX ASR Models

Check for new streaming ASR models available in sherpa-onnx that could be used in the Relagent project:

1. Search for the latest sherpa-onnx streaming ASR models (check GitHub releases, documentation, and model repository)
2. Compare with the models currently referenced in the project (check apps/assets/ and any model configuration)
3. Identify any new models that have been added since the last check
4. Evaluate new models for:
   - Language support (especially English and European languages)
   - Model size and performance characteristics
   - Suitability for on-device use in the Flutter app
   - Multilingual support (check for universal/omnilingual models)
5. Report findings with recommendations on whether to update or add new models

Focus **ONLY on true streaming ASR models** suitable for real-time speech recognition on consumer hardware. Exclude offline/non-streaming models completely.

## Models of Interest

- **Current model**: sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06 (English only)
- **To evaluate**: Meta Omnilingual ASR (sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-int8) - supports 1600+ languages including all European languages, true streaming CTC model

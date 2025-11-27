# Limitations and failures

## Kokoro TTS licensing

The [kokoro TTS models](https://github.com/thewh1teagle/kokoro-onnx) released by sherpa-onnx include espeak-ng-data. This might lead to licensing issues if distributed together.

espeak-ng is only available as a GPL library. Requiring all derived work to be also released under GPL. But Relagent tries to remain less restrictive using a more permissive license. Future models might no longer require espeak-ng-data. Then the model might be bundled with the app. See: https://github.com/hexgrad/kokoro/issues/247

## Performance

This software should be usable and fluent enough for daily use. But no extensive effort will be put into optimizations that are very likely to be solved by advances in available models or libraries. Also increased hardware capabilities can be expected to get ideal performance.

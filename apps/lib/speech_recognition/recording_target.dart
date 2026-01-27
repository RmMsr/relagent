/// Interface for widgets that can receive speech recognition input.
///
/// Implement this interface to create widgets that can receive text from
/// speech recognition. The RecordingProvider will route all speech events
/// to the currently active RecordingTarget.
///
/// Only one RecordingTarget can be active at a time. If a new target
/// starts recording, the previous target must be stopped first.
abstract class RecordingTarget {
  /// Called when text is recognized from speech input.
  ///
  /// This is called for both partial and final recognized text.
  /// Implementations should update their text field/display with the
  /// recognized text, replacing any previous recognized text.
  ///
  /// [text] The recognized text to display
  void onTextRecognized(String text);

  /// Called when speech input has finished and should be submitted.
  ///
  /// This is called when:
  /// - Endpoint is detected in continuous listening mode
  /// - User explicitly submits the text (e.g., presses Enter)
  ///
  /// Implementations should submit the current text and clear the input field.
  void onTextFinished();

  /// Called when recording has started.
  ///
  /// Implementations can use this to show UI feedback (e.g., start
  /// animation, show recording indicator). This is optional - can be no-op.
  void onRecordingStarted();

  /// Called when recording has stopped.
  ///
  /// Implementations can use this to hide UI feedback (e.g., stop animation,
  /// hide recording indicator). This is optional - can be no-op.
  void onRecordingStopped();

  /// Called when an error occurs during recording.
  ///
  /// Implementations should display the error to the user (e.g., show
  /// a snackbar, display error text) or log it for debugging.
  ///
  /// [error] A human-readable error message
  void onError(String error);
}

/// Pure decision logic for the `config` wizard's blank-keeps-current
/// behavior — kept free of terminal I/O so it can be unit tested directly.
/// See the cli-config spec's "Wizard Preserves Current Value on Blank
/// Input" requirement.
class ConfigWizardDecision {
  /// The engine URL to persist — [currentUrl] unchanged if [urlInput] was
  /// blank.
  final String engineUrl;

  /// Whether [engineUrl] differs from the value the wizard started with.
  final bool urlChanged;

  /// The new token to store, or `null` when [tokenInput] was blank and the
  /// existing stored token (if any) should be left untouched.
  final String? newToken;

  /// Whether `chat` should purge the session on exit by default —
  /// [currentAlwaysPurgeSession] unchanged if [alwaysPurgeSessionInput] was
  /// blank.
  final bool alwaysPurgeSession;

  const ConfigWizardDecision({
    required this.engineUrl,
    required this.urlChanged,
    this.newToken,
    required this.alwaysPurgeSession,
  });
}

ConfigWizardDecision decideConfigWizardAnswers({
  required String currentUrl,
  required String urlInput,
  required String tokenInput,
  bool currentAlwaysPurgeSession = false,
  String alwaysPurgeSessionInput = '',
}) {
  final trimmedUrl = urlInput.trim();
  final engineUrl = trimmedUrl.isEmpty ? currentUrl : trimmedUrl;

  final trimmedPurge = alwaysPurgeSessionInput.trim().toLowerCase();
  final alwaysPurgeSession = trimmedPurge.isEmpty
      ? currentAlwaysPurgeSession
      : (trimmedPurge == 'y' || trimmedPurge == 'yes');

  return ConfigWizardDecision(
    engineUrl: engineUrl,
    urlChanged: trimmedUrl.isNotEmpty && trimmedUrl != currentUrl,
    newToken: tokenInput.isEmpty ? null : tokenInput,
    alwaysPurgeSession: alwaysPurgeSession,
  );
}

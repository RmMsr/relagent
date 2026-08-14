import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/providers/settings_provider.dart';

/// The session currently shown in the chat UI.
///
/// Decoupled from [Settings.agenticSessionId], which persists only the last
/// session to restore on next launch. Live session switching flows through
/// this provider instead; callers that want the switch to survive a restart
/// persist to [Settings.agenticSessionId] separately, at the same points
/// that already did so before this provider existed (new session created,
/// user explicitly switches).
final displayedSessionProvider =
    NotifierProvider<DisplayedSessionNotifier, String?>(() {
      return DisplayedSessionNotifier();
    });

class DisplayedSessionNotifier extends Notifier<String?> {
  @override
  String? build() {
    // One-time seed from the last-persisted session. Not a `watch`: later
    // changes to Settings.agenticSessionId (e.g. from an explicit switch)
    // must not implicitly override what `show` was told to display.
    return ref.read(settingsProvider).agenticSessionId;
  }

  void show(String? sessionId) {
    state = sessionId;
  }
}

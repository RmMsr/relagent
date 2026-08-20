import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot request to jump the Settings page to a specific tab.
///
/// Used when returning to Settings from a nested screen (e.g. Voice Models'
/// "Review Settings" action) needs to land on a specific tab — the
/// Connection tab, where credential/URL fields live — regardless of
/// whichever tab was last active. [SettingsPage] consumes and [clear]s the
/// request as soon as it applies it, so it doesn't refire on the next
/// unrelated rebuild.
class SettingsTabRequestNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void requestTab(int index) => state = index;

  void clear() => state = null;
}

final settingsTabRequestProvider =
    NotifierProvider.autoDispose<SettingsTabRequestNotifier, int?>(
      SettingsTabRequestNotifier.new,
    );

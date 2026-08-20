import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the currently-active connection settings (base URL + credentials
/// for whichever backend is selected) are trusted to be correct right now.
///
/// Defaults to `true` — an untouched session inherits whatever already
/// works. [invalidate] resets it to `false` the moment something relevant
/// changes (URL, backend, credential fields); [markVerified] records the
/// result the next time it's actually tested (the Test Connection buttons,
/// or Apply's own live check on the Settings page).
///
/// This is what lets Apply, when pressed from a screen with no access to
/// the credential fields (e.g. Voice Models), decide whether it's safe to
/// commit and leave silently or whether it needs to send the user back to
/// Settings first.
class CredentialsPassNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void invalidate() => state = false;

  void markVerified(bool passed) => state = passed;
}

final credentialsPassProvider =
    NotifierProvider.autoDispose<CredentialsPassNotifier, bool>(
      CredentialsPassNotifier.new,
    );

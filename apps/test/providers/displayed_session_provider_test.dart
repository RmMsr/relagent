import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/displayed_session_provider.dart';
import 'package:relagent/providers/settings_provider.dart';

class _StubSettingsNotifier extends SettingsNotifier {
  final String? sessionId;
  _StubSettingsNotifier({this.sessionId});

  @override
  Settings build() => Settings.defaults().copyWith(agenticSessionId: sessionId);

  @override
  Future<String?> getEnginePassword({String? url}) async => null;

  @override
  Future<String?> getEngineApiKey({String? url}) async => null;
}

ProviderContainer _makeContainer({String? sessionId}) {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _StubSettingsNotifier(sessionId: sessionId),
      ),
    ],
  );
}

void main() {
  group('DisplayedSessionNotifier', () {
    test('seeds from Settings.agenticSessionId on first read', () {
      final container = _makeContainer(sessionId: 'restored-session');
      addTearDown(container.dispose);

      expect(container.read(displayedSessionProvider), 'restored-session');
    });

    test('seeds null when no session was persisted', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      expect(container.read(displayedSessionProvider), isNull);
    });

    test('show() updates the displayed session', () {
      final container = _makeContainer(sessionId: 'a');
      addTearDown(container.dispose);

      container.read(displayedSessionProvider.notifier).show('b');

      expect(container.read(displayedSessionProvider), 'b');
    });

    test('show() does not write through to Settings', () {
      final container = _makeContainer(sessionId: 'a');
      addTearDown(container.dispose);

      container.read(displayedSessionProvider.notifier).show('b');

      expect(
        container.read(settingsProvider).agenticSessionId,
        'a',
        reason:
            'displayedSessionProvider is decoupled from Settings — '
            'callers persist explicitly at their own trigger points',
      );
    });

    test('show(null) clears the displayed session', () {
      final container = _makeContainer(sessionId: 'a');
      addTearDown(container.dispose);

      container.read(displayedSessionProvider.notifier).show(null);

      expect(container.read(displayedSessionProvider), isNull);
    });
  });
}

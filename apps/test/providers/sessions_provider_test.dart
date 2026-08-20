import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentic_client/agentic_client.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/sessions_provider.dart';
import 'package:relagent/providers/settings_provider.dart';

class _StubSettingsNotifier extends SettingsNotifier {
  @override
  Settings build() => Settings.defaults();

  @override
  Future<String?> getEnginePassword({String? url}) async => null;

  @override
  Future<String?> getEngineApiKey({String? url}) async => null;
}

ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: [settingsProvider.overrideWith(() => _StubSettingsNotifier())],
  );
}

SessionInfo _session(String id, DateTime updatedAt, {String? title}) {
  return SessionInfo(
    sessionId: id,
    title: title,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('SessionsNotifier.bumpActivity', () {
    test('moves the bumped session to the top of the list', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);

      final t0 = DateTime.utc(2025, 1, 1);
      notifier.addSession(_session('a', t0, title: 'A'));
      notifier.addSession(_session('b', t0, title: 'B'));
      notifier.addSession(_session('c', t0, title: 'C'));
      // addSession inserts at the front, so the list is currently [c, b, a].

      notifier.bumpActivity('a', DateTime.utc(2025, 6, 1));

      final ids = container
          .read(sessionsProvider)
          .sessions
          .map((s) => s.sessionInfo.sessionId);
      expect(ids.first, 'a');
      expect(ids.toList(), containsAll(['a', 'b', 'c']));
    });

    test('updates the timestamp without touching title or other fields', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);

      final created = DateTime.utc(2025, 1, 1);
      notifier.addSession(_session('a', created, title: 'Original title'));

      final bumped = DateTime.utc(2025, 6, 1);
      notifier.bumpActivity('a', bumped);

      final info = container.read(sessionsProvider).sessions.first.sessionInfo;
      expect(info.updatedAt, bumped);
      expect(info.title, 'Original title');
      expect(info.createdAt, created);
    });

    test('preserves isActive when bumping the currently active session', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);

      notifier.addSession(_session('a', DateTime.utc(2025, 1, 1)));
      notifier.updateActiveSession('a');

      notifier.bumpActivity('a', DateTime.utc(2025, 6, 1));

      expect(container.read(sessionsProvider).sessions.first.isActive, isTrue);
    });

    test('no-ops if the session is not in the list', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);

      notifier.addSession(_session('a', DateTime.utc(2025, 1, 1)));

      notifier.bumpActivity('never-added', DateTime.utc(2025, 6, 1));

      expect(container.read(sessionsProvider).sessions.length, 1);
    });

    test(
      'no-ops if the timestamp is not strictly newer than what is shown',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(sessionsProvider.notifier);

        final current = DateTime.utc(2025, 6, 1);
        notifier.addSession(_session('a', current));

        notifier.bumpActivity('a', DateTime.utc(2020, 1, 1));

        final info = container
            .read(sessionsProvider)
            .sessions
            .first
            .sessionInfo;
        expect(
          info.updatedAt,
          current,
          reason:
              'an out-of-order/older event must not regress an '
              'already-newer displayed timestamp',
        );
      },
    );
  });
}

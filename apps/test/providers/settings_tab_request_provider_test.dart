import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/settings_tab_request_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('build defaults to null (no pending tab request)', () {
    expect(container.read(settingsTabRequestProvider), isNull);
  });

  test('requestTab sets the requested index', () {
    container.read(settingsTabRequestProvider.notifier).requestTab(0);
    expect(container.read(settingsTabRequestProvider), 0);
  });

  test('clear resets the request back to null', () {
    container.read(settingsTabRequestProvider.notifier).requestTab(0);
    container.read(settingsTabRequestProvider.notifier).clear();
    expect(container.read(settingsTabRequestProvider), isNull);
  });

  test(
    'stays alive across an event-loop turn while something is watching it',
    () async {
      final sub = container.listen(
        settingsTabRequestProvider,
        (previous, next) {},
      );
      container.read(settingsTabRequestProvider.notifier).requestTab(0);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(settingsTabRequestProvider), 0);
      sub.close();
    },
  );
}

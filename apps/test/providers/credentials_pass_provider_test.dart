import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/providers/credentials_pass_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('build defaults to true (untouched session is trusted)', () {
    expect(container.read(credentialsPassProvider), isTrue);
  });

  test('invalidate sets state to false', () {
    container.read(credentialsPassProvider.notifier).invalidate();
    expect(container.read(credentialsPassProvider), isFalse);
  });

  test('markVerified(true) sets state to true', () {
    container.read(credentialsPassProvider.notifier).invalidate();
    container.read(credentialsPassProvider.notifier).markVerified(true);
    expect(container.read(credentialsPassProvider), isTrue);
  });

  test('markVerified(false) sets state to false', () {
    container.read(credentialsPassProvider.notifier).markVerified(false);
    expect(container.read(credentialsPassProvider), isFalse);
  });

  test('invalidate after a successful verify goes back to false', () {
    container.read(credentialsPassProvider.notifier).markVerified(true);
    container.read(credentialsPassProvider.notifier).invalidate();
    expect(container.read(credentialsPassProvider), isFalse);
  });

  test('stays alive across an event-loop turn while something is watching it',
      () async {
    final sub = container.listen(credentialsPassProvider, (previous, next) {});
    container.read(credentialsPassProvider.notifier).invalidate();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(credentialsPassProvider), isFalse);
    sub.close();
  });
}

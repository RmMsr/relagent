import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:relagent_cli/settings_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SettingsStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('relagent_cli_test_');
    store = SettingsStore(file: File(p.join(tempDir.path, 'settings.ini')));
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('readEngineUrl returns null when nothing has been written', () {
    expect(store.readEngineUrl(), isNull);
  });

  test('writeEngineUrl persists a value readEngineUrl then returns', () {
    store.writeEngineUrl('http://engine.example.com');
    expect(store.readEngineUrl(), 'http://engine.example.com');
  });

  test('clear removes the persisted file entirely', () {
    store.writeEngineUrl('http://engine.example.com');
    expect(store.file.existsSync(), isTrue);

    store.clear();

    expect(store.file.existsSync(), isFalse);
    expect(store.readEngineUrl(), isNull);
  });

  test('clear is a no-op when nothing was ever persisted', () {
    expect(() => store.clear(), returnsNormally);
    expect(store.readEngineUrl(), isNull);
  });

  test(
    'readAlwaysPurgeChatSession returns null when nothing has been written',
    () {
      expect(store.readAlwaysPurgeChatSession(), isNull);
    },
  );

  test(
    'writeAlwaysPurgeChatSession persists a value '
    'readAlwaysPurgeChatSession then returns',
    () {
      store.writeAlwaysPurgeChatSession(true);
      expect(store.readAlwaysPurgeChatSession(), isTrue);

      store.writeAlwaysPurgeChatSession(false);
      expect(store.readAlwaysPurgeChatSession(), isFalse);
    },
  );

  test(
    'writeAlwaysPurgeChatSession does not clobber the persisted engine URL',
    () {
      store.writeEngineUrl('http://engine.example.com');
      store.writeAlwaysPurgeChatSession(true);

      expect(store.readEngineUrl(), 'http://engine.example.com');
      expect(store.readAlwaysPurgeChatSession(), isTrue);
    },
  );
}

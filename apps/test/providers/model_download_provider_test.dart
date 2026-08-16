import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/voice/model_download_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Redirects path_provider's cache directory to a temp directory for testing.
class _FakeCachePathProvider extends PathProviderPlatform {
  final String cachePath;
  _FakeCachePathProvider(this.cachePath);

  @override
  Future<String?> getApplicationCachePath() async => cachePath;

  @override
  Future<String?> getTemporaryPath() async => cachePath;
}

/// Fails the first [failCount] calls, then "succeeds" by writing a real
/// .complete marker so listDownloadedModels() picks it up on refresh —
/// mirrors what a real resumed download looks like from the provider's
/// perspective.
class _FlakyModelDownloadService extends ModelDownloadService {
  _FlakyModelDownloadService(this.failCount);
  final int failCount;
  int callCount = 0;

  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    callCount++;
    if (callCount <= failCount) {
      throw Exception('simulated failure $callCount');
    }
    final dir = Directory(await getModelPath(entry));
    await dir.create(recursive: true);
    await File('${dir.path}/.complete').writeAsString('done');
  }
}

/// Always fails, simulating a connection that never manages to finish.
class _AlwaysFailingModelDownloadService extends ModelDownloadService {
  int callCount = 0;

  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    callCount++;
    throw Exception('simulated failure $callCount');
  }
}

/// Returns normally without extracting anything, simulating a deliberate
/// cancelDownload() call (ModelDownloadService.downloadModel() does the
/// same: no exception, nothing saved).
class _CancellingModelDownloadService extends ModelDownloadService {
  int callCount = 0;

  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    callCount++;
  }
}

/// Doesn't complete until the test explicitly signals it to via [gates], so
/// tests can control exactly when each concurrent download finishes.
class _ControlledModelDownloadService extends ModelDownloadService {
  final Map<String, Completer<void>> gates = {};

  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    await gates.putIfAbsent(entry.id, () => Completer<void>()).future;
    final dir = Directory(await getModelPath(entry));
    await dir.create(recursive: true);
    await File('${dir.path}/.complete').writeAsString('done');
  }
}

/// Records every enable/disable call instead of touching a real platform
/// channel — WakelockPlus has no default test implementation.
class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  final List<bool> calls = [];
  bool _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async {
    calls.add(enable);
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    final fixture =
        await File('test/fixtures/voice-models.json').readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  late _FakeWakelockPlatform fakeWakelock;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('model_dl_provider_test_');
    PathProviderPlatform.instance = _FakeCachePathProvider(tempDir.path);
    fakeWakelock = _FakeWakelockPlatform();
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('downloadModel retries a failed attempt and succeeds once the '
      'service recovers', () async {
    final fake = _FlakyModelDownloadService(2);
    final container = ProviderContainer(
      overrides: [modelDownloadServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(modelDownloadProvider.notifier)
        .downloadModel('zipformer-en-kroko');

    expect(fake.callCount, 3);
    final state = container.read(modelDownloadProvider);
    expect(state.error, isNull);
    expect(state.isDownloaded('zipformer-en-kroko'), isTrue);
    expect(state.lastCompletedModelName, 'English - Zipformer');
  });

  test('downloadModel gives up after repeated failures and surfaces an '
      'error instead of retrying forever', () async {
    final fake = _AlwaysFailingModelDownloadService();
    final container = ProviderContainer(
      overrides: [modelDownloadServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(modelDownloadProvider.notifier)
        .downloadModel('zipformer-en-kroko');

    expect(fake.callCount, greaterThan(1));
    final state = container.read(modelDownloadProvider);
    expect(state.error, contains('Download failed'));
    expect(state.isDownloaded('zipformer-en-kroko'), isFalse);
  });

  test('a cancelled download does not retry and does not show a false '
      '"downloaded" notification', () async {
    final fake = _CancellingModelDownloadService();
    final container = ProviderContainer(
      overrides: [modelDownloadServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(modelDownloadProvider.notifier)
        .downloadModel('zipformer-en-kroko');

    // A clean cancel returns normally (no exception) — the retry loop must
    // not mistake that for "keep trying," and the completion notification
    // must not fire for a model that was never actually saved.
    expect(fake.callCount, 1);
    final state = container.read(modelDownloadProvider);
    expect(state.lastCompletedModelName, isNull);
    expect(state.isDownloaded('zipformer-en-kroko'), isFalse);
  });

  test('downloadModel holds a wakelock for the duration of the download, '
      'including across retries, and releases it once done', () async {
    final fake = _FlakyModelDownloadService(2);
    final container = ProviderContainer(
      overrides: [modelDownloadServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(modelDownloadProvider.notifier)
        .downloadModel('zipformer-en-kroko');

    // One enable/disable pair despite 3 attempts — the lock must be held
    // across the whole retry loop, not re-acquired per attempt.
    expect(fakeWakelock.calls, [true, false]);
  });

  test('wakelock stays held while a second concurrent download is still '
      'in flight, and only releases once both finish', () async {
    final fake = _ControlledModelDownloadService();
    final container = ProviderContainer(
      overrides: [modelDownloadServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(modelDownloadProvider.notifier);

    final future1 = notifier.downloadModel('zipformer-en-kroko');
    final future2 = notifier.downloadModel('zipformer-fr-kroko');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fakeWakelock.calls, [true]);

    fake.gates['zipformer-en-kroko']!.complete();
    await future1;
    expect(fakeWakelock.calls, [true]); // still held: second is in flight

    fake.gates['zipformer-fr-kroko']!.complete();
    await future2;
    expect(fakeWakelock.calls, [true, false]);
  });
}

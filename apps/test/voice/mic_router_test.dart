import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/voice/mic_router.dart';
import 'package:relagent/voice/voice_service.dart';
import 'package:relagent/voice/voice_service_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const micChannel = MethodChannel('com.relagent.mic_router');
  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  void mockMicChannel(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(micChannel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    // audio_session: accept configuration, report setActive success.
    messenger.setMockMethodCallHandler(audioSessionChannel, (call) async {
      if (call.method == 'setActive') return true;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(micChannel, null);
    messenger.setMockMethodCallHandler(audioSessionChannel, null);
  });

  group('MicRouter facade', () {
    test('listInputs parses device maps', () async {
      mockMicChannel((call) async {
        expect(call.method, 'listInputs');
        return [
          {
            'id': 3,
            'category': 'bluetooth',
            'name': 'BT Headset',
            'address': 'AA:BB',
          },
          {'id': 1, 'category': 'builtin', 'name': 'Phone', 'address': ''},
        ];
      });
      final router = MicRouter(supportedOverride: true);
      final devices = await router.listInputs();
      expect(devices, hasLength(2));
      expect(devices.first.category, MicDeviceCategory.bluetooth);
      expect(devices.first.address, 'AA:BB');
    });

    test('listInputs degrades to empty list on channel error', () async {
      mockMicChannel((call) async {
        throw PlatformException(code: 'boom');
      });
      final router = MicRouter(supportedOverride: true);
      expect(await router.listInputs(), isEmpty);
    });

    test('ensureReady sends preference and parses result', () async {
      mockMicChannel((call) async {
        expect(call.method, 'ensureReady');
        expect(call.arguments, {
          'mode': 'pinned',
          'category': 'bluetooth',
          'address': 'AA:BB',
        });
        return {
          'status': 'ok',
          'device': {
            'id': 3,
            'category': 'bluetooth',
            'name': 'BT Headset',
            'address': 'AA:BB',
          },
        };
      });
      final router = MicRouter(supportedOverride: true);
      final result = await router.ensureReady(
        const MicPreference.pinned(
          category: MicDeviceCategory.bluetooth,
          address: 'AA:BB',
          name: 'BT Headset',
        ),
      );
      expect(result.status, MicSelectionStatus.ok);
      expect(result.device?.category, MicDeviceCategory.bluetooth);
    });

    test('ensureReady surfaces timeout status', () async {
      mockMicChannel((call) async => {'status': 'timeout', 'device': null});
      final router = MicRouter(supportedOverride: true);
      final result = await router.ensureReady(const MicPreference.auto());
      expect(result.status, MicSelectionStatus.timeout);
    });

    test('ensureReady degrades to error result on channel failure', () async {
      mockMicChannel((call) async {
        throw PlatformException(code: 'boom');
      });
      final router = MicRouter(supportedOverride: true);
      final result = await router.ensureReady(const MicPreference.auto());
      expect(result.status, MicSelectionStatus.error);
      expect(result.device, isNull);
    });

    test('unsupported platform makes no channel calls', () async {
      mockMicChannel((call) async => fail('channel must not be called'));
      final router = MicRouter(supportedOverride: false);
      final result = await router.ensureReady(const MicPreference.auto());
      expect(result.status, MicSelectionStatus.unsupported);
      expect(await router.listInputs(), isEmpty);
      await router.releaseAfterIdle();
      await router.releaseNow();
      expect(calls, isEmpty);
    });

    test('release calls are fire-and-forget and swallow errors', () async {
      mockMicChannel((call) async {
        throw PlatformException(code: 'boom');
      });
      final router = MicRouter(supportedOverride: true);
      await router.releaseAfterIdle();
      await router.releaseNow();
      expect(calls.map((c) => c.method), ['releaseAfterIdle', 'releaseNow']);
    });
  });

  group('NativeVoiceService routing sequence', () {
    NativeVoiceService buildService() =>
        NativeVoiceService(micRouter: MicRouter(supportedOverride: true));

    test(
      'recording configuration establishes the route via ensureReady',
      () async {
        mockMicChannel((call) async => {'status': 'ok', 'device': null});
        final service = buildService();
        await service.configureAudioSessionForRecording();
        expect(calls.map((c) => c.method), contains('ensureReady'));
      },
    );

    test('preference set on the service reaches ensureReady', () async {
      mockMicChannel((call) async => {'status': 'ok', 'device': null});
      final service = buildService();
      service.setInputDevicePreference(
        const MicPreference.pinned(category: MicDeviceCategory.builtin),
      );
      await service.configureAudioSessionForRecording();
      final ensureReady = calls.singleWhere((c) => c.method == 'ensureReady');
      expect((ensureReady.arguments as Map)['mode'], 'pinned');
      expect((ensureReady.arguments as Map)['category'], 'builtin');
    });

    test(
      'stopRecording schedules idle release (route kept for follow-ups)',
      () async {
        mockMicChannel((call) async => null);
        final service = buildService();
        await service.stopRecording();
        expect(calls.map((c) => c.method), ['releaseAfterIdle']);
      },
    );

    test('playback configuration releases the route immediately', () async {
      mockMicChannel((call) async => null);
      final service = buildService();
      await service.configureAudioSessionForPlayback();
      expect(calls.map((c) => c.method), contains('releaseNow'));
    });
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '/providers/invocation_provider.dart';

String? _textFromFiles(List<SharedMediaFile> files) {
  for (final f in files) {
    if (f.type == SharedMediaType.text && f.path.isNotEmpty) return f.path;
  }
  return null;
}

/// Listens for incoming shared text (warm intents) and PROCESS_TEXT events,
/// forwarding them to [invocationProvider]. Read once at app startup.
final invocationListenerProvider = Provider<void>((ref) {
  if (kIsWeb) return;

  // Warm share-sheet intents (ACTION_SEND)
  final sub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
    final text = _textFromFiles(files);
    if (text != null) ref.read(invocationProvider.notifier).set(text);
  });
  ref.onDispose(sub.cancel);

  // PROCESS_TEXT warm intents from MainActivity platform channel
  const channel = MethodChannel('com.relagent.process_text');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onProcessText') {
      final text = call.arguments as String?;
      if (text != null && text.isNotEmpty) {
        ref.read(invocationProvider.notifier).set(text);
      }
    }
  });
  ref.onDispose(() => channel.setMethodCallHandler(null));
});

/// Reads the initial (cold-start) shared text from [ReceiveSharingIntent].
/// Returns null on non-mobile platforms or when no text was shared.
Future<String?> getInitialSharedText() async {
  if (kIsWeb) return null;
  try {
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    await ReceiveSharingIntent.instance.reset();
    return _textFromFiles(files);
  } catch (_) {
    return null;
  }
}

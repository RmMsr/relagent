import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/providers/recording_provider.dart';
import '/providers/tts_provider.dart';

/// Wraps [child] in a [Stack] and shows a full-screen semi-transparent overlay
/// with a spinner while [RecordingState.isInitializing] is true.
///
/// The overlay absorbs all touch input during ASR model loading so the user
/// cannot interact with the underlying UI while the main thread is blocked.
class VoiceInitOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const VoiceInitOverlay({required this.child, super.key});

  @override
  ConsumerState<VoiceInitOverlay> createState() => _VoiceInitOverlayState();
}

class _VoiceInitOverlayState extends ConsumerState<VoiceInitOverlay> {
  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      ttsProvider.select((s) => s.initError),
      (previous, error) {
        if (error != null && error != previous) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Voice model failed to load: $error'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Dismiss',
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
            ),
          );
        }
      },
    );

    final isInitializing = ref.watch(
      recordingProvider.select((s) => s.isInitializing),
    );

    return Stack(
      children: [
        widget.child,
        if (isInitializing) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0x80000000)),
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.mic, size: 40),
                    SizedBox(height: 16),
                    Text(
                      'Initializing voice recognition…',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This may take a few seconds.\nPlease wait.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

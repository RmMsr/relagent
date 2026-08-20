import 'package:flutter/material.dart';

/// Back/play-pause/forward row shown once a message's TTS playback has
/// focus, replacing the single play button. [outlined] and [iconSize] let
/// each call site match its existing single-button styling.
class TtsChunkControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final bool outlined;
  final double iconSize;

  const TtsChunkControls({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSkipPrevious,
    required this.onSkipNext,
    this.outlined = false,
    this.iconSize = 18,
  });

  Widget _button(IconData icon, String tooltip, VoidCallback onPressed) {
    if (outlined) {
      return IconButton.outlined(
        icon: Icon(icon, size: iconSize),
        iconSize: iconSize,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }
    return IconButton(
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.skip_previous, 'Previous', onSkipPrevious),
        const SizedBox(width: 4),
        _button(
          isPlaying ? Icons.pause : Icons.play_arrow,
          isPlaying ? 'Pause' : 'Resume',
          onPlayPause,
        ),
        const SizedBox(width: 4),
        _button(Icons.skip_next, 'Next', onSkipNext),
      ],
    );
  }
}

/// Animates between a single button (idle/generating/completed/error) and
/// [TtsChunkControls] (playing/paused).
class AnimatedTtsControls extends StatelessWidget {
  final bool showChunkControls;
  final Widget singleButton;
  final Widget chunkControls;

  const AnimatedTtsControls({
    super.key,
    required this.showChunkControls,
    required this.singleButton,
    required this.chunkControls,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axis: Axis.horizontal,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: showChunkControls
          ? KeyedSubtree(
              key: const ValueKey('chunk-controls'),
              child: chunkControls,
            )
          : KeyedSubtree(
              key: const ValueKey('single-button'),
              child: singleButton,
            ),
    );
  }
}

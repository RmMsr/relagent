import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/voice/model_resolver.dart';

/// Task 10.6: Verify that the app handles missing bundled assets gracefully.
///
/// When no model is selected (selectedAsrModelId == null) and no bundled asset
/// is configured (AppConfig returns null), the resolver returns null and the
/// app should enter the "model unavailable" state without crashing.
void main() {
  group('Graceful degradation — no models available', () {
    test('resolveAsrMetadata returns null with default settings (no selection)',
        () async {
      // Default settings have no selectedAsrModelId
      final settings = Settings.defaults();
      expect(settings.selectedAsrModelId, isNull);

      final result = await resolveAsrMetadata(
        settings,
        const ModelDownloadState(),
      );

      expect(
        result,
        isNull,
        reason: 'No model selected and no downloads → resolver returns null',
      );
    });

    test('resolveTtsModel returns null with default settings (no selection)',
        () async {
      final settings = Settings.defaults();
      expect(settings.selectedTtsModelId, isNull);

      final result = await resolveTtsModel(
        settings,
        const ModelDownloadState(),
      );

      expect(
        result,
        isNull,
        reason: 'No model selected and no downloads → resolver returns null',
      );
    });

    test(
        'ModelDownloadState.isDownloaded returns false for all catalog entries '
        'when no models are downloaded', () {
      final emptyState = const ModelDownloadState();
      for (final entry in ModelCatalog.entries) {
        expect(
          emptyState.isDownloaded(entry.id),
          isFalse,
          reason: '${entry.id} should not appear downloaded in empty state',
        );
      }
    });

    test('ModelCatalog.entries is non-empty even without bundled assets', () {
      // The catalog is hardcoded — it should always have entries regardless of
      // whether any models are bundled in assets or downloaded.
      expect(ModelCatalog.entries, isNotEmpty);
    });

    test(
        'getSelectedTtsSpeakerCount falls back to bundled Kokoro (54 speakers) '
        'when no TTS model is selected', () {
      // When no model is selected, the bundled Kokoro is the implicit fallback.
      // 54 is expected; this documents the fallback behaviour.
      final settings = Settings.defaults();
      expect(getSelectedTtsSpeakerCount(settings), 54);
    });
  });
}
